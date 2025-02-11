unit u_radio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fgl, u_utils, u_song;

type
  TRadioStatus = (rsPaused, rsPlaying, rsError);

  TFactionDistanceData = record
    FactionName: string;
    DistanceKm: double;
  end;
  TFactionDistanceDataArray = array of TFactionDistanceData;
  PFactionDistanceDataArray = ^TFactionDistanceDataArray;

  TRadioStationSlotTrack = class
  private
    _track: TPlayableAudioTrack;
    _status: TSongStatus;
    _volume: double;
    _timer: integer;
    _stoptime: qword;
    _onlineretrytimer: qword;
    _onlinestoptimer: qword;
    _isactive: boolean;
    function int_GetFileName: string;
    function int_GetLength: integer;
    function int_GetPos: integer;
    procedure int_SetPos(pos: integer);
    function int_GetStatus: TSongStatus;
    function int_IsOnline: boolean;
  public
    constructor Create(track: TPlayableAudioTrack);
    destructor Destroy; override;
    procedure Update(newStatus: TSongStatus; newVolume: double; currentTime: qword; active: boolean);
    property FileName: string read int_GetFileName;
    property LengthMs: integer read int_GetLength;
    property PositionMs: integer read int_GetPos write int_SetPos;
    property Status: TSongStatus read int_GetStatus;
    property IsOnline: boolean read int_IsOnline;
    property Volume: double read _volume;
  end;

  TRadioStationSlotTrackList = specialize TFPGList<TRadioStationSlotTrack>;

  TRadioStationSlot = class
  private
    _ismp3: boolean;
    _mp3index: integer;
    _tracks: TRadioStationSlotTrackList;
    _owners: TStringArray;
    _lf: double;
    _df: double;
    _status: TSongStatus;
    _isactive: boolean;
    _volume: double;
  public
    _suppression: double; // Helps improve overlapping radio stations slots over time!
    constructor Create(ownerList: TStringArray; fileName: string; loudFactor, dampFactor: double);
    constructor Create(ownerList: TStringArray; track: TPlayableAudioTrack; loudFactor, dampFactor: double);
    constructor Create(files: TStrings; loudFactor: double); // Dedicated MP3 player slot
    destructor Destroy; override;
    function GetBaseVolume(factionData: PFactionDistanceDataArray): double; // Based solely on faction ownerships and distances
    function GetClosestDistance(factionData: PFactionDistanceDataArray): double; // Based solely on faction ownerships and distances
    function CheckOwnerListCompatibility(lst: TStringArray): boolean;
    function IsValid: boolean;
    procedure SetRandomPos(MaxRandomPos: double);
    procedure ReplayCurrTrack;
    procedure SkipNextTrack;
    procedure Process(newVolume: double; playbackStatus: TSongStatus; bIsActiveSlot: boolean);
    procedure GenerateReport(lst: TStrings; indentationLevel: integer);
    property IsMP3Slot: boolean read _ismp3;
    property LoudnessFactor: double read _lf;
    property DampeningFactor: double read _df;
    property Status: TSongStatus read _status;
    property RealMusicVolume: double read _volume;
  end;

  TRadioStationSlotList = specialize TFPGList<TRadioStationSlot>;

  TRadioStation = class
  private
    _slots: TRadioStationSlotList;
    _data: PFactionDistanceDataArray;
    _rsname: string;
    _status: TRadioStatus;
    _volume: double;
    _mastervol: double;
    procedure int_SetMasterVol(vol: double);
    procedure int_AdjustSuppression(index, loudestIndex: integer; loudestVolume: double);
  public
    constructor Create;
    constructor Create(files: TStrings; loudFactor: double);
    destructor Destroy; override;
    function CheckSlotOwnerListCompatibility(lst: TStringArray): boolean;
    function AddRadioSlot(Owners: TStringArray; FileName: string; LoudnessFactor, DampeningFactor: double): boolean;
    function AddRadioSlot(Owners: TStringArray; Track: TPlayableAudioTrack; LoudnessFactor, DampeningFactor: double): boolean;
    function IsValid: boolean;
    procedure SetRandomPos(MaxRandomPos: double);
    procedure SkipNextTrack;
    procedure ReplayCurrTrack;
    procedure Process(DistanceData: PFactionDistanceDataArray; Volume: double; CurrentStatus: TRadioStatus; IsActiveRadio: boolean);
    procedure GenerateReport(lst: TStrings; indentationLevel: integer);
    property Status: TRadioStatus read _status;
    property RadioStationName: string read _rsname write _rsname;
    property MasterVolume: double read _mastervol write int_SetMasterVol;
  end;

  TRadioStationList = specialize TFPGList<TRadioStation>;

implementation

{################
 TRadioStationSlotTrack
 ################}

function TRadioStationSlotTrack.int_GetFileName: string;
begin
  Result := _track.FileName;
end;

function TRadioStationSlotTrack.int_GetLength: integer;
begin
  Result := _track.LengthMs;
end;

function TRadioStationSlotTrack.int_GetPos: integer;
begin
  if _isactive then
     Result := _track.PositionMs
  else
     Result := _timer;
end;

procedure TRadioStationSlotTrack.int_SetPos(pos: integer);
begin
  if _isactive then
     _track.PositionMs := pos
  else
     begin
       if (pos < 0) then
          pos := 0;
       _timer := pos;
     end;
end;

function TRadioStationSlotTrack.int_GetStatus: TSongStatus;
begin
  // Errored out?
  if (_status = ssError) then
     exit(ssError);

  // Fake status report
  if _isactive then
     _status := _track.Status
  else if (_timer > _track.LengthMs) and (not _track.IsOnlineStream) then
     _status := ssStopped;
  Result := _status;
end;

function TRadioStationSlotTrack.int_IsOnline: boolean;
begin
  Result := _track.IsOnlineStream;
end;

constructor TRadioStationSlotTrack.Create(track: TPlayableAudioTrack);
begin
  inherited Create;
  _track := track;
  _timer := 0;
  _stoptime := 0;
  _onlinestoptimer := 0;
  _onlineretrytimer := 0;
  _isactive := false;
  Update(ssStopped, 0.0, 0, false);
end;

destructor TRadioStationSlotTrack.Destroy;
begin
  _track.Free;
  inherited;
end;

procedure TRadioStationSlotTrack.Update(newStatus: TSongStatus; newVolume: double; currentTime: qword; active: boolean);
var
  st: TSongStatus;
  wasActive: boolean;
begin
  // Set data
  st := int_GetStatus; // It is important, that we query this BEFORE setting _isactive
  wasActive := _isactive;
  _isactive := active;
  _volume := NormalizeFloat(newVolume, 0.0, 1.0);

  // Status code check and update
  if (st <> ssError) then
     begin
       if (st in [ssStopped, ssNone]) then
          begin
            _timer := 0;
            _stoptime := currentTime;
          end;
       if (not (st in [ssPaused, ssPlaying])) and (newStatus = ssPaused) then
          newStatus := ssStopped
       else if (newStatus = ssError) or (newStatus = ssNone) then
          newStatus := ssStopped;
       _status := newStatus;
     end

  // Errored-out online track reset
  else if _track.IsOnlineStream  then
     begin
       if (_onlineretrytimer = 0) then
          _onlineretrytimer := currentTime;
       if (currentTime >= (_onlineretrytimer + 60000)) then // Retry after 1 min
          begin
            // Do not allow sudden loud sound burst! Can only attempt reconnect, if just activated agian!
            if (not _isactive) or (not wasActive) then
               begin
                 _onlineretrytimer := 0;
                 _status := ssStopped;
                 _track.ResetOnlineStatus;
               end;
          end;
     end;

  // Update track
  if (_status = ssPaused) then
     begin
       if (_onlinestoptimer = 0) then
          _onlinestoptimer := currentTime;
       if _isactive then
          begin
           if (not _track.IsOnlineStream) or (currentTime > (_onlinestoptimer + 5000)) then
              _track.Status := ssPaused
           else
              _track.Volume := 0.0; // Online streams are only stopped after 5 seconds of consistent requests
          end
       else
          begin
            if wasActive then
               _timer := _track.PositionMs;
            _stoptime := currentTime;
            if (not _track.IsOnlineStream) or (currentTime > (_onlinestoptimer + 5000)) then
              _track.Status := ssStopped
            else
              _track.Volume := 0.0; // Online streams are only stopped after 5 seconds of consistent requests
          end;
     end
  else if (_status = ssPlaying) then
     begin
       // Active state
       if _isactive then
          begin
            _onlinestoptimer := 0;
            // State change: inactive -> active
            if (not wasActive) then
               begin
                 if (_timer > _track.LengthMs) and (not _track.IsOnlineStream) then
                    begin
                      _status := ssStopped;
                      _timer := 0;
                    end
                 else
                    begin
                      _track.Status := ssPlaying;
                      _track.Volume := _volume;
                      _track.PositionMs := _timer;
                    end;
               end
            // State not changed
            else
               begin
                 if (_track.Status <> ssPlaying) then
                     _track.Status := ssPlaying;
                  _track.Volume := _volume;
               end;
          end
       // Inactive state
       else
          begin
            // State change: active -> inactive
             if wasActive then
                begin
                  _onlinestoptimer := currentTime;
                  _timer := _track.PositionMs;
                  _stoptime := currentTime;
                  if _track.IsOnlineStream then
                     _track.Volume := 0.0 // Don't stop the online track yet!
                  else
                     _track.Status := ssStopped;
                end

             // State not changed
             else
                begin
                  if (not _track.IsOnlineStream) or (currentTime > (_onlinestoptimer + 5000)) then
                     _track.Status := ssStopped
                  else
                     _track.Volume := 0.0; // Online streams are only stopped after 5 seconds of consistent requests
                  _timer := _timer + (currentTime - _stoptime); // Progress the phantom playback!
                  _stoptime := currentTime;
                  if (_timer >_track.LengthMs) then
                     begin
                       _status := ssStopped;
                       _timer := 0;
                     end;
                end;
          end;
     end
  else
     begin
       if (_onlinestoptimer = 0) then
          _onlinestoptimer := currentTime;
       if (not _track.IsOnlineStream) or (currentTime > (_onlinestoptimer + 5000)) then
          _track.Status := ssStopped
       else
          _track.Volume := 0.0; // Online streams are only stopped after 5 seconds of consistent requests
       _timer := 0;
     end;
end;

{################
 TRadioStationSlot
 ################}

constructor TRadioStationSlot.Create(ownerList: TStringArray; fileName: string; loudFactor, dampFactor: double);
var
  track: TPlayableAudioTrack;
begin
  _ismp3 := false;
  _owners := Copy(ownerList);
  _tracks := TRadioStationSlotTrackList.Create;
  _lf := loudFactor;
  _df := dampFactor;
  _isactive := false;
  _suppression := 0.0;
  track := TPlayableAudioTrack.Create(fileName);
  if (track.Status <> ssError) then
     _tracks.Add(TRadioStationSlotTrack.Create(track))
  else
     track.Free;
  Process(0.0, ssStopped, false);
end;

constructor TRadioStationSlot.Create(ownerList: TStringArray; track: TPlayableAudioTrack; loudFactor, dampFactor: double);
begin
  _ismp3 := false;
  _owners := Copy(ownerList);
  _tracks := TRadioStationSlotTrackList.Create;
  _lf := loudFactor;
  _df := dampFactor;
  _isactive := false;
  _suppression := 0.0;
  if (track.Status <> ssError) then
     _tracks.Add(TRadioStationSlotTrack.Create(track));
  Process(0.0, ssStopped, false);
end;

constructor TRadioStationSlot.Create(files: TStrings; loudFactor: double);
var
  i: integer;
  track: TPlayableAudioTrack;
begin
  _ismp3 := true;
  _mp3index := 0;
  SetLength(_owners, 0);
  _tracks := TRadioStationSlotTrackList.Create;
  _lf := loudFactor;
  _df := 1.0;
  _isactive := false;
  _suppression := 0.0;
  for i := 0 to files.Count - 1 do
      begin
        track := TPlayableAudioTrack.Create(files[i]);
        if (track.Status <> ssError) then
           _tracks.Add(TRadioStationSlotTrack.Create(track))
        else
           track.Free;
      end;
  Process(0.0, ssStopped, false);
end;

destructor TRadioStationSlot.Destroy;
var
  i: integer;
begin
  SetLength(_owners, 0);
  for i := 0 to _tracks.Count - 1 do
      _tracks[i].Free;
  _tracks.Free;
  inherited;
end;

function TRadioStationSlot.GetBaseVolume(factionData: PFactionDistanceDataArray): double;
var
  i, j: integer;
  d: double;
begin
  if _ismp3 or (not IsValid) or (Length(_owners) = 0) or (factionData = nil) then
     exit(1.0);

  // Calculates the desired volume level, based on faction ownerships, distances, and dampening factor
  Result := 0.0;
  for i := 0 to High(_owners) do
      for j := 0 to High(factionData^) do
          if (CompareText(_owners[i], factionData^[j].FactionName) = 0) then
             begin
               if (factionData^[j].DistanceKm > 0.0) then
                  d := power(_df, factionData^[j].DistanceKm)
               else
                  d := 1.0;
               if (d > Result) then
                  Result := d;
             end;
  Result := Result * _lf;
end;

function TRadioStationSlot.GetClosestDistance(factionData: PFactionDistanceDataArray): double; // Based solely on faction ownerships and distances
var
  i, j: integer;
  d: double;
begin
  if _ismp3 or (not IsValid) or (Length(_owners) = 0) or (factionData = nil) then
     exit(1.0);

  // Calculate the closest distance
  Result := double.MaxValue;
  for i := 0 to High(_owners) do
      for j := 0 to High(factionData^) do
          if (CompareText(_owners[i], factionData^[j].FactionName) = 0) then
             begin
               d := factionData^[j].DistanceKm;
               if (d < Result) then
                  Result := d;
             end;
end;

function TRadioStationSlot.CheckOwnerListCompatibility(lst: TStringArray): boolean;
var
  i, j: integer;
begin
  if _ismp3 then
     exit(false); // MP3 is never compatible

  if (Length(_owners) = 0) or (Length(lst) = 0) then
     exit(false); // Empty owner lists collide with everything

  for i := 0 to High(lst) do
      for j := 0 to High(_owners) do
          if (CompareText(lst[i], _owners[j]) = 0) then
             exit(false); // Ownership collision

  // No collision
  exit(true);
end;

function TRadioStationSlot.IsValid: boolean;
var
  i: integer;
begin
  for i := 0 to _tracks.Count - 1 do
      if _tracks[i].IsOnline or (_tracks[i].Status <> ssError) then
         exit(true); // One online or valid track is enough
  exit(false);
end;

procedure TRadioStationSlot.SetRandomPos(MaxRandomPos: double);
begin
  if (not _ismp3) and IsValid then
     _tracks[0].PositionMs := round(random * _tracks[0].LengthMs * MaxRandomPos);
end;

procedure TRadioStationSlot.ReplayCurrTrack;
begin
  if _ismp3 and IsValid then
     _tracks[_mp3index].PositionMs := 0;
end;

procedure TRadioStationSlot.SkipNextTrack;
begin
  if _ismp3 and IsValid then
     begin
       _tracks[_mp3index].Update(ssStopped, _volume, 0, _isactive);
       Process(_volume, _status, _isactive);
     end;
end;

procedure TRadioStationSlot.Process(newVolume: double; playbackStatus: TSongStatus; bIsActiveSlot: boolean);
var
  currentTime: qword;
  i: integer;
begin
  currentTime := GetTickCount64;

  // Setup data
  _volume := NormalizeFloat(newVolume, 0.0, 1.0);
  if (playbackStatus = ssError) or (playbackStatus = ssNone) then
     playbackStatus := ssStopped;
  _status := playbackStatus;
  _isactive := bIsActiveSlot;

  // Do process
  if (_status = ssPaused) then
     begin
       for i := 0 to _tracks.Count - 1 do
           _tracks[i].Update(ssPaused, _volume, currentTime, _isactive);
     end
  else if (_status = ssPlaying) then
     begin
       if _ismp3 then
          begin
            if _tracks[_mp3index].Status in [ssStopped, ssNone, ssError] then
               begin
                 inc(_mp3index);
                 if (_mp3index >= _tracks.Count) then
                    _mp3index := 0;
               end;
            _tracks[_mp3index].Update(ssPlaying, _volume, currentTime, _isactive);
          end
       else
          _tracks[0].Update(ssPlaying, _volume, currentTime, _isactive);
     end
  else
     begin
       for i := 0 to _tracks.Count - 1 do
           _tracks[i].Update(ssStopped, _volume, currentTime, _isactive);
     end;
end;

procedure TRadioStationSlot.GenerateReport(lst: TStrings; indentationLevel: integer);
var
  i: integer;
  indentString: string;
begin
  // Proper indentation
  if (indentationLevel < 0) then
     indentationLevel := 0;
  indentString := '';
  for i := 1 to indentationLevel do
      indentString := indentString + #9;

  // Generate report
  if IsValid then
     begin
       lst.Add(indentString + 'MP3 Player: %s', [BoolToStr(_ismp3, true)]);
       lst.Add(indentString + Format('Loudness factor: %.8f', [_lf], X4OrsFormatSettings));
       lst.Add(indentString + Format('Dampening factor: %.8f', [_df], X4OrsFormatSettings));
       lst.Add(indentString + 'Owner(s):');
       for i := 0 to High(_owners) do
           lst.Add(indentString + #9'%s', [_owners[i]]);
       lst.Add(indentString + 'File(s):');
       for i := 0 to _tracks.Count - 1 do
           lst.Add(indentString + #9'%s', [_tracks[i].FileName]);
     end
  else
     lst.Add('Invalid slot!');
end;

{################
   TRadioStation
 ################}

procedure TRadioStation.int_SetMasterVol(vol: double);
begin
  _mastervol := NormalizeFloat(vol, 0.0, 1.0);
end;

procedure TRadioStation.int_AdjustSuppression(index, loudestIndex: integer; loudestVolume: double);
var
  locLoudFactor, locDampFactor, distance, step, adjustment: double;
begin
  // Limit input to valid ranges
  locLoudFactor := NormalizeFloat(_slots[loudestIndex].LoudnessFactor, 0.01, 1.0);
  locDampFactor := NormalizeFloat(_slots[loudestIndex].DampeningFactor, 0.01, 1.0);
  loudestVolume := NormalizeFloat(loudestVolume, 0.0, 1.0);

  // Calculate adjustment
  distance := NormalizeFloat(_slots[loudestIndex].GetClosestDistance(_data), 1.0, 1000000.0); // Limit to valid range
  step := locLoudFactor * locDampFactor * distance;
  if (step < 0.001) then
     step := 0.001; // Limit to valid range
  adjustment := NormalizeFloat(((locLoudFactor * loudestVolume) / step) / _slots.Count, 0.0, loudestVolume * 0.25); // Limit to valid range

  // Adjust
  if (index = loudestIndex) then
     _slots[index]._suppression := _slots[index]._suppression - adjustment
  else
     _slots[index]._suppression := _slots[index]._suppression + adjustment;
  _slots[index]._suppression := NormalizeFloat(_slots[index]._suppression, 0.0, loudestVolume);
end;

constructor TRadioStation.Create;
begin
  inherited;
  _slots := TRadioStationSlotList.Create;
  _rsname := '';
  _mastervol := 0.0;
  Process(nil, 0.0, rsPlaying, false);
end;

constructor TRadioStation.Create(files: TStrings; loudFactor: double);
begin
  inherited Create;
  _slots := TRadioStationSlotList.Create;
  _rsname := '';
  _mastervol := loudFactor;
  _slots.Add(TRadioStationSlot.Create(files, 1.0));
  Process(nil, 0.0, rsPlaying, false);
end;

destructor TRadioStation.Destroy;
var
  i: integer;
begin
  for i := 0 to _slots.Count - 1 do
      _slots[i].Free;
  _slots.Free;
  inherited;
end;

function TRadioStation.CheckSlotOwnerListCompatibility(lst: TStringArray): boolean;
var
  i: integer;
begin
  for i := 0 to _slots.Count - 1 do
      if (not _slots[i].CheckOwnerListCompatibility(lst)) or _slots[i].IsMP3Slot then
         exit(false); // Ownership collision

  // No collision
  exit(true);
end;

function TRadioStation.AddRadioSlot(Owners: TStringArray; FileName: string; LoudnessFactor, DampeningFactor: double): boolean;
var
  slot: TRadioStationSlot;
begin
  if (_status = rsError) or (not CheckSlotOwnerListCompatibility(Owners)) then
     exit(false);

  // Create track
  slot := TRadioStationSlot.Create(Owners, FileName, LoudnessFactor, DampeningFactor);
  if (not slot.IsValid) then
     begin
       slot.Free;
       exit(false);
     end;

  // Now can add slot
  _slots.Add(slot);
  exit(true);
end;

function TRadioStation.AddRadioSlot(Owners: TStringArray; Track: TPlayableAudioTrack; LoudnessFactor, DampeningFactor: double): boolean;
begin
  if (_status = rsError) or (Track.Status = ssError) or (not CheckSlotOwnerListCompatibility(Owners)) then
     exit(false);

  // Now can add slot
  _slots.Add(TRadioStationSlot.Create(Owners, Track, LoudnessFactor, DampeningFactor));
  exit(true);
end;

function TRadioStation.IsValid: boolean;
var
  i: integer;
begin
  for i := 0 to _slots.Count - 1 do
      if _slots[i].IsValid then
         exit(true); // One valid slot is enough
  exit(false);
end;

procedure TRadioStation.SetRandomPos(MaxRandomPos: double);
var
  i: integer;
begin
  if (not IsValid) or (_status = rsError) then
     exit;

  // Randomize pos
  for i := 0 to _slots.Count - 1 do
      _slots[i].SetRandomPos(MaxRandomPos);
end;

procedure TRadioStation.SkipNextTrack;
var
  i: integer;
begin
  if (not IsValid) or (_status = rsError) then
     exit;

  // Skip to next track
  for i := 0 to _slots.Count - 1 do
      _slots[i].SkipNextTrack;
end;

procedure TRadioStation.ReplayCurrTrack;
var
  i: integer;
begin
  if (not IsValid) or (_status = rsError) then
     exit;

  // Replay current track
  for i := 0 to _slots.Count - 1 do
      _slots[i].ReplayCurrTrack;
end;

procedure TRadioStation.Process(DistanceData: PFactionDistanceDataArray; Volume: double; CurrentStatus: TRadioStatus; IsActiveRadio: boolean);
var
  i, locLoudestIndex: integer;
  locVol, locCalcVol, locLoudestVol, locSlotVol: double;
begin
  if (not IsValid) then
     exit;

  // Store external data
  _data := DistanceData;
  if (CurrentStatus = rsError) then
     CurrentStatus := rsPaused;
  if (_status <> rsError) then
     _status := CurrentStatus;
  _volume := NormalizeFloat(Volume, 0.0, 1.0);
  locVol := _volume * _mastervol;

  // Process
  if (_status = rsPaused) then
     begin
       for i := 0 to _slots.Count - 1 do
           _slots[i].Process(0.0, ssPaused, IsActiveRadio);
     end
  else if (_status = rsPlaying) then
     begin
       if IsActiveRadio then
          begin
            locLoudestIndex := 0;
            locLoudestVol := 0;
            for i := 0 to _slots.Count - 1 do
                begin
                  locSlotVol := _slots[i].GetBaseVolume(_data);
                  if (locSlotVol > locLoudestVol) then
                     begin
                       locLoudestVol := locSlotVol;
                       locLoudestIndex := i;
                     end;
                end;
            for i := 0 to _slots.Count - 1 do
                begin
                  locSlotVol := _slots[i].GetBaseVolume(_data);
                  if (locLoudestVol > 0.0) then
                     locCalcVol := power(locSlotVol / locLoudestVol, 8.75) * locSlotVol
                  else
                     locCalcVol := locSlotVol;
                  int_AdjustSuppression(i, locLoudestIndex, locLoudestVol);
                  locCalcVol := locCalcVol - _slots[i]._suppression;
                  _slots[i].Process(locCalcVol * locVol, ssPlaying, true);
                end;
          end
       else
          begin
            for i := 0 to _slots.Count - 1 do
                begin
                  _slots[i]._suppression := 0.0;
                  _slots[i].Process(0.0, ssPlaying, false);
                end;
          end;
     end
  else
     begin
       for i := 0 to _slots.Count - 1 do
           _slots[i].Process(0.0, ssStopped, false);
     end;
end;

procedure TRadioStation.GenerateReport(lst: TStrings; indentationLevel: integer);
var
  i: integer;
  indentString: string;
begin
  // Proper indentation
  if (indentationLevel < 0) then
     indentationLevel := 0;
  indentString := '';
  for i := 1 to indentationLevel do
      indentString := indentString + #9;

  // Generate report
  if IsValid then
     begin
       lst.Add(indentString + 'Name: %s', [_rsname]);
       lst.Add(indentString + Format('Master volume: %.8f', [_mastervol], X4OrsFormatSettings));
       lst.Add(indentString + 'Slot(s):');
       for i := 0 to _slots.count - 1 do
           begin
             lst.Add(indentString + #9'Slot %d:', [i + 1]);
             _slots[i].GenerateReport(lst, indentationLevel + 2);
           end;
     end
  else
     lst.Add('Invalid radio station!');
end;

end.


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

  TRadioStationSlot = record
    Owners: TStringArray;
    LoudnessFactor, DampeningFactor: double;
    Tracks: TPlayableAudioTrackList;
  end;
  TRadioStationSlotArray = array of TRadioStationSlot;

  TRadioStation = class
  private
    _slots: TRadioStationSlotArray;
    _data: PFactionDistanceDataArray;
    _ismp3: boolean;
    _mp3index: integer;
    _rsname: string;
    _status: TRadioStatus;
    _volume: double;
    _mastervol: double;
    procedure int_SetStatus(st: TRadioStatus);
    procedure int_SetMasterVol(vol: double);
    function int_IsValid: boolean;
    function int_GetSlotBaseVolume(index: integer): double;
    function int_GetSlotCalculatedVolume(index: integer): double;
    function int_NewSlot(owners: TStringArray; lf, df: double): integer;
  public
    constructor Create;
    constructor Create(files: TStrings);
    destructor Destroy; override;
    procedure AddRadioSlot(Owners: TStringArray; FileName: string; LoudnessFactor, DampeningFactor: double);
    procedure AddRadioSlot(Owners: TStringArray; Track: TPlayableAudioTrack; LoudnessFactor, DampeningFactor: double);
    procedure SetRandomPos(MaxRandomPos: double);
    procedure SkipNextTrack;
    procedure ReplayCurrTrack;
    procedure Process(DistanceData: PFactionDistanceDataArray; Volume: double);
    procedure WriteReport(fn: string);
    property IsValid: boolean read int_IsValid;
    property IsMP3Station: boolean read _ismp3;
    property Status: TRadioStatus read _status write int_SetStatus;
    property RadioStationName: string read _rsname write _rsname;
    property MasterVolume: double read _mastervol write int_SetMasterVol;
  end;

  TRadioStationList = specialize TFPGList<TRadioStation>;

implementation

procedure TRadioStation.int_SetStatus(st: TRadioStatus);
begin
  if (_status = rsError) or (st = rsError) then
     exit;
  _status := st;
  Process(_data, _volume);
end;

procedure TRadioStation.int_SetMasterVol(vol: double);
begin
  _mastervol := vol;
  if (_mastervol < 0.0) then
     _mastervol := 0.0
  else if (_mastervol > 1.0) then
     _mastervol := 1.0;
  Process(_data, _volume);
end;

function TRadioStation.int_IsValid: boolean;
var
  i, j: integer;
begin
  for i := 0 to High(_slots) do
      begin
        for j := 0 to _slots[i].Tracks.Count - 1 do
            if (_slots[i].Tracks[j].Status <> ssError) then
               exit(true);
      end;
  exit(false);
end;

function TRadioStation.int_GetSlotBaseVolume(index: integer): double;
var
  i, j: integer;
  d: double;
begin
  if (not IsValid) or _ismp3 or (index < 0) or (index > High(_slots)) or (_data = nil) or (Length(_slots[index].Owners) <= 0) then
     exit(1.0);

  // Calculates the desired volume level of the selected slot, based on radio station type, and faction station distance
  Result := 0.0;
  for i := 0 to High(_slots[index].Owners) do
      for j := 0 to High(_data^) do
          if (CompareText(_slots[index].Owners[i], _data^[j].FactionName) = 0) then
             begin
               // Multi-Owner check. The loudest loudness wins!
               if (_data^[j].DistanceKm > 0.0) then
                  d := power(_slots[index].DampeningFactor,_data^[j].DistanceKm)
               else
                  d := 1.0;
               if (d > Result) then
                  Result := d;
             end;
  Result := Result * _slots[index].LoudnessFactor;
end;

function TRadioStation.int_GetSlotCalculatedVolume(index: integer): double;
var
  i: integer;
  loudestVol, currentVol: double;
begin
  if (not IsValid) or _ismp3 or (index < 0) or (index > High(_slots)) or (_data = nil) or (Length(_slots[index].Owners) <= 0) then
     exit(_volume);

  // Slot base volume
  Result := int_GetSlotBaseVolume(index);

  // Calculates the desired volume level of the selected slot, taking other slots into consideration
  loudestVol := 0.0;
  for i := 0 to High(_slots) do
      begin
        currentVol := int_GetSlotBaseVolume(i);
        if (currentVol > loudestVol) then
           loudestVol := currentVol;
      end;
  if (loudestVol > 0.0) then
     Result := (Result / loudestVol) * Result;

  // Adjust with volume
  Result := Result * _volume;
end;

function TRadioStation.int_NewSlot(owners: TStringArray; lf, df: double): integer;
begin
  if (lf < 0.0) then
     lf := 0.0
  else if (lf > 1.0) then
     lf := 1.0;
  if (df < 0.0) then
     df := 0.0
  else if (df > 1.0) then
     df := 1.0;
  SetLength(_slots, Length(_slots) + 1);
  Result := High(_slots);
  _slots[Result].Owners := owners;
  _slots[Result].LoudnessFactor := lf;
  _slots[Result].DampeningFactor := df;
  _slots[Result].Tracks := TPlayableAudioTrackList.Create;
end;

constructor TRadioStation.Create;
begin
  inherited;
  SetLength(_slots, 0);
  _ismp3 := false;
  _status := rsPlaying;
  _rsname := '';
  _mastervol := 0.0;
  Process(nil, 0.0);
end;

constructor TRadioStation.Create(files: TStrings);
var
  i, h: integer;
  track: TPlayableAudioTrack;
  empty_arr: TStringArray;
begin
  inherited Create;
  SetLength(_slots, 0);
  _ismp3 := true;
  _mp3index := 0;
  _status := rsPlaying;
  _rsname := '';
  _mastervol := 0.0;
  SetLength(empty_arr, 0);
  h := int_NewSlot(empty_arr, 1.0, 1.0);
  for i := 0 to files.Count - 1 do
      begin
        track := TPlayableAudioTrack.Create(files[i]);
        if (track.Status <> ssError) then
           _slots[h].Tracks.Add(track)
        else
           track.Free;
      end;
  Process(nil, 0.0);
end;

destructor TRadioStation.Destroy;
var
  i, j: integer;
begin
  for i := 0 to High(_slots) do
      begin
        SetLength(_slots[i].Owners, 0);
        for j := 0 to _slots[i].Tracks.Count - 1 do
            _slots[i].Tracks[j].Free;
        _slots[i].Tracks.Free;
      end;
  SetLength(_slots, 0);
  inherited;
end;

procedure TRadioStation.AddRadioSlot(Owners: TStringArray; FileName: string; LoudnessFactor, DampeningFactor: double);
var
  track: TPlayableAudioTrack;
begin
  if _ismp3 or (_status = rsError) then
     exit;
  track := TPlayableAudioTrack.Create(FileName);
  if (track.Status <> ssError) then
     AddRadioSlot(Owners, track, LoudnessFactor, DampeningFactor)
  else
     track.Free;
end;

procedure TRadioStation.AddRadioSlot(Owners: TStringArray; Track: TPlayableAudioTrack; LoudnessFactor, DampeningFactor: double);
var
  h: integer;
begin
  if _ismp3 or (_status = rsError) then
     exit;
  if (Track.Status <> ssError) then
     begin
       h := int_NewSlot(Owners, LoudnessFactor, DampeningFactor);
       _slots[h].Tracks.Add(Track);
       Process(_data, _volume);
     end;
end;

procedure TRadioStation.SetRandomPos(MaxRandomPos: double);
var
  i: integer;
begin
  if not IsValid or (_status = rsError) then
     exit;
  if _ismp3 then
     begin
       if (_slots[0].Tracks[_mp3index].Status in [ssPlaying, ssPaused]) then
          _slots[0].Tracks[_mp3index].Status := ssStopped;
       _mp3index := random(_slots[0].Tracks.Count);
       Process(_data, _volume);
     end
  else
     begin
       if (MaxRandomPos > 1.0) or (MaxRandomPos < 0.0) then
          MaxRandomPos := 0.0;
       for i := 0 to High(_slots) do
           if (_slots[i].Tracks.Count > 0) then
              _slots[i].Tracks[0].PositionMs := round(_slots[i].Tracks[0].LengthMs * MaxRandomPos * random);
     end;
end;

procedure TRadioStation.SkipNextTrack;
begin
  if (not IsValid) or (not _ismp3) or (_status = rsError) then
     exit;
  _slots[0].Tracks[_mp3index].Status := ssStopped;
  Process(_data, _volume);
end;

procedure TRadioStation.ReplayCurrTrack;
begin
  if (not IsValid) or (not _ismp3) or (_status = rsError) then
     exit;
  _slots[0].Tracks[_mp3index].PositionMs := 0;
end;

procedure TRadioStation.Process(DistanceData: PFactionDistanceDataArray; Volume: double);
var
  i, j: integer;
begin
  // Store external data
  _data := DistanceData;
  _volume := Volume;
  if (_volume > 1.0) then
     _volume := 1.0
  else if (_volume < 0.0) then
     _volume := 0.0;

  // Do process
  if (not IsValid) or (_status = rsError) then
     exit;
  if (_status = rsPaused) then
     begin
       for i := 0 to High(_slots) do
           for j := 0 to _slots[i].Tracks.Count - 1 do
               if (_slots[i].Tracks[j].Status = ssPlaying) then
                  _slots[i].Tracks[j].Status := ssPaused;
     end
  else if (_status = rsPlaying) then
     begin
       if _ismp3 then
          begin
            if (_slots[0].Tracks[_mp3index].Status in [ssStopped, ssError]) then // ssError - will consider errored-out tracks to be finished
               begin
                 inc(_mp3index);
                 if (_mp3index >= _slots[0].Tracks.Count) then
                    _mp3index := 0;
                 _slots[0].Tracks[_mp3index].Status := ssPlaying;
               end
            else if (_slots[0].Tracks[_mp3index].Status = ssPaused) then
               _slots[0].Tracks[_mp3index].Status := ssPlaying;
            _slots[0].Tracks[_mp3index].Volume := _volume;
            for i := 0 to _slots[0].Tracks.Count - 1 do
                if (i <> _mp3index) then
                   _slots[0].Tracks[i].Status := ssStopped;
          end
       else
          begin
            for i := 0 to High(_slots) do
                if (_slots[i].Tracks.Count > 0) then
                   begin
                     if (_slots[i].Tracks[0].Status in [ssPaused, ssStopped]) then
                        _slots[i].Tracks[0].Status := ssPlaying;
                     _slots[i].Tracks[0].Volume := int_GetSlotCalculatedVolume(i);
                   end;
          end;
     end
  else
     begin
       for i := 0 to High(_slots) do
           for j := 0 to _slots[i].Tracks.Count - 1 do
               if (_slots[i].Tracks[j].Status in [ssPlaying, ssPaused]) then
                  _slots[i].Tracks[j].Status := ssStopped;
     end;
end;

procedure TRadioStation.WriteReport(fn: string);
var
  f: System.Text;
  i, j: integer;
begin
  System.Assign(f, fn);
  {$I-}
  Rewrite(f);
  if (not IsValid) then
     writeln(f, 'Invalid radio station!')
  else if _ismp3 then
     begin
       writeln(f, 'MP3 Report:');
       for i := 0 to _slots[0].Tracks.Count - 1 do
           writeln(f, _slots[0].Tracks[i].FileName);
     end
  else
     begin
       writeln(f, 'Radio Station Report:');
       writeln(f, Format('Slots: %d', [Length(_slots)]));
       for i := 0 to High(_slots) do
           begin
             writeln(f, Format('Slot number: %d', [i + 1]));
             writeln(f, Format('File name: %s', [_slots[i].Tracks[0].FileName]));
             writeln(f, Format('Loudness factor: %f', [_slots[i].LoudnessFactor], X4OrsFormatSettings));
             writeln(f, Format('Dampening factor: %f', [_slots[i].DampeningFactor], X4OrsFormatSettings));
             writeln(f, 'Owners:');
             for j := 0 to High(_slots[i].Owners) do
                 writeln(f, Format(#9'%s', [_slots[i].Owners[j]]));
           end;
     end;
  System.Close(f);
  {$I+}
end;

end.


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
    Owners: array of string;
    LoudnessFactor, DampeningFactor: double;
  end;
  TRadioStationSlotArray = array of TRadioStationSlot;

  TRadioStation = class
  private
    slots: TRadioStationSlotArray;
    _isforcemp3: boolean;
    _mp3index: integer;
    _tracks: TPlayableAudioTrackList;
    _status: TRadioStatus;
    _mastervol, _progmastervol: double;
    _linearvol: boolean;
    _factiondata: PFactionDistanceDataArray;
    _rsname: string;
    procedure int_SetStatus(st: TRadioStatus);
    procedure int_SetVolume(vol: double);
    function int_IsValid: boolean;
    function int_GetCalculatedVolume(index: integer): double;
    function int_GetInterpolatedVolume(index: integer): double;
    function int_GetSlotFinalVolume(index: integer): double;
  public
    constructor Create;
    constructor Create(files: TStrings);
    destructor Destroy; override;
    procedure AddRadioSlot(Owners: TStringArray; FileName: string; LoudnessFactor, DampeningFactor: double);
    procedure SetRandomPos;
    procedure SkipNextTrack;
    procedure ReplayCurrTrack;
    procedure Process;
    procedure Update(DistanceData: PFactionDistanceDataArray; ProgramMasterVolume: double; UseLinearVolume: boolean);
    procedure WriteReport(fn: string);
    property IsValid: boolean read int_IsValid;
    property IsMP3Station: boolean read _isforcemp3;
    property Status: TRadioStatus read _status write int_SetStatus;
    property Volume: double read _mastervol write int_SetVolume;
    property RadioStationName: string read _rsname write _rsname;
  end;

  TRadioStationList = specialize TFPGList<TRadioStation>;

implementation

procedure TRadioStation.int_SetStatus(st: TRadioStatus);
begin
  if ((_status = rsError) or (st = rsError)) then
     exit;
  _status := st;
  Process;
end;

procedure TRadioStation.int_SetVolume(vol: double);
begin
  if (vol > 1.0) then
     vol := 1.0
  else if (vol < 0.0) then
     vol := 0.0;
  _mastervol := vol;
  Process;
end;

function TRadioStation.int_IsValid: boolean;
begin
  Result := (_tracks.Count > 0) and (_isforcemp3 or (Length(slots) = _tracks.Count));
end;

function TRadioStation.int_GetCalculatedVolume(index: integer): double;
var
  i, j: integer;
  d: double;
begin
  // Calculates the desired volume level of the selected slot, based on radio station type, and faction station distance
  Result := 1.0;
  if (not _isforcemp3) and (index >= 0) and (index <= High(slots)) and IsValid and Assigned(_factiondata) and (Length(slots[index].Owners) > 0) then
     begin
       Result := 0.0;
       for i := 0 to High(slots[index].Owners) do
           for j := 0 to High(_factiondata^) do
               if (CompareText(slots[index].Owners[i], _factiondata^[j].FactionName) = 0) then
                  begin
                    // Multi-Owner check. The loudest loudness wins!
                    if (_factiondata^[j].DistanceKm > 0.0) then
                       d := power(slots[index].DampeningFactor,_factiondata^[j].DistanceKm)
                    else
                       d := 1.0;
                    if (d > Result) then
                       Result := d;
                  end;
       Result := Result * slots[index].LoudnessFactor;
     end;
end;

function TRadioStation.int_GetInterpolatedVolume(index: integer): double;
var
  i: integer;
  loudestVol, currentVol: double;
begin
  Result := int_GetCalculatedVolume(index);

  // Calculates the desired volume level of the selected slot, taking other slots into consideration
  if (not _isforcemp3) and (index >= 0) and (index <= High(slots)) and IsValid and Assigned(_factiondata) and (Length(slots[index].Owners) > 0) then
     begin
       loudestVol := int_GetCalculatedVolume(0);
       for i := 0 to High(slots) do
           begin
             currentVol := int_GetCalculatedVolume(i);
             if (currentVol > loudestVol) then
                loudestVol := currentVol;
           end;
       if (loudestVol > 0.0) then
          Result := (Result / loudestVol) * Result;
     end;
end;

function TRadioStation.int_GetSlotFinalVolume(index: integer): double;
begin
  // Adjust the volume with the Playback conditions
  Result := int_GetInterpolatedVolume(index) * _mastervol * _progmastervol;
  if _linearvol then
     Result := (2 * Result) - (Result * Result);
end;

constructor TRadioStation.Create;
begin
  inherited;
  SetLength(slots, 0);
  _isforcemp3 := false;
  _tracks := TPlayableAudioTrackList.Create;
  _status := rsPlaying;
  _mastervol := 1.0;
  _progmastervol := 0.0;
  _linearvol := false;
  _factiondata := nil;
  _rsname := '';
  Process;
end;

constructor TRadioStation.Create(files: TStrings);
var
  i: integer;
  track: TPlayableAudioTrack;
begin
  inherited Create;
  SetLength(slots, 0);
  _isforcemp3 := true;
  _mp3index := 0;
  _tracks := TPlayableAudioTrackList.Create;
  _status := rsPlaying;
  _mastervol := 1.0;
  _progmastervol := 0.0;
  _linearvol := false;
  _factiondata := nil;
  _rsname := '';
  for i := 0 to files.Count - 1 do
      begin
        track := TPlayableAudioTrack.Create(files[i]);
        if (track.Status <> ssError) then
           _tracks.Add(track)
        else
           track.Free;
      end;
  Process;
end;

destructor TRadioStation.Destroy;
var
  i: integer;
begin
  for i := 0 to _tracks.Count - 1 do
      _tracks[i].Free;
  _tracks.Free;
  SetLength(slots, 0);
  inherited;
end;

procedure TRadioStation.AddRadioSlot(Owners: TStringArray; FileName: string; LoudnessFactor, DampeningFactor: double);
var
  track: TPlayableAudioTrack;
begin
  if not _isforcemp3 then
     begin
       track := TPlayableAudioTrack.Create(FileName);
       if (track.Status <> ssError) then
          begin
            SetLength(slots, Length(slots) + 1);
            slots[High(slots)].Owners := Owners;
            slots[High(slots)].LoudnessFactor := LoudnessFactor;
            slots[High(slots)].DampeningFactor := DampeningFactor;
            _tracks.Add(track);
            Process;
          end
       else
          track.Free;
     end;
end;

procedure TRadioStation.SetRandomPos;
var
  i: integer;
begin
  if _isforcemp3 then
     begin
       if (_tracks.Count > 0) then
          begin
            if (_tracks[_mp3index].Status in [ssPlaying, ssPaused]) then
               _tracks[_mp3index].Status := ssStopped;
            _mp3index := random(_tracks.Count);
            Process;
          end;
     end
  else
     begin
       for i := 0 to _tracks.Count - 1 do
           _tracks[i].PositionMs := round(_tracks[i].LengthMs * random * 0.775); // 0.775, so the position won't be at the end!
     end;
end;

procedure TRadioStation.SkipNextTrack;
begin
  if _isforcemp3 and (_tracks.Count > 0) then
     begin
       if (_tracks[_mp3index].Status in [ssPlaying, ssPaused]) then
          _tracks[_mp3index].Status := ssStopped;
       Process;
     end;
end;

procedure TRadioStation.ReplayCurrTrack;
begin
  if _isforcemp3 and (_tracks.Count > 0) then
     _tracks[_mp3index].PositionMs := 0;
end;

procedure TRadioStation.Process;
var
  i: integer;
begin
  if (_status = rsPaused) then
     begin
       for i := 0 to _tracks.Count - 1 do
           begin
             if (_tracks[i].Status = ssPlaying) then
                _tracks[i].Status := ssPaused;
           end;
     end
  else if (_status = rsPlaying) then
     begin
       if _isforcemp3 then
          begin
            if (_tracks.Count > 0) then
               begin
                 if (_tracks[_mp3index].Status in [ssStopped, ssError]) then // An errored-out MP3 must not make the whole MP3 player station stuck! (ssError)
                    begin
                      inc(_mp3index);
                      if (_mp3index >= _tracks.Count) then
                         _mp3index := 0;
                      _tracks[_mp3index].Volume := int_GetSlotFinalVolume(0);
                      _tracks[_mp3index].Status := ssPlaying;
                    end
                 else if (_tracks[_mp3index].Status = ssPaused) then
                    begin
                      _tracks[_mp3index].Volume := int_GetSlotFinalVolume(0);
                      _tracks[_mp3index].Status := ssPlaying;
                    end
                 else
                    _tracks[_mp3index].Volume := int_GetSlotFinalVolume(0);
                 for i := 0 to _tracks.Count - 1 do
                     if (i <> _mp3index) and (_tracks[i].Status in [ssPlaying, ssPaused]) then
                        _tracks[_mp3index].Status := ssStopped;
               end;
          end
       else
          begin
            for i := 0 to _tracks.Count - 1 do
                begin
                  if (_tracks[i].Status in [ssPaused, ssStopped]) then
                     _tracks[i].Status := ssPlaying;
                  _tracks[i].Volume := int_GetSlotFinalVolume(i);
                end;
          end;
     end
  else
     begin
       for i := 0 to _tracks.Count - 1 do
           if (_tracks[i].Status = ssPlaying) then
              _tracks[i].Status := ssStopped;
     end;
end;

procedure TRadioStation.Update(DistanceData: PFactionDistanceDataArray; ProgramMasterVolume: double; UseLinearVolume: boolean);
begin
  _factiondata := DistanceData;
  _progmastervol := ProgramMasterVolume;
  _linearvol := UseLinearVolume;
  Process;
end;

procedure TRadioStation.WriteReport(fn: string);
var
  f: System.Text;
  i, j: integer;
begin
  System.Assign(f, fn);
  {$I-}
  Rewrite(f);
  if _isforcemp3 then
     begin
       writeln(f, 'MP3 Report:');
       for i := 0 to _tracks.Count - 1 do
           writeln(f, _tracks[i].FileName);
     end
  else
     begin
       writeln(f, 'Radio Station Report:');
       if IsValid then
          begin
            writeln(f, Format('Slots: %d', [Length(slots)]));
            for i := 0 to High(slots) do
                begin
                  writeln(f, Format('Slot number: %d', [i + 1]));
                  writeln(f, Format('File name: %s', [_tracks[i].FileName])); // NOTE: Because IsValid only returns true for a non-MP3 station, if slots count = tracks count, then this is totally safe
                  writeln(f, Format('Loudness factor: %f', [slots[i].LoudnessFactor], X4OrsFormatSettings));
                  writeln(f, Format('Dampening factor: %f', [slots[i].DampeningFactor], X4OrsFormatSettings));
                  writeln(f, 'Owners:');
                  for j := 0 to High(slots[i].Owners) do
                      writeln(f, Format(#9'%s', [slots[i].Owners[j]]));
                end;
          end;
     end;
  System.Close(f);
  {$I+}
end;

end.


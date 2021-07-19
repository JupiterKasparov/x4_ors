unit u_radio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl, u_logger, u_song;

type
  TPlayableAudioTrackList = specialize TFPGList<TPlayableAudioTrack>;

  TRadioStation = class
  private
    _ismp3, _errored: boolean;
    _tracks: TPlayableAudioTrackList;
    _curr_index: integer;
    function IsValid: boolean;
    procedure Initialize(files: TStringArray; bForcedMP3: boolean);
  public
    constructor Create(files: TStringArray; bForcedMP3: boolean = false);
    constructor Create(files: TStrings; bForcedMP3: boolean = false);
    constructor Create(filename: string; bForcedMP3: boolean = false);
    destructor Destroy; override;
    procedure SetPaused(bPaused: boolean);
    procedure SetVolume(vol: double);
    procedure RandomizePosition;
    procedure DoProgress;
    procedure SkipNextTrack;
    procedure Replay;
    property Valid: boolean read IsValid;
    property IsMP3Station: boolean read _ismp3;
  end;

implementation

function TRadioStation.IsValid: boolean;
begin
  exit(_tracks.Count > 0);
end;

procedure TRadioStation.Initialize(files: TStringArray; bForcedMP3: boolean);
var
  i: integer;
  trk: TPlayableAudioTrack;
begin
  _errored := false;
  _tracks := TPlayableAudioTrackList.Create;
  _curr_index := 0;
  _ismp3 := (Length(files) > 1) or bForcedMP3;
  for i := 0 to High(files) do
      begin
        trk := TPlayableAudioTrack.Create(files[i]);
        if (trk.Status <> ssError) then
           _tracks.Add(trk)
        else
           begin
             Log(Format('[RADIO INIT]: Audio file ''%s'' cannot be loaded, error ''%s''!', [files[i], trk.ErrorString]));
             trk.Free;
           end;
        trk := nil;
      end;
end;


constructor TRadioStation.Create(files: TStringArray; bForcedMP3: boolean = false);
begin
  inherited Create;
  Initialize(files, bForcedMP3);
end;

constructor TRadioStation.Create(files: TStrings; bForcedMP3: boolean = false);
var
  filelist: TStringArray;
  i: integer;
begin
  inherited Create;
  SetLength(filelist, files.Count);
  for i := 0 to files.Count - 1 do
      filelist[i] := files[i];
  Initialize(filelist, bForcedMP3);
  SetLength(filelist, 0);
end;

constructor TRadioStation.Create(filename: string; bForcedMP3: boolean = false);
var
  filelist: TStringArray;
begin
  inherited Create;
  SetLength(filelist, 1);
  filelist[0] := filename;
  Initialize(filelist, bForcedMP3);
  SetLength(filelist, 0);
end;

destructor TRadioStation.Destroy;
var
  i: integer;
begin
  for i := 0 to _tracks.Count - 1 do
      _tracks[i].Free;
  _tracks.Clear;
  _tracks.Free;
  inherited;
end;

procedure TRadioStation.SetPaused(bPaused: boolean);
var
  i: integer;
  ri: integer = -1;
begin
  for i := 0 to _tracks.Count - 1 do
      if bPaused then
         begin
           if (_tracks[i].Status = ssPlaying) then
              _tracks[i].Status := ssPaused;
           ri := i;
         end
      else
         begin
           if (_tracks[i].Status = ssPaused) then
              _tracks[i].Status := ssPlaying;
           ri := i;
         end;
  if (ri >= 0) and (_tracks[ri].Status = ssError) then
     begin
       if not _errored then
          Log(Format('[PLAYBACK]: Cannot pause or resume track ''%s''! Error: ''%s''!', [_tracks[ri].FileName, _tracks[ri].ErrorString]));
       _errored := true;
     end
  else
     _errored := false;
end;

procedure TRadioStation.SetVolume(vol: double);
var
  i: integer;
begin
  if (vol > 1.0) then
     vol := 1.0
  else if (vol < 0.0) then
     vol := 0.0;
  for i := 0 to _tracks.Count - 1 do
      _tracks[i].Volume := vol;
end;

procedure TRadioStation.RandomizePosition;
var
  bPaused: boolean;
  ri: integer = -1;
begin
  if IsValid then
     begin
       if _ismp3 then
          begin
            bPaused := _tracks[_curr_index].Status = ssPaused;
            _tracks[_curr_index].Status := ssStopped;
            _curr_index := random(_tracks.Count);
            _tracks[_curr_index].Status := ssPlaying;
            if bPaused then
               _tracks[_curr_index].Status := ssPaused;
            ri := _curr_index;
          end
       else
          begin
            _tracks[0].Status := ssPlaying;
            _tracks[0].PositionMs := round(_tracks[0].LengthMs * random * 0.775); // 0.775, so the position won't be at the end!
            ri := 0;
          end;
     end;
  if (ri >= 0) and (_tracks[ri].Status = ssError) then
     begin
       if not _errored then
          Log(Format('[PLAYBACK]: Cannot randomize position for track ''%s''! Error: ''%s''!', [_tracks[ri].FileName, _tracks[ri].ErrorString]));
       _errored := true;
     end
  else
     _errored := false;
end;

procedure TRadioStation.DoProgress;
var
  ri: integer = -1;
begin
  if IsValid then
     begin
       if _ismp3 then
          begin
            if (_tracks[_curr_index].Status = ssStopped) then
               begin
                 inc(_curr_index);
                 if (_curr_index = _tracks.Count) then
                    _curr_index := 0;
                 _tracks[_curr_index].Status := ssPlaying;
                 ri := _curr_index;
               end;
          end
       else
          begin
            if (_tracks[0].Status = ssStopped) then
               _tracks[0].Status := ssPlaying;
            ri := 0;
          end;
     end;
  if (ri >= 0) and (_tracks[ri].Status = ssError) then
     begin
       if not _errored then
          Log(Format('[PLAYBACK]: Cannot play track ''%s''! Error: ''%s''!', [_tracks[ri].FileName, _tracks[ri].ErrorString]));
       _errored := true;
     end
  else
     _errored := false;
end;

procedure TRadioStation.SkipNextTrack;
var
  ri: integer = -1;
begin
  if IsValid and _ismp3 then
     begin
       if (_tracks[_curr_index].Status = ssPlaying) then
          begin
            _tracks[_curr_index].Status := ssStopped;
            inc(_curr_index);
            if (_curr_index = _tracks.Count) then
               _curr_index := 0;
            _tracks[_curr_index].Status := ssPlaying;
            ri := _curr_index;
          end;
     end;
  if (ri >= 0) and (_tracks[ri].Status = ssError) then
     begin
       if not _errored then
          Log(Format('[PLAYBACK]: Cannot skip MP3 player to track ''%s''! Error: ''%s''!', [_tracks[ri].FileName, _tracks[ri].ErrorString]));
       _errored := true;
     end
  else
     _errored := false;
end;

procedure TRadioStation.Replay;
begin
  if IsValid and _ismp3 then
     begin
       if (_tracks[_curr_index].Status = ssPlaying) then
          _tracks[_curr_index].PositionMs := 0;
     end;
end;

end.


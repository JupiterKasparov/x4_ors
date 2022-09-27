unit u_song;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BASS, u_utils, u_logger, FileUtil;

type
  TSongStatus = (ssNone, ssStopped, ssPaused, ssPlaying, ssError);

  TPlayableAudioTrack = class
  private
    bassSample: HSAMPLE;
    bassChannel: HCHANNEL;
    _isonline, _onlinepaused, _isdummy: boolean;
    _status: TSongStatus;
    _vol: double;
    _filename, _dummyfile, _errorStr: string;
    procedure int_SetError(err: integer);
    function int_GetStatus: TSongStatus;
    procedure int_SetStatus(st: TSongStatus);
    procedure int_SetVolume(vol: double);
    function int_GetLengthMs: integer;
    function int_GetPositionMs: integer;
    procedure int_SetPositionMs(pos: integer);
  public
    constructor Create(fn: string);
    destructor Destroy; override;
    property Status: TSongStatus read int_GetStatus write int_SetStatus;
    property ErrorString: string read _errorStr;
    property Volume: double read _vol write int_SetVolume;
    property LengthMs: integer read int_GetLengthMs;
    property PositionMs: integer read int_GetPositionMs write int_SetPositionMs;
    property IsOnlineStream: boolean read _isonline;
    property FileName: string read _filename;
  end;

var
  bLinearizeVolume: boolean = false;

implementation

var
  tempfilecount: integer = 0;

procedure TPlayableAudioTrack.int_SetError(err: integer);
begin
  _errorStr := Format('BASS error: %d', [err]);
end;

function TPlayableAudioTrack.int_GetStatus: TSongStatus;
var
  s: DWORD;
begin
  if (_status = ssError) then
     exit(ssError);
  s := BASS_ChannelIsActive(bassChannel);
  case s of
       BASS_ACTIVE_STOPPED: Result := ssStopped;
       BASS_ACTIVE_PLAYING, BASS_ACTIVE_STALLED: Result := ssPlaying;
       BASS_ACTIVE_PAUSED: Result := ssPaused;
       else Result := ssStopped;
  end;
  if (Result = ssStopped) and _onlinepaused and _isonline then // To be able to 'pause' an online stream!
     Result := ssPaused;
end;

procedure TPlayableAudioTrack.int_SetStatus(st: TSongStatus);

          procedure InternalPlayTrack;
          begin
            if _isonline then
               bassChannel := BASS_StreamCreateURL(PChar(_filename), 0, BASS_STREAM_BLOCK or BASS_STREAM_AUTOFREE, nil, nil)
            else
               bassChannel := BASS_SampleGetChannel(bassSample, BOOL(0));
            if (bassChannel = 0) then
               begin
                 _status := ssError;
                 int_SetError(BASS_ErrorGetCode);
               end
            else
               begin
                 if _isonline then
                    begin
                      BASS_ChannelPlay(bassChannel, BOOL(0));
                      _onlinepaused  := false;
                    end
                 else
                    BASS_ChannelPlay(bassChannel, BOOL(1));
                 int_SetVolume(_vol);
               end;
          end;

begin
  if (int_GetStatus in [ssNone, ssError]) then
     exit;
  if (st = ssError) or (st = ssNone) then
     st := ssStopped;
   if (st = ssPaused) then
     begin
       if (int_GetStatus = ssPlaying) then
          begin
            if _isonline then
               begin
                 BASS_StreamFree(bassChannel);
                 _onlinepaused := true;
               end
            else
               BASS_ChannelPause(bassChannel);
          end;
     end
  else if (st = ssPlaying) then
     begin
       if (int_GetStatus = ssStopped) then
          InternalPlayTrack
       else if (int_GetStatus = ssPaused) then
          begin
            if _isonline then
               InternalPlayTrack
            else
               BASS_ChannelPlay(bassChannel, BOOL(0));
          end;
     end
  else if (st = ssStopped) then
     begin
       if (int_GetStatus in [ssPlaying, ssPaused]) then
          begin
            if _isonline then
               begin
                 BASS_StreamFree(bassChannel);
                 _onlinepaused  := false;
               end
            else
               BASS_ChannelStop(bassChannel);
          end;
     end;
end;

procedure TPlayableAudioTrack.int_SetVolume(vol: double);
var
  lv: double;
begin
  if (vol > 1.0) then
     vol := 1.0
  else if (vol < 0.0) then
     vol := 0.0;
  _vol := vol;
  if bLinearizeVolume then // If the program must linearize the volume, then explicitly linearize it here!
     lv := (2 * vol) - (vol * vol)
  else
     lv := _vol;
  if not (int_GetStatus in [ssNone, ssError, ssStopped]) then
     BASS_ChannelSetAttribute(bassChannel, BASS_ATTRIB_VOL, lv);
end;

function TPlayableAudioTrack.int_GetLengthMs: integer;
var
  info: BASS_SAMPLE;
begin
  if _isonline then
     exit(-1);
  if (int_GetStatus in [ssNone, ssError]) then
     exit(0);
  BASS_SampleGetInfo(bassSample, info);
  Result := round(BASS_ChannelBytes2Seconds(bassSample, info.length));
end;

function TPlayableAudioTrack.int_GetPositionMs: integer;
begin
  if _isonline then
     exit(-1);
  if (int_GetStatus in [ssNone, ssError, ssStopped]) then
     exit(0);
  Result := round(BASS_ChannelBytes2Seconds(bassChannel, BASS_ChannelGetPosition(bassChannel, BASS_POS_BYTE)));
end;

procedure TPlayableAudioTrack.int_SetPositionMs(pos: integer);
begin
  if _isonline then
     exit;
  if (pos > int_GetLengthMs) then
     exit;
  if (int_GetStatus in [ssPlaying, ssPaused]) then
     BASS_ChannelSetPosition(bassChannel, BASS_ChannelSeconds2Bytes(bassChannel, pos), BASS_POS_BYTE);
end;

constructor TPlayableAudioTrack.Create(fn: string);
begin
  inherited Create;
  _status := ssNone;
  _dummyfile := '';
  _errorStr := '';
  _vol := 1.0;
  _isonline := false;
  _onlinepaused := false;
  _isdummy := false;
  _filename := fn;
  if IsNetFile(_filename) then
     _isonline := true
  else
     begin
       _isonline := false;
       bassSample := BASS_SampleLoad(BOOL(0), PChar(_filename), 0, 0, 1, 0);
       if (bassSample = 0) then
          begin
            // Maybe the filename is bad (cyrillic, etc)? Copy it to TEMP with acceptable filename, and try again, boy!
            Log(Format('[FAILSAFE]: ''%s'' cannot be loaded - maybe because of its file name? Trying to load it from temporary file...', [_filename]));
            _dummyfile := Format('%s\tmp%d%s', [x4_ors_temp_dir, tempfilecount, ExtractFileExt(_filename)]);
            if not DirectoryExists(ExtractFilePath(_dummyfile)) then
               CreateDir(ExtractFilePath(_dummyfile));
            if CopyFile(_filename, _dummyfile, true, false) then
               begin
                 _isdummy := true;
                 bassSample := BASS_SampleLoad(BOOL(0), PChar(_dummyfile), 0, 0, 1, 0);
                 if (bassSample = 0) then
                    begin
                      Log(Format('[FAILSAFE]: Failed to load ''%s'' from temporary file!', [_filename]));
                      _status := ssError;
                      int_SetError(BASS_ErrorGetCode);
                    end
                 else
                     begin
                       Log(Format('[FAILSAFE]: Successfully loaded ''%s'' from temporary file!', [_filename]));
                       _status := ssStopped;
                     end;
                 inc(tempfilecount);
               end
            else
               begin
                 Log(Format('[FAILSAFE]: Failed to create temporary file for ''%s''!', [_filename]));
                 _status := ssError;
                 int_SetError(BASS_ErrorGetCode);
               end;
          end
       else
          _status := ssStopped;
     end;
end;

destructor TPlayableAudioTrack.Destroy;
begin
  int_SetStatus(ssStopped);
  if (_status <> ssError) and (not _isonline) then
     BASS_SampleFree(bassSample);
  if _isdummy and FileExists(_dummyfile) then
     DeleteFile(_dummyfile);
  inherited;
end;

initialization
  BASS_Init(-1, 44100, BASS_DEVICE_NOSPEAKER, 0, nil);
  BASS_SetConfig(BASS_CONFIG_NET_PLAYLIST, 1);
  BASS_SetConfig(BASS_CONFIG_NET_PREBUF_WAIT, 0);
  BASS_SetConfigPtr(BASS_CONFIG_NET_PROXY, nil);

finalization
  BASS_Stop;
  BASS_Free;

end.


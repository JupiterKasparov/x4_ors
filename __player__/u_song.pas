unit u_song;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BASS, FileUtil, u_utils, fgl, u_logger;

type
  TSongStatus = (ssNone, ssStopped, ssPaused, ssPlaying, ssError);

  TPlayableAudioTrack = class
  private
    bassSample: HSAMPLE;
    bassChannel: HCHANNEL;
    _isonline, _onlinestopped: boolean;
    _status: TSongStatus;
    _vol: double;
    _filename: string;
    _errno: integer;
    function int_GetStatus: TSongStatus;
    procedure int_SetStatus(st: TSongStatus);
    procedure int_SetVolume(vol: double);
    function int_GetLengthMs: integer;
    function int_GetPositionMs: integer;
    procedure int_SetPositionMs(pos: integer);
  public
    constructor Create(fn: string);
    destructor Destroy; override;
    function GetErrorInfo: string;
    property Status: TSongStatus read int_GetStatus write int_SetStatus;
    property Volume: double read _vol write int_SetVolume;
    property LengthMs: integer read int_GetLengthMs;
    property PositionMs: integer read int_GetPositionMs write int_SetPositionMs;
    property IsOnlineStream: boolean read _isonline;
    property FileName: string read _filename;
  end;

  TPlayableAudioTrackList = specialize TFPGList<TPlayableAudioTrack>;

implementation

procedure InitOnlineStream(obj: Pointer);
var
  song: TPlayableAudioTrack absolute obj;
  bassChannel: HCHANNEL;
begin
  // Load the online stream
  bassChannel := BASS_StreamCreateURL(PChar(song.FileName), 0, BASS_STREAM_BLOCK or BASS_STREAM_AUTOFREE, nil, nil);
  try
    if (bassChannel = 0) then
       begin
         song._status := ssError;
         song._errno := BASS_ErrorGetCode;
       end
    else if (song.Status = ssPlaying) then
       begin
         song.bassChannel := bassChannel;
         BASS_ChannelPlay(song.bassChannel, BOOL(0));
         song.int_SetVolume(song._vol);
       end
    else
       BASS_StreamFree(bassChannel); // It is possible, that the song is already stopped...
  except
    // It is possible, that the song is already done for...
    if (bassChannel <> 0) then
       BASS_StreamFree(bassChannel);
  end;

  // Terminate this thread snippet
  with TThread.CurrentThread do
       begin
         FreeOnTerminate := True;
         Terminate;
       end;
end;

function TPlayableAudioTrack.int_GetStatus: TSongStatus;
begin
  if (_status = ssError) then
     exit(ssError);
  if _isonline then
     begin
       if not _onlinestopped then
          Result := ssPlaying
       else
          Result := ssStopped;
     end
  else
     begin
       case BASS_ChannelIsActive(bassChannel) of
            BASS_ACTIVE_STOPPED: Result := ssStopped;
            BASS_ACTIVE_PLAYING, BASS_ACTIVE_STALLED: Result := ssPlaying;
            BASS_ACTIVE_PAUSED: Result := ssPaused;
            else Result := ssStopped;
       end;
     end;
end;

procedure TPlayableAudioTrack.int_SetStatus(st: TSongStatus);

          procedure InternalPlayTrack;
          begin
            if _isonline then
               begin
                 bassChannel := 0;
                 _onlinestopped := false;
                 TThread.ExecuteInThread(@InitOnlineStream, Pointer(Self), nil);
               end
            else
               begin
                 bassChannel := BASS_SampleGetChannel(bassSample, BOOL(0));
                 if (bassChannel = 0) then
                    begin
                      _status := ssError;
                      _errno := BASS_ErrorGetCode;
                    end
                 else
                    BASS_ChannelPlay(bassChannel, BOOL(1));
               end;
            int_SetVolume(_vol);
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
                 _onlinestopped := true;
                 if (bassChannel <> 0) then
                    BASS_StreamFree(bassChannel);
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
                 _onlinestopped := true;
                 if (bassChannel <> 0) then
                    BASS_StreamFree(bassChannel);
               end
            else
               BASS_ChannelStop(bassChannel);
          end;
     end;
end;

procedure TPlayableAudioTrack.int_SetVolume(vol: double);
begin
  if (vol > 1.0) then
     vol := 1.0
  else if (vol < 0.0) then
     vol := 0.0;
  _vol := vol;
  if not (int_GetStatus in [ssNone, ssError, ssStopped]) then
     begin
       if _isonline and (bassChannel = 0) then
          exit;
       BASS_ChannelSetAttribute(bassChannel, BASS_ATTRIB_VOL, _vol);
     end;
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
var
  _dummystream: TMemoryStream;
begin
  inherited Create;
  _status := ssNone;
  _errno := 0;
  _vol := 1.0;
  _filename := fn;
  if IsNetFile(_filename) then
     begin
       _isonline := true;
       _onlinestopped := false;
       bassChannel := 0;
     end
  else
     begin
       _isonline := false;
       bassSample := BASS_SampleLoad(BOOL(0), PChar(_filename), 0, 0, 1, 0);
       if (bassSample = 0) then
          begin
            // Files with invalid names often cannot be loaded directly. We try to use the Memory-based approach.
            _dummystream := TMemoryStream.Create;
            try
              try
                _dummystream.LoadFromFile(_filename);
                bassSample := BASS_SampleLoad(BOOL(1), _dummystream.Memory, 0, _dummystream.Size, 1, 0);
              except
                bassSample := 0;
              end;
            finally
              _dummystream.Free;
            end;
            if (bassSample = 0) then
               begin
                 _status := ssError;
                 _errno := BASS_ErrorGetCode;
               end;
          end
       else
          _status := ssStopped;
     end;
end;

destructor TPlayableAudioTrack.Destroy;
begin
  int_SetStatus(ssStopped);
  if _isonline then
     begin
       if (bassChannel <> 0) then
          BASS_StreamFree(bassChannel);
     end
  else if (_status <> ssError) then
     BASS_SampleFree(bassSample);
  inherited;
end;

function TPlayableAudioTrack.GetErrorInfo: string;
begin
  case _errno of
       0: Result := ''; // BASS_OK: we return empty string here, to signal, that there's no error
       1: Result := 'BASS_ERROR_MEM';
       2: Result := 'BASS_ERROR_FILEOPEN';
       3: Result := 'BASS_ERROR_DRIVER';
       4: Result := 'BASS_ERROR_BUFLOST';
       5: Result := 'BASS_ERROR_HANDLE';
       6: Result := 'BASS_ERROR_FORMAT';
       7: Result := 'BASS_ERROR_POSITION';
       8: Result := 'BASS_ERROR_INIT';
       9: Result := 'BASS_ERROR_START';
       10: Result := 'BASS_ERROR_SSL';
       11: Result := 'BASS_ERROR_REINIT';
       14: Result := 'BASS_ERROR_ALREADY';
       17: Result := 'BASS_ERROR_NOTAUDIO';
       18: Result := 'BASS_ERROR_NOCHAN';
       19: Result := 'BASS_ERROR_ILLTYPE';
       20: Result := 'BASS_ERROR_ILLPARAM';
       21: Result := 'BASS_ERROR_NO3D';
       22: Result := 'BASS_ERROR_NOEAX';
       23: Result := 'BASS_ERROR_DEVICE';
       24: Result := 'BASS_ERROR_NOPLAY';
       25: Result := 'BASS_ERROR_FREQ';
       27: Result := 'BASS_ERROR_NOTFILE';
       29: Result := 'BASS_ERROR_NOHW';
       31: Result := 'BASS_ERROR_EMPTY';
       32: Result := 'BASS_ERROR_NONET';
       33: Result := 'BASS_ERROR_CREATE';
       34: Result := 'BASS_ERROR_NOFX';
       37: Result := 'BASS_ERROR_NOTAVAIL';
       38: Result := 'BASS_ERROR_DECODE';
       39: Result := 'BASS_ERROR_DX';
       40: Result := 'BASS_ERROR_TIMEOUT';
       41: Result := 'BASS_ERROR_FILEFORM';
       42: Result := 'BASS_ERROR_SPEAKER';
       43: Result := 'BASS_ERROR_VERSION';
       44: Result := 'BASS_ERROR_CODEC';
       45: Result := 'BASS_ERROR_ENDED';
       46: Result := 'BASS_ERROR_BUSY';
       47: Result := 'BASS_ERROR_UNSTREAMABLE';
       48: Result := 'BASS_ERROR_PROTOCOL';
       49: Result := 'BASS_ERROR_DENIED';
       else Result := 'BASS_ERROR_UNKNOWN';
  end;
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


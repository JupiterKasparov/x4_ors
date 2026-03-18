unit u_song;

{$mode objfpc}
{$H+}

interface

uses
  Classes, SysUtils, BASS, u_utils, fgl, u_logger;

type
  TSongStatus = (ssNone, ssStopped, ssPaused, ssPlaying, ssError);

  TPlayableAudioTrack = class
  private
    bassStreamHandle: HSTREAM;
    onlineSyncHandle: HSYNC;
    _isonline, _onlinestopped: boolean;
    _status: TSongStatus;
    _vol: double;
    _filename: string;
    _errno: integer;
    _dummystream: TMemoryStream;
    function int_GetStatus: TSongStatus;
    procedure int_SetStatus(st: TSongStatus);
    procedure int_SetVolume(vol: double);
    function int_GetLengthMs: integer;
    function int_GetPositionMs: integer;
    procedure int_SetPositionMs(pos: integer);
  public
    constructor Create(fn: string);
    destructor Destroy; override;
    procedure ResetOnlineStatus;
    function GetErrorInfo: string;
    property Status: TSongStatus read int_GetStatus write int_SetStatus;
    property Volume: double read _vol write int_SetVolume;
    property LengthMs: integer read int_GetLengthMs;
    property PositionMs: integer read int_GetPositionMs write int_SetPositionMs;
    property IsOnlineStream: boolean read _isonline;
    property FileName: string read _filename;
  end;

  TPlayableAudioTrackList = specialize TFPGList<TPlayableAudioTrack>;

  TNoiseChannel = class
  private
    bassStreamHandle: HSTREAM;
    _isstopped: boolean;
    _vol: double;
    function int_GetStatus: TSongStatus;
    procedure int_SetStatus(st: TSongStatus);
    procedure int_SetVolume(vol: double);
  public
    constructor Create;
    destructor Destroy; override;
    property Status: TSongStatus read int_GetStatus write int_SetStatus;
    property Volume: double read _vol write int_SetVolume;
  end;

implementation

{$IFDEF MSWINDOWS}
uses
  Windows;
{$ENDIF}

{ TPlayableAudioTrack }

procedure OnlineStreamEndProc(handle: HSYNC; channel, data: DWORD; obj: Pointer); {$IFDEF MSWINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  try
    if not TPlayableAudioTrack(obj)._onlinestopped then
       begin
         TPlayableAudioTrack(obj)._status := ssError;
         TPlayableAudioTrack(obj)._errno := BASS_ERROR_BUFLOST;
         TPlayableAudioTrack(obj).bassStreamHandle := 0;
       end;
    TPlayableAudioTrack(obj).onlineSyncHandle := 0;
  except
    ; // Not an error! Can happen even in normal operation!
  end;
end;

var
  OnlineLoadingList: TThreadList;

procedure InitOnlineStream(obj: Pointer);
var
  bassStreamHandle: HCHANNEL;
  lst: TList;
begin
  // Connect to stream
  bassStreamHandle := BASS_StreamCreateURL(PChar(TPlayableAudioTrack(obj)._filename), 0, BASS_STREAM_BLOCK or BASS_STREAM_AUTOFREE, nil, nil);
  try
    lst := OnlineLoadingList.LockList;
    try
      // Track is valid
      if (lst.IndexOf(obj) >= 0) then
         begin
           lst.Extract(obj);

           // Error
           if (bassStreamHandle = 0) then
              begin
                // Set error flag
                TPlayableAudioTrack(obj)._status := ssError;
                TPlayableAudioTrack(obj)._errno := BASS_ErrorGetCode;

                // Log error
                LogError(Format('Failed to connect to online stream ''%s''! Error: %s', [TPlayableAudioTrack(obj)._filename, TPlayableAudioTrack(obj).GetErrorInfo]));
              end

           // Success
           else if (TPlayableAudioTrack(obj).Status = ssPlaying) then
              begin
                TPlayableAudioTrack(obj).bassStreamHandle := bassStreamHandle;
                BASS_ChannelPlay(TPlayableAudioTrack(obj).bassStreamHandle, BOOL(0));
                TPlayableAudioTrack(obj).int_SetVolume(TPlayableAudioTrack(obj)._vol);
                TPlayableAudioTrack(obj).onlineSyncHandle := BASS_ChannelSetSync(TPlayableAudioTrack(obj).bassStreamHandle, BASS_SYNC_FREE, 0, @OnlineStreamEndProc, obj);
              end

           // Already stopped
           else
              begin
                BASS_StreamFree(bassStreamHandle);
                bassStreamHandle := 0;
              end;
         end

      // Track has already gone
      else if (bassStreamHandle <> 0) then
         begin
           BASS_StreamFree(bassStreamHandle);
           bassStreamHandle := 0;
         end;
    finally
      OnlineLoadingList.UnlockList;
    end;
  except
    // Unhandled exception occurred
    LogError(ExceptObject, ExceptAddr);
    if (bassStreamHandle <> 0) then
       BASS_StreamFree(bassStreamHandle);
  end;

  // Terminate thread
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
       case BASS_ChannelIsActive(bassStreamHandle) of
            BASS_ACTIVE_STOPPED: Result := ssStopped;
            BASS_ACTIVE_PLAYING, BASS_ACTIVE_STALLED: Result := ssPlaying;
            BASS_ACTIVE_PAUSED, BASS_ACTIVE_PAUSED_DEVICE: Result := ssPaused;
            else Result := ssStopped;
       end;
     end;
end;

procedure TPlayableAudioTrack.int_SetStatus(st: TSongStatus);
var
  currStatus: TSongStatus;
  lst: TList;
begin
  // Current status
  currStatus := int_GetStatus;
  if (currStatus in [ssNone, ssError]) then
     exit;
  if (st = ssError) or (st = ssNone) then
     st := ssStopped;

  // Modify status
  if (st = ssPaused) then
     begin
       if _isonline then
          begin
            if (not _onlinestopped) then
               begin
                 _onlinestopped := true;
                 BASS_StreamFree(bassStreamHandle);
                 bassStreamHandle := 0;
               end;
          end
       else if (currStatus = ssPlaying) then
          BASS_ChannelPause(bassStreamHandle);
     end
  else if (st = ssPlaying) then
     begin
       if _isonline then
          begin
            if _onlinestopped then
               begin
                 _onlinestopped := false;
                 lst := OnlineLoadingList.LockList;
                 try
                   if (lst.IndexOf(Pointer(Self)) < 0) then
                      begin
                        lst.Add(Pointer(Self));
                        TThread.ExecuteInThread(@InitOnlineStream, Pointer(Self), nil);
                      end;
                 finally
                   OnlineLoadingList.UnlockList;
                 end;
               end;
          end
       else if (currStatus = ssPaused) then
          begin
            BASS_ChannelPlay(bassStreamHandle, BOOL(0));
            int_SetVolume(_vol);
          end
       else if (currStatus <> ssPlaying) then
          begin
            BASS_ChannelPlay(bassStreamHandle, BOOL(1));
            int_SetVolume(_vol);
          end;
     end
  else
     begin
       if _isonline then
          begin
            if (not _onlinestopped) then
               begin
                 _onlinestopped := true;
                 BASS_StreamFree(bassStreamHandle);
                 bassStreamHandle := 0;
               end;
          end
       else if (currStatus in [ssPlaying, ssPaused]) then
          BASS_ChannelStop(bassStreamHandle);
     end;
end;

procedure TPlayableAudioTrack.int_SetVolume(vol: double);
begin
  _vol := Clamp(vol, 0.0, 1.0);
  if (int_GetStatus in [ssPlaying, ssPaused]) then
     BASS_ChannelSetAttribute(bassStreamHandle, BASS_ATTRIB_VOL, _vol);
end;

function TPlayableAudioTrack.int_GetLengthMs: integer;
begin
  if _isonline then
     exit(-1);
  if (int_GetStatus in [ssNone, ssError]) then
     exit(0);
  Result := round(BASS_ChannelBytes2Seconds(bassStreamHandle, BASS_ChannelGetLength(bassStreamHandle, BASS_POS_BYTE)) * 1000);
end;

function TPlayableAudioTrack.int_GetPositionMs: integer;
begin
  if _isonline then
     exit(-1);
  if (int_GetStatus in [ssNone, ssError, ssStopped]) then
     exit(0);
  Result := round(BASS_ChannelBytes2Seconds(bassStreamHandle, BASS_ChannelGetPosition(bassStreamHandle, BASS_POS_BYTE)) * 1000);
end;

procedure TPlayableAudioTrack.int_SetPositionMs(pos: integer);
begin
  if _isonline then
     exit;
  if (pos > int_GetLengthMs) then
     exit;
  if (int_GetStatus in [ssPlaying, ssPaused]) then
     BASS_ChannelSetPosition(bassStreamHandle, BASS_ChannelSeconds2Bytes(bassStreamHandle, pos / 1000), BASS_POS_BYTE);
end;

constructor TPlayableAudioTrack.Create(fn: string);
begin
  inherited Create;
  _status := ssNone;
  _errno := 0;
  _vol := 1.0;
  _filename := fn;
  _dummystream := nil;
  if IsNetFile(_filename) then
     begin
       _isonline := true;
       _onlinestopped := true;
       bassStreamHandle := 0;
       onlineSyncHandle := 0;
     end
  else
     begin
       _isonline := false;
       bassStreamHandle := BASS_StreamCreateFile(BOOL(0), PChar(_filename), 0, 0, BASS_STREAM_PRESCAN);
       if (bassStreamHandle = 0) then
          begin
            // Files with invalid names often cannot be loaded directly. We try to use the Memory-based approach.
            _dummystream := TMemoryStream.Create;
            try
              if FileExists(_filename) then
                 begin
                   _dummystream.LoadFromFile(_filename); // This can result in a non-continuable exception, if the file doesn't exist!
                   bassStreamHandle := BASS_StreamCreateFile(BOOL(1), _dummystream.Memory, 0, _dummystream.Size, BASS_STREAM_PRESCAN);
                 end;
            except
              bassStreamHandle := 0;
            end;
            if (bassStreamHandle = 0) then
               begin
                 FreeAndNil(_dummystream); // It's unnecessary to keep the invalid stream then...
                 _status := ssError;
                 _errno := BASS_ErrorGetCode;
                 LogError(Format('Failed to load ''%s''! Error: %s', [_filename, GetErrorInfo]));
               end;
          end
       else
          _status := ssStopped;
     end;
end;

destructor TPlayableAudioTrack.Destroy;
var
  lst: TList;
begin
  int_SetStatus(ssStopped);
  if _isonline then
     begin
       lst := OnlineLoadingList.LockList;
       try
         if (lst.IndexOf(Pointer(Self)) >= 0) then
            lst.Extract(Pointer(Self));
       finally
         OnlineLoadingList.UnlockList;
       end;
       if (onlineSyncHandle <> 0) and (bassStreamHandle <> 0) then
          BASS_ChannelRemoveSync(bassStreamHandle, onlineSyncHandle);
       onlineSyncHandle := 0;
     end;
  if (bassStreamHandle <> 0) then
     BASS_StreamFree(bassStreamHandle);
  if Assigned(_dummystream) then
     FreeAndNil(_dummystream);
  inherited;
end;

procedure TPlayableAudioTrack.ResetOnlineStatus;
begin
  if _isonline and (int_GetStatus = ssError) then
     begin
       _onlinestopped := true;
       _status := ssStopped;
       _errno := 0;
       bassStreamHandle := 0;
     end;
end;

function TPlayableAudioTrack.GetErrorInfo: string;
begin
  if (_errno = 0) then
     exit('')
  else
     exit(Format('BASS Error %d', [_errno]));
end;

{ TNoiseChannel }

{$IFDEF MSWINDOWS}
  {$IF not defined(BCryptGenRandom)}
  function BCryptGenRandom(hAlgorithm: Pointer; pbBuffer: Pointer; cbBuffer: ULONG; dwFlags: ULONG): LongInt; stdcall; external 'bcrypt.dll';
  {$ENDIF}
{$ELSE}
var
  uRandomHandle: THandle;
{$ENDIF}

function NoiseChannelProc(handle: HSTREAM; buffer: Pointer; length: DWORD; user: Pointer): DWORD; {$IFDEF MSWINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  {$IFDEF MSWINDOWS}
  if (BCryptGenRandom(nil, buffer, length, 2) = 0) then
    Result := length
  else
    Result := 0;
  {$ELSE}
  if (uRandomHandle <> feInvalidHandle) then
    Result := FileRead(uRandomHandle, buffer^, length)
  else
    Result := 0;
  {$ENDIF}
end;

function TNoiseChannel.int_GetStatus:TSongStatus;
begin
  if _isstopped then
     Result := ssStopped
  else
     Result := ssPlaying;
end;

procedure TNoiseChannel.int_SetStatus(st: TSongStatus);
var
  currStatus: TSongStatus;
begin
  // Current status
  currStatus := int_GetStatus;
  if (st <> ssPlaying) then
     st := ssStopped;

  // Modify status
  if (st = ssPlaying) then
     begin
       if _isstopped then
          begin
            bassStreamHandle := BASS_StreamCreate(44100, 1, BASS_SAMPLE_8BITS, @NoiseChannelProc, Pointer(Self));
            if (bassStreamHandle <> 0) then
               begin
                 _isstopped := false;
                 BASS_ChannelPlay(bassStreamHandle, BOOL(0));
                 int_SetVolume(_vol);
               end;
          end;
     end
  else if (currStatus = ssPlaying) then
     begin
       _isstopped := true;
       BASS_StreamFree(bassStreamHandle);
       bassStreamHandle := 0;
     end;
end;

procedure TNoiseChannel.int_SetVolume(vol: double);
begin
  _vol := Clamp(vol, 0.0, 1.0);
  if (int_GetStatus = ssPlaying) then
     BASS_ChannelSetAttribute(bassStreamHandle, BASS_ATTRIB_VOL, _vol);
end;

constructor TNoiseChannel.Create;
begin
  inherited;
  bassStreamHandle := 0;
  _isstopped := true;
  _vol := 0.0;
end;

destructor TNoiseChannel.Destroy;
begin
  int_SetStatus(ssStopped);
  if (bassStreamHandle <> 0) then
     BASS_StreamFree(bassStreamHandle);
  inherited;
end;


initialization
  OnlineLoadingList := TThreadList.Create;
  BASS_Init(-1, 44100, BASS_DEVICE_NOSPEAKER, {$IFDEF MSWINDOWS}0{$ELSE}nil{$ENDIF}, nil);
  BASS_SetConfig(BASS_CONFIG_NET_PLAYLIST, 1);
  BASS_SetConfig(BASS_CONFIG_NET_PREBUF_WAIT, 0);
  BASS_SetConfig(71{BASS_CONFIG_NET_META}, 0);
  BASS_SetConfigPtr(BASS_CONFIG_NET_PROXY, nil);
  BASS_SetConfig(BASS_CONFIG_NET_READTIMEOUT, 5000);
  BASS_SetConfigPtr(BASS_CONFIG_NET_AGENT, PChar('X4 ORS Playback Controller Application'));
  {$IFDEF LINUX}
  uRandomHandle := FileOpen('/dev/urandom', fmOpenRead);
  {$ENDIF}

finalization
  BASS_Stop;
  BASS_Free;
  FreeAndNil(OnlineLoadingList);
  {$IFDEF LINUX}
  if (uRandomHandle <> feInvalidHandle) then
     FileClose(uRandomHandle);
  {$ENDIF}

end.


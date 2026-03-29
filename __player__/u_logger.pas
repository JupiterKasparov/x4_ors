unit u_logger;

{$mode objfpc}
{$H+}

interface

uses
  Classes, SysUtils, syncobjs, u_utils;

procedure SetAppLogFile(fn: string);
procedure Log(category, msg: string);
procedure LogError(msg: string);
procedure LogError(xcpt: TObject; addr: Pointer);
procedure LogLastError;

implementation

const
  logname: string = '';

var
  logActive: boolean;
  logCriticalSection: TCriticalSection;

procedure SetAppLogFile(fn: string);
begin
  logname := fn;
end;

procedure Log(category, msg: string);
var
  time: TDateTime;
  log: System.Text;
begin
  if (logname <> '') and Assigned(logCriticalSection) then
     begin
       logCriticalSection.Acquire;
       try
         time := Now;
         System.Assign(log, logname);
         {$I-}
         if (not logActive) or (not FileExists(logname)) then
            begin
              logActive := true;
              Rewrite(log);
            end
         else
            Append(log);
         writeln(log, Format('[%s]: %s - %s', [category, DateTimeToStr(time, X4OrsFormatSettings, true), msg]));
         System.Close(log);
         {$I+}
       finally
         logCriticalSection.Release;
       end;
     end;
end;

procedure LogError(msg: string);
begin
  Log('ERROR', msg);
end;

procedure LogError(xcpt: TObject; addr: Pointer);
begin
  if (xcpt = nil) then
     LogError(Format('Exception <null> at address 0x%p', [addr]))
  else if (xcpt is Exception) then
     LogError(Format('Exception %s at address 0x%p - %s', [xcpt.ClassName, addr, Exception(xcpt).Message]))
  else
     LogError(Format('Exception %s at address 0x%p', [xcpt.ClassName, addr]));
end;

procedure LogLastError;
begin
  LogError(SysErrorMessage(GetLastOSError));
end;

initialization
  logActive := false;
  logCriticalSection := TCriticalSection.Create;

finalization
  FreeAndNil(logCriticalSection);

end.


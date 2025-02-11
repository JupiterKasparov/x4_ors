unit u_logger;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, u_utils;

var
  NoLog: boolean = false;

procedure Log(category, msg: string);
procedure LogError(msg: string);
procedure LogError(xcpt: TObject; addr: Pointer);

implementation

const
  logname: string = 'x4_ors.log';

var
  logActive: boolean;
  logCriticalSection: TCriticalSection;

procedure Log(category, msg: string);
var
  time: TDateTime;
  log: System.Text;
begin
  if (not NoLog) and Assigned(logCriticalSection) then
     begin
       logCriticalSection.Acquire;
       try
         time := Now;
         System.Assign(log, logname);
         {$I-}
         if (not logActive) then
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

initialization
  logActive := false;
  logCriticalSection := TCriticalSection.Create;

finalization
  FreeAndNil(logCriticalSection);

end.


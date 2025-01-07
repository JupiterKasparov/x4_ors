unit u_logger;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows;

var
  NoLog: boolean = false;

procedure Log(category, msg: string);
procedure LogError(msg: string);
procedure LogError(xcpt: TObject; addr: Pointer);

implementation

const
  logname: string = 'x4_ors.log';

var
  bLogActive: boolean = false;

procedure Log(category, msg: string);
var
  time: SYSTEMTIME;
  f: System.Text;
begin
  if not NoLog then
     begin
       GetLocalTime(time);
       System.Assign(f, logname);
       // In case of IO error, no log is done!
       {$I-}
       if bLogActive then
          Append(f)
       else
          begin
            bLogActive := true;
            Rewrite(f);
          end;
       writeln(f, Format('[%s]: %.2d/%.2d/%.4d %.2d:%.2d:%.2d.%.3d - %s', [category, time.wDay, time.wMonth, time.wYear, time.wHour, time.wMinute, time.wSecond, time.wMilliseconds, msg]));
       System.Close(f);
       {$I+}
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

end.


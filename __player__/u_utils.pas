unit u_utils;

{$mode objfpc}{$H+}

interface

uses
  strutils;

var
  bLinearizeVolume: boolean = false;

function IsNetFile(fn: string): boolean;

implementation

function IsNetFile(fn: string): boolean;
begin
  Result := AnsiStartsText('http://', fn) or
            AnsiStartsText('https://', fn) or
            AnsiStartsText('ftp://', fn);
end;

end.


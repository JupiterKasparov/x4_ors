unit u_utils;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, strutils;

var
  bLinearizeVolume: boolean = false;
  x4_ors_temp_dir: string;

function IsNetFile(fn: string): boolean;

implementation

function IsNetFile(fn: string): boolean;
begin
  Result := AnsiStartsText('http://', fn) or
            AnsiStartsText('https://', fn) or
            AnsiStartsText('ftp://', fn);
end;

initialization
  x4_ors_temp_dir := Format('%s\x4_ors_temp_dir', [GetTempDir]);

end.


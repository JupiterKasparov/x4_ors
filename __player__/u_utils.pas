unit u_utils;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, strutils;

function IsNetFile(fn: string): boolean;
function ReadStringSetting(ini: TIniFile; name, def: string): string;
function ReadIntSetting(ini: TIniFile; name: string; def: integer): integer;
function ReadFloatSetting(ini: TIniFile; name: string; def: double): double;
procedure WriteStringSetting(ini: TIniFile; name, value: string);
procedure WriteIntSetting(ini: TIniFile; name: string; value: integer);
procedure WriteFloatSetting(ini: TIniFile; name: string; value: double);
procedure ShuffleList(lst: TStrings);

var
  X4OrsFormatSettings: TFormatSettings;

implementation

function IsNetFile(fn: string): boolean;
begin
  fn := Trim(fn);
  if AnsiStartsStr('\\', fn) then
     exit(true) // UNC path
  else if (Pos('://', fn) > 0) then
     exit(true); // Internet path
  exit(false); // Local path
end;

function ReadStringSetting(ini: TIniFile; name, def: string): string;
var
  tok: integer;
  value: string;
begin
  tok := Pos('.', name);
  if (tok <= 0) then
     value := def;
  value := RightStr(name, Length(name) - tok);
  name := LeftStr(name, tok - 1);
  Result := ini.ReadString(name, value, def);
end;

function ReadIntSetting(ini: TIniFile; name: string; def: integer): integer;
var
  i: integer;
  s: string;
begin
  s := ReadStringSetting(ini, name, '??');
  if TryStrToInt(s, i) then
     Result := i
  else
     Result := def;
end;

function ReadFloatSetting(ini: TIniFile; name: string; def: double): double;
var
  f: double;
  s: string;
begin
  s := ReadStringSetting(ini, name, '??');
  if TryStrToFloat(s, f, X4OrsFormatSettings) then
     Result := f
  else
     Result := def;
end;

procedure WriteStringSetting(ini: TIniFile; name, value: string);
var
  tok: integer;
  section, identifier: string;
begin
  tok := Pos('.', name);
  if (tok <= 0) then
     begin
      section := '';
      identifier := name;
     end
  else
     begin
       section := LeftStr(name, tok - 1);
       identifier := RightStr(name, Length(name) - tok);
     end;
  ini.WriteString(section, identifier, value);
end;

procedure WriteIntSetting(ini: TIniFile; name: string; value: integer);
begin
  WriteStringSetting(ini, name, IntToStr(value));
end;

procedure WriteFloatSetting(ini: TIniFile; name: string; value: double);
begin
  WriteStringSetting(ini, name, FloatToStr(value, X4OrsFormatSettings));
end;

procedure ShuffleList(lst: TStrings);
var
  i, r: integer;
  temp: string;
begin
  if (lst.Count > 1) then
     for i := 0 to lst.Count - 1 do
         begin
           r := random(lst.Count);
           if (r <> i) then
              begin
                temp := lst[i];
                lst[i] := lst[r];
                lst[r] := temp;
              end;
         end;
end;

initialization
  X4OrsFormatSettings := DefaultFormatSettings;
  X4OrsFormatSettings.DecimalSeparator := '.';

end.


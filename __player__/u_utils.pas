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
function Clamp(flt, minvalue, maxvalue: double): double;
function Clamp(ivalue, minvalue, maxvalue: integer): integer;
function ParseList(lst: string): TStringArray;
procedure OrderListByList(lst, orderBy: TStrings);

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
begin
  if (lst.Count > 1) then
     for i := lst.Count - 1 downto 0 do
         begin
           r := random(i + 1);
           if (r <> i) then
              lst.Exchange(i, r);
         end;
end;

function Clamp(flt, minvalue, maxvalue: double): double;
begin
  if (maxvalue < minvalue) then
     maxvalue := minvalue;
  if (flt < minvalue) then
     Result := minvalue
  else if (flt > maxvalue) then
     Result := maxvalue
  else
     Result := flt;
end;

function Clamp(ivalue, minvalue, maxvalue: integer): integer;
begin
  if (maxvalue < minvalue) then
     maxvalue := minvalue;
  if (ivalue < minvalue) then
     Result := minvalue
  else if (ivalue > maxvalue) then
     Result := maxvalue
  else
     Result := ivalue;
end;

function ParseList(lst: string): TStringArray;
var
  tok: integer;
  str: string;
begin
  SetLength(Result, 0);
  repeat
    tok := Pos(',', lst);
    if (tok <= 0) then
       str := Trim(lst)
    else
       begin
         str := Trim(LeftStr(lst, tok - 1));
         lst := Trim(RightStr(lst, Length(lst) - tok));
       end;
    if (str <> '') then
       begin
         SetLength(Result, Length(Result) + 1);
         Result[High(Result)] := str;
       end;
  until (tok <= 0);
end;

procedure OrderListByList(lst, orderBy: TStrings);
var
  orderByName, orderedName: string;
  copyList: TStrings;
  i, j: integer;
begin
  if (lst.Count > 0) and (orderBy.Count > 0) then
     begin
       copyList := TStringList.Create;
       try
         copyList.AddStrings(lst);
         lst.Clear;
         for i := 0 to orderBy.Count - 1 do
             begin
               orderByName := ExtractFileName(Trim(orderBy[i]));
               for j := 0 to copyList.Count - 1 do
                   begin
                     orderedName := ExtractFileName(Trim(copyList[j]));
                     if (CompareText(orderByName, orderedName) = 0) then
                        begin
                          lst.Add(copyList[j]);
                          break;
                        end;
                   end;
             end;
         for i := 0 to copyList.Count - 1 do
             begin
               orderedName := copyList[i];
               if (lst.IndexOf(orderedName) < 0) then
                  lst.Add(orderedName);
             end;
       finally
         copyList.Clear;
         copyList.Free;
       end;
     end;
end;

initialization
  X4OrsFormatSettings := DefaultFormatSettings;
  X4OrsFormatSettings.DecimalSeparator := '.';
  X4OrsFormatSettings.ShortDateFormat := 'dd/mm/yyy';
  X4OrsFormatSettings.ShortTimeFormat := 'hh:nn:ss.zzz';
  X4OrsFormatSettings.LongDateFormat := 'dd/mm/yyy';
  X4OrsFormatSettings.LongTimeFormat := 'hh:nn:ss.zzz';
  X4OrsFormatSettings.DateSeparator := '/';
  X4OrsFormatSettings.TimeSeparator := ':';

end.


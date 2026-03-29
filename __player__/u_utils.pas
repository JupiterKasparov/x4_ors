unit u_utils;

{$mode objfpc}
{$H+}

interface

uses
  Classes, SysUtils, strutils, {$IFDEF MSWINDOWS}Windows{$ELSE}BaseUnix{$ENDIF};

function GetParentFolder(folder: string; level: integer = 1): string;
function FindFileAt(fileName: string; folders: TStringArray): string;
function GetExeFolder: string;
function IsNetFile(fn: string): boolean;
procedure GetFileList(dir: string; var lst: TStrings);
procedure ShuffleList(var lst: TStrings);
function Clamp(flt, minvalue, maxvalue: double): double;
function Clamp(ivalue, minvalue, maxvalue: integer): integer;
function ParseList(lst: string): TStringArray;
procedure OrderListByList(var lst: TStrings; orderBy: TStrings);

var
  X4OrsFormatSettings: TFormatSettings;

implementation

function GetParentFolder(folder: string; level: integer = 1): string;
var
  i: integer;
begin
  if not DirectoryExists(folder) then
     folder := ExtractFilePath(folder);
  Result := folder;
  if (level > 0) then
     for i := 1 to level do
         Result := ExtractFilePath(ExcludeTrailingPathDelimiter(Result));
  Result := IncludeTrailingPathDelimiter(Result);
end;

function FindFileAt(fileName: string; folders: TStringArray): string;
var
  i: integer;
  fn: string;
begin
  Result := '';
  for i := 0 to High(folders) do
      begin
        fn := IncludeTrailingPathDelimiter(folders[i]) + fileName;
        if FileExists(fn) then
           exit(fn);
      end;
end;

function GetExeFolder: string;
{$IFDEF MSWINDOWS}
var
  exeFilePath: array [0..32767] of char;
begin
  FillChar(exeFilePath, SizeOf(exeFilePath), 0);
  GetModuleFileName(GetModuleHandle(nil), @exeFilePath, 32767);
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(StrPas(exeFilePath)));
end;
{$ELSE}
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(fpReadLink('/proc/self/exe')));
end;
{$ENDIF}

function IsNetFile(fn: string): boolean;
begin
  // Only check whether the path requires network functions to access
  fn := Trim(fn);
  if (Pos('://', fn) > 0) then
     exit(true);
  exit(false);
end;

procedure GetFileList(dir: string; var lst: TStrings);
var
  rec: TSearchRec;
  fn: string;
begin
  lst.Clear;
  DoDirSeparators(dir);
  dir := IncludeTrailingPathDelimiter(dir);
  if (SysUtils.FindFirst(dir + '*', faAnyFile, rec) = 0) then
     begin
       repeat
          if ((rec.Attr and faDirectory) <> 0) or (rec.Name = '.') or (rec.Name = '..') then
             continue; // Do not load directories!
          fn := dir + rec.Name;
          DoDirSeparators(fn);
          if (lst.IndexOf(fn) < 0) then
             lst.Add(fn);
       until (SysUtils.FindNext(rec) <> 0);
       SysUtils.FindClose(rec);
     end;
end;

procedure ShuffleList(var lst: TStrings);
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

procedure OrderListByList(var lst: TStrings; orderBy: TStrings);
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
  // UTF8 handling setup
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);

  // Custom format settings setup
  X4OrsFormatSettings := DefaultFormatSettings;
  X4OrsFormatSettings.DecimalSeparator := '.';
  X4OrsFormatSettings.ShortDateFormat := 'dd/mm/yyy';
  X4OrsFormatSettings.ShortTimeFormat := 'hh:nn:ss.zzz';
  X4OrsFormatSettings.LongDateFormat := 'dd/mm/yyy';
  X4OrsFormatSettings.LongTimeFormat := 'hh:nn:ss.zzz';
  X4OrsFormatSettings.DateSeparator := '/';
  X4OrsFormatSettings.TimeSeparator := ':';
end.

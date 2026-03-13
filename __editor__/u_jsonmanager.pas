unit u_jsonmanager;

{$mode ObjFPC}
{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser;

function LoadSettings(fileName: string): TJSONData;
function GetStringSetting(base: TJSONData; path: string; defaultValue: string = ''): string;
function GetIntegerSetting(base: TJSONData; path: string; defaultValue: integer = 0): integer;
function GetFloatSetting(base: TJSONData; path: string; defaultValue: TJSONFloat = 0.0): TJSONFloat;
function GetBooleanSetting(base: TJSONData; path: string; defaultValue: boolean = false): boolean;
function GetListSetting(base: TJSONData; path: string): TJSONArray;
function GetObjectSetting(base: TJSONData; path: string): TJSONObject;
function SaveSettings(base: TJSONData; fileName: string): boolean;
procedure SetStringSetting(base: TJSONData; path: string; value: string = '');
procedure SetIntegerSetting(base: TJSONData; path: string; value: integer = 0);
procedure SetFloatSetting(base: TJSONData; path: string; value: TJSONFloat = 0.0);
procedure SetBooleanSetting(base: TJSONData; path: string; value: boolean = false);
function SetListSetting(base: TJSONData; path: string; minCount: integer = 0): TJSONArray;
function SetObjectSetting(base: TJSONData; path: string): TJSONObject;

implementation

function GetData(base: TJSONData; path: string = ''): TJSONData;
begin
  if (base = nil) then
    exit(nil);
  if (path = '') then
    exit(base);
  Result := base.FindPath(path);
end;

function GetOrInsertParent(base: TJSONData; path: string = ''): TJSONObject;
var
  current, obj: TJSONData;
  p: integer;
  partName: string;
begin
  if (base = nil) or (base.JSONType <> jtObject) then
    exit(nil);
  current := base;
  repeat
    p := Pos('.', path);
    if (p <= 0) then
      exit(TJSONObject(current));
    partName := Trim(LeftStr(path, p - 1));
    path := Trim(RightStr(path, Length(path) - p));
    obj := TJSONObject(current).Find(partName);
    if (obj = nil) or (obj.JSONType <> jtObject) then
      begin
        obj := TJSONObject.Create;
        TJSONObject(current).Objects[partName] := TJSONObject(obj);
      end;
    current := obj;
  until false;
end;

function GetLocalAttributeName(path: string = ''): string;
var
  p: integer;
begin
  repeat
    p := Pos('.', path);
    if (p <= 0) then
      exit(Trim(path));
    path := Trim(RightStr(path, Length(path) - p));
  until false;
end;

function LoadSettings(fileName: string): TJSONData;
var
  fs: TFileStream;
begin
  if not FileExists(fileName) then
    exit(nil);
  Result := nil;
  fs := nil;
  try
    try
      fs := TFileStream.Create(fileName, fmOpenRead);
      fs.Seek(0, soFromBeginning);
      Result := GetJSON(fs);
    except
      if (Result <> nil) then
        Result.Free;
      exit(nil);
    end;
  finally
    if (fs <> nil) then
      fs.Free;
  end;
end;

function GetStringSetting(base: TJSONData; path: string; defaultValue: string = ''): string;
var
  data: TJSONData;
begin
  data := GetData(base, path);
  if (data = nil) or (data.JSONType <> jtString) then
    exit(defaultValue);
  try
    Result := data.AsString;
  except
    Result := defaultValue;
  end;
end;

function GetIntegerSetting(base: TJSONData; path: string; defaultValue: integer = 0): integer;
var
  data: TJSONData;
begin
  data := GetData(base, path);
  if (data = nil) or (data.JSONType <> jtNumber) then
    exit(defaultValue);
  try
    Result := data.AsInteger;
  except
    Result := defaultValue;
  end;
end;

function GetFloatSetting(base: TJSONData; path: string; defaultValue: TJSONFloat = 0.0): TJSONFloat;
var
  data: TJSONData;
begin
  data := GetData(base, path);
  if (data = nil) or (data.JSONType <> jtNumber) then
    exit(defaultValue);
  try
    Result := data.AsFloat;
  except
    Result := defaultValue;
  end;
end;

function GetBooleanSetting(base: TJSONData; path: string; defaultValue: boolean = false): boolean;
var
  data: TJSONData;
begin
  data := GetData(base, path);
  if (data = nil) or (data.JSONType <> jtBoolean) then
    exit(defaultValue);
  try
    Result := data.AsBoolean;
  except
    Result := defaultValue;
  end;
end;

function GetListSetting(base: TJSONData; path: string): TJSONArray;
var
  data: TJSONData;
begin
  data := GetData(base, path);
  if (data = nil) or (data.JSONType <> jtArray)  then
    exit(nil);
  Result := TJSONArray(data);
end;

function GetObjectSetting(base: TJSONData; path: string): TJSONObject;
var
  data: TJSONData;
begin
  data := GetData(base, path);
  if (data = nil) or (data.JSONType <> jtObject) then
    exit(nil);
  Result := TJSONObject(data);
end;

function SaveSettings(base: TJSONData; fileName: string): boolean;
var
  lst: TStrings;
begin
  if (base = nil) then
    exit(false);
  lst := nil;
  try
    try
      lst := TStringList.Create;
      lst.LineBreak := #13#10;
      lst.Text := AdjustLineBreaks(base.FormatJSON, tlbsCRLF);
      lst.SaveToFile(fileName);
      exit(true);
    except
      exit(false);
    end;
  finally
    if (lst <> nil) then
      lst.Free;
  end;
end;

procedure SetStringSetting(base: TJSONData; path: string; value: string = '');
var
  node: TJSONObject;
begin
  if (base = nil) then
    exit;
  node := GetOrInsertParent(base, path);
  if (node <> nil) then
    node.Strings[GetLocalAttributeName(path)] := value;
end;

procedure SetIntegerSetting(base: TJSONData; path: string; value: integer = 0);
var
  node: TJSONObject;
begin
  if (base = nil) then
    exit;
  node := GetOrInsertParent(base, path);
  if (node <> nil) then
    node.Integers[GetLocalAttributeName(path)] := value;
end;

procedure SetFloatSetting(base: TJSONData; path: string; value: TJSONFloat = 0.0);
var
  node: TJSONObject;
begin
  if (base = nil) then
    exit;
  node := GetOrInsertParent(base, path);
  if (node <> nil) then
    node.Floats[GetLocalAttributeName(path)] := value;
end;

procedure SetBooleanSetting(base: TJSONData; path: string; value: boolean = false);
var
  node: TJSONObject;
begin
  if (base = nil) then
    exit;
  node := GetOrInsertParent(base, path);
  if (node <> nil) then
    node.Booleans[GetLocalAttributeName(path)] := value;
end;

function SetListSetting(base: TJSONData; path: string; minCount: integer = 0): TJSONArray;
var
  node: TJSONObject;
  i: integer;
begin
  if (base = nil) then
    exit(nil);
  node := GetOrInsertParent(base, path);
  if (node <> nil) then
    begin
      try
        Result := node.Arrays[GetLocalAttributeName(path)];
      except
        Result := nil;
      end;
      if (Result = nil) or (Result.JSONType <> jtArray) then
        begin
          Result := TJSONArray.Create;
          node.Arrays[GetLocalAttributeName(path)] := Result;
        end;
      if (minCount < 0) then
        minCount := 0;
      if (Result.Count < minCount) then
        for i := 1 to minCount do
            Result.Add(0);
    end
  else
    exit(nil);
end;

function SetObjectSetting(base: TJSONData; path: string): TJSONObject;
var
  node: TJSONObject;
begin
  if (base = nil) then
    exit(nil);
  node := GetOrInsertParent(base, path);
  if (node <> nil) then
    begin
      try
        Result := node.Objects[GetLocalAttributeName(path)];
      except
        Result := nil;
      end;
      if (Result = nil) or (Result.JSONType <> jtObject) then
        begin
          Result := TJSONObject.Create;
          node.Objects[GetLocalAttributeName(path)] := Result;
        end;
    end
  else
    exit(nil);
end;

end.


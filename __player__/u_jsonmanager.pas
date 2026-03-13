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

implementation

function GetData(base: TJSONData; path: string = ''): TJSONData;
begin
  if (base = nil) then
    exit(nil);
  if (path = '') then
    exit(base);
  Result := base.FindPath(path);
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

end.



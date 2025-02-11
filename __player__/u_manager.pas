unit u_manager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, u_radio, u_utils;

type
  TRadioStationManager = class
  private
    _stations: TRadioStationList;
    _status: TRadioStatus;
    _rsindex: integer;
    _volume: double;
    _data: PFactionDistanceDataArray;
    _linearvolume: boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddRadioStation(station: TRadioStation);
    procedure Process(rsindex: integer; volume: double; data: PFactionDistanceDataArray; linearvolume: boolean; CurrentStatus: TRadioStatus);
    procedure SetRandomPos(maxrandompos: double);
    procedure SkipNextTrack;
    procedure ReplayCurrTrack;
    function GetNameList: TStringArray;
    procedure WriteReport(fileName: string);
    property Status: TRadioStatus read _status;
  end;

implementation

constructor TRadioStationManager.Create;
begin
  inherited;
  _stations := TRadioStationList.Create;
  Process(-1, 0.0, nil, false, rsPlaying);
end;

destructor TRadioStationManager.Destroy;
var
  i: integer;
begin
  for i := 0 to _stations.Count - 1 do
      _stations[i].Free;
  _stations.Free;
  inherited;
end;

procedure TRadioStationManager.AddRadioStation(station: TRadioStation);
begin
  if (_stations.IndexOf(station) < 0) then
     begin
       _stations.Add(station);
       Process(_rsindex, _volume, _data, _linearvolume, _status);
     end;
end;

procedure TRadioStationManager.Process(rsindex: integer; volume: double; data: PFactionDistanceDataArray; linearvolume: boolean; CurrentStatus: TRadioStatus);
var
  i: integer;
  locvol: double;
begin
  // Store external data
  if (CurrentStatus = rsError) then
     CurrentStatus := rsPaused;
  _status := CurrentStatus;
  _rsindex := NormalizeInt(rsindex, -1, _stations.Count - 1);
  _volume := NormalizeFloat(volume, 0.0, 1.0);
  _data := data;
  _linearvolume := linearvolume;

  // Do process
  locvol := _volume;
  if _linearvolume then
     locvol := (2 * locvol) - (locvol * locvol);
  for i := 0 to _stations.Count - 1 do
      begin
        if (_rsindex <> i) then
           _stations[i].Process(nil, 0.0, _status, false)
        else
          _stations[i].Process(_data, locvol, _status, true);
      end;
end;

procedure TRadioStationManager.SetRandomPos(maxrandompos: double);
var
  i: integer;
begin
  for i := 0 to _stations.Count - 1 do
      _stations[i].SetRandomPos(maxrandompos);
end;

procedure TRadioStationManager.SkipNextTrack;
begin
  if (_rsindex > -1) then
     _stations[_rsindex].SkipNextTrack;
end;

procedure TRadioStationManager.ReplayCurrTrack;
begin
  if (_rsindex > -1) then
     _stations[_rsindex].ReplayCurrTrack;
end;

function TRadioStationManager.GetNameList: TStringArray;
var
  i: integer;
begin
  SetLength(Result, _stations.Count);
  for i := 0 to _stations.Count - 1 do
      Result[i] := _stations[i].RadioStationName;
end;

procedure TRadioStationManager.WriteReport(fileName: string);
var
  report: TStrings;
  i: integer;
  log: System.Text;
begin
  report := TStringList.Create;
  try
    for i := 0 to _stations.Count - 1 do
        begin
          report.Add('Radio station %d:', [i + 1]);
          _stations[i].GenerateReport(report, 1);
          report.Add('');
        end;
    System.Assign(log, fileName);
    {$I-}
    Rewrite(log);
    for i := 0 to report.Count - 1 do
        writeln(log, report[i]);
    System.Close(log);
    {$I+}
  finally
    report.Free;
  end;
end;

end.


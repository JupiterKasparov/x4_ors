unit u_manager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, u_radio, u_utils;

type
  TRadioStationManager = class
  private
    _stations: TRadioStationList;
    _rsindex: integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddRadioStation(station: TRadioStation);
    procedure Process(currentStationIndex: integer; currentVolume: double; factionData: PFactionDistanceDataArray; bUseLinearVol: boolean; playbackStatus: TRadioStatus; currentTime: qword);
    procedure SetRandomPos(maxrandompos: double);
    procedure SkipNextTrack;
    procedure ReplayCurrTrack;
    function GetNameList: TStringArray;
    procedure WriteReport(fileName: string);
  end;

implementation

constructor TRadioStationManager.Create;
begin
  inherited;
  _stations := TRadioStationList.Create;
  Process(-1, 0.0, nil, false, rsPaused, 0);
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
       Process(-1, 0.0, nil, false, rsPaused, 0);
     end;
end;

procedure TRadioStationManager.Process(currentStationIndex: integer; currentVolume: double; factionData: PFactionDistanceDataArray; bUseLinearVol: boolean; playbackStatus: TRadioStatus; currentTime: qword);
var
  i: integer;
  locvol: double;
begin
  // Limit parameters to valid ranges
  if (playbackStatus = rsError) then
     playbackStatus := rsPaused;
  _rsindex := NormalizeInt(currentStationIndex, -1, _stations.Count - 1);
  currentVolume := NormalizeFloat(currentVolume, 0.0, 1.0);

  // Do process
  locvol := currentVolume;
  if bUseLinearVol then
     locvol := (2 * locvol) - (locvol * locvol);
  for i := 0 to _stations.Count - 1 do
      begin
        if (_rsindex <> i) then
           _stations[i].Process(nil, 0.0, playbackStatus, currentTime, false)
        else
          _stations[i].Process(factionData, locvol, playbackStatus, currentTime, true);
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


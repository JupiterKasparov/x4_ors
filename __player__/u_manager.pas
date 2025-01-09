unit u_manager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, u_radio;

type
  TRadioStationManager = class
  private
    _stations: TRadioStationList;
    _status: TRadioStatus;
    _rsindex: integer;
    _volume: double;
    _data: PFactionDistanceDataArray;
    _linearvolume: boolean;
    procedure int_SetStatus(st: TRadioStatus);
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddRadioStation(station: TRadioStation);
    procedure Process(rsindex: integer; volume: double; data: PFactionDistanceDataArray; linearvolume: boolean);
    procedure SetRandomPos(maxrandompos: double);
    procedure SkipNextTrack;
    procedure ReplayCurrTrack;
    function GetNameList: TStringArray;
    property Status: TRadioStatus read _status write int_SetStatus;
  end;

implementation

procedure TRadioStationManager.int_SetStatus(st: TRadioStatus);
begin
  if (_status = rsError) or (st = rsError) then
     exit;
  _status := st;
  Process(_rsindex, _volume, _data, _linearvolume);
end;

constructor TRadioStationManager.Create;
begin
  inherited;
  _stations := TRadioStationList.Create;
  _status := rsPlaying;
  Process(-1, 0.0, nil, false);
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
       Process(_rsindex, _volume, _data, _linearvolume);
     end;
end;

procedure TRadioStationManager.Process(rsindex: integer; volume: double; data: PFactionDistanceDataArray; linearvolume: boolean);
var
  i: integer;
  locvol: double;
begin
  // Store external data
  _rsindex := rsindex;
  if (_rsindex > _stations.Count - 1) or (_rsindex < -1) then
     _rsindex := -1;
  _volume := volume;
  if (_volume > 1.0) then
     _volume := 1.0
  else if (_volume < 0.0) then
     _volume := 0.0;
  _data := data;
  _linearvolume := linearvolume;

  // Do process
  locvol := _volume;
  if _linearvolume then
     locvol := (2 * locvol) - (locvol * locvol);
  for i := 0 to _stations.Count - 1 do
      begin
        if (_rsindex <> i) then
           _stations[i].Process(nil, 0.0)
        else
          _stations[i].Process(_data, locvol);
        _stations[i].Status := _status;
      end;
end;

procedure TRadioStationManager.SetRandomPos(maxrandompos: double);
var
  i: integer;
begin
  for i := 0to _stations.Count - 1 do
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

end.


unit u_filechooser;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, EditBtn,
  ExtCtrls, u_osutils;

type

  TFrmFileChooserLocationType = (ffcltFile, ffcltDirectory, ffcltURL);

  { TFrmFileChooser }

  TFrmFileChooser = class(TForm)
    DlgOpenFile: TOpenDialog;
    DlgOpenDir: TSelectDirectoryDialog;
    LblLocType: TLabel;
    LblLocation: TLabel;
    LvLocType: TComboBox;
    LvLocation: TEditButton;
    LeOK: TButton;
    LeCancel: TButton;
    procedure ev_ChangeLocationType(Sender: TObject);
    procedure ev_ChooseLocation(Sender: TObject);
    procedure ev_InitWindow(Sender: TObject);
  private
    function GetFileName: string;
    procedure SetFileName(fn: string);
    function GetLocationType: TFrmFileChooserLocationType;
    procedure SetLocationType(loc: TFrmFileChooserLocationType);
  public
    property FileName: string read GetFileName write SetFileName;
    property LocationType: TFrmFileChooserLocationType read GetLocationType write SetLocationType;
  end;

var
  FrmFileChooser: TFrmFileChooser;

implementation

{$R *.lfm}

{ TFrmFileChooser }

function TFrmFileChooser.GetFileName: string;
begin
  Result := LvLocation.Text;
end;

procedure TFrmFileChooser.SetFileName(fn: string);
begin
  LvLocation.Text := fn;
end;

function TFrmFileChooser.GetLocationType: TFrmFileChooserLocationType;
begin
  case LvLocType.ItemIndex of
       0: Result := ffcltFile;
       1: Result := ffcltDirectory;
       else Result := ffcltURL;
  end;
end;

procedure TFrmFileChooser.SetLocationType(loc: TFrmFileChooserLocationType);
begin
  case loc of
       ffcltFile: LvLocType.ItemIndex := 0;
       ffcltDirectory: LvLocType.ItemIndex := 1;
       else LvLocType.ItemIndex := 2;
  end;
  if Assigned(LvLocType.OnChange) then
     LvLocType.OnChange(LvLocType);
end;

procedure TFrmFileChooser.ev_ChooseLocation(Sender: TObject);
begin
  if (LvLocType.ItemIndex = 0) then
     begin
       if DlgOpenFile.Execute then
          LvLocation.Text := DlgOpenFile.FileName;
     end
  else if (LvLocType.ItemIndex = 1) then
     begin
       if DlgOpenDir.Execute then
          LvLocation.Text := DlgOpenDir.FileName;
     end;
end;

procedure TFrmFileChooser.ev_InitWindow(Sender: TObject);
begin
  SetLocationType(ffcltFile);
  UpdateForm(self);
end;

procedure TFrmFileChooser.ev_ChangeLocationType(Sender: TObject);
begin
  LvLocation.Button.Enabled := LvLocType.ItemIndex <> 2;
  LvLocation.DirectInput := not LvLocation.Button.Enabled;
end;

end.


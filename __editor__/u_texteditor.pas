unit u_texteditor;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, u_osutils;

type

  { TFrmStringEditor }

  TFrmStringEditor = class(TForm)
    TvTextEditor: TMemo;
    TeCancel: TButton;
    TeOK: TButton;
    procedure ev_InitWindow(Sender: TObject);
  private
    function GetEditText: string;
    procedure SetEditText(txt: string);
  public
    property EditText: string read GetEditText write SetEditText;
  end;

var
  FrmStringEditor: TFrmStringEditor;

implementation

{$R *.lfm}

{ TFrmStringEditor }

procedure TFrmStringEditor.ev_InitWindow(Sender: TObject);
begin
  UpdateForm(self);
end;

function TFrmStringEditor.GetEditText: string;
begin
  Result := Trim(AdjustLineBreaks(TvTextEditor.Lines.Text, tlbsCRLF));
end;

procedure TFrmStringEditor.SetEditText(txt: string);
begin
  TvTextEditor.Lines.Text := Trim(txt);
end;

end.


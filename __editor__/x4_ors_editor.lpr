program x4_ors_editor;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, editor, u_filechooser, u_texteditor, u_keyeditor,
  u_jsonmanager, u_oldconvert, u_osutils
  { you can add units after this };

{$R *.res}

begin
  RequireDerivedFormResource:=True;
  Application.Scaled:=True;
  {$PUSH}{$WARN 5044 OFF}
  Application.MainFormOnTaskbar:=True;
  {$POP}
  Application.Initialize;
  Application.CreateForm(TFrmEditor, FrmEditor);
  Application.CreateForm(TFrmFileChooser, FrmFileChooser);
  Application.CreateForm(TFrmStringEditor, FrmStringEditor);
  Application.CreateForm(TFrmKeyEditor, FrmKeyEditor);
  Application.Run;
end.


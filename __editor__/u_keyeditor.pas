unit u_keyeditor;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, EditBtn,
  ExtCtrls, LCLType, LCLIntf, LCLProc, u_osutils,
  {$IFDEF MSWINDOWS}
  Windows
  {$ELSE}
  BaseUnix, xlib, x, gtk2, gdk2
  {$ENDIF};

type

  { TFrmKeyEditor }

  TFrmKeyEditor = class(TForm)
    KeWaitingIcon: TImage;
    KvKeyEdit: TEditButton;
    LbkKeyWaitingState: TLabel;
    KeUnbind: TButton;
    KeCancel: TButton;
    KeOK: TButton;
    procedure ev_AcquireKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ev_CloseWindow(Sender: TObject; var CloseAction: TCloseAction);
    procedure ev_InitWindow(Sender: TObject);
    procedure ev_StartAcquireKey(Sender: TObject);
    procedure ev_Unbind(Sender: TObject);
  private
    myKeycode: Word;
    procedure SetKeycode(key: Word);
  public
    property KeyCode: Word read myKeycode write SetKeycode;
  end;

function GetKeyName(vk: Word): string;

var
  FrmKeyEditor: TFrmKeyEditor;

implementation

{$IFDEF MSWINDOWS}
function GetPlatformKeyName(vk: Word): string;
var
  keyState: TKeyboardState;
  i: integer;
  uc: array [0..1] of UnicodeChar;
begin
  Result := '';

  // Hardcoded name check (technical reasons)
  case vk of
       VK_SHIFT: Result := 'Shift';
       VK_LSHIFT: Result := 'L Shift';
       VK_RSHIFT: Result := 'R Shift';
       VK_CONTROL: Result := 'Ctrl';
       VK_LCONTROL: Result := 'L Ctrl';
       VK_RCONTROL: Result := 'R Ctrl';
       VK_MENU: Result := 'Alt';
       VK_LMENU: Result := 'L Alt';
       VK_RMENU: Result := 'R Alt';
       VK_LWIN: Result := 'L Windows';
       VK_RWIN: Result := 'R Windows';
       VK_RETURN: Result := 'Enter';
       VK_ESCAPE: Result := 'Esc';
       VK_SPACE: Result := 'Space';
       VK_TAB: Result := 'Tab';
       VK_BACK: Result := 'Backspace';
       VK_CAPITAL: Result := 'Caps Lock';
       VK_NUMPAD0..VK_NUMPAD9: Result := Format('Num %d', [vk - VK_NUMPAD0]);
       VK_ADD: Result := 'Num +';
       VK_SUBTRACT: Result := 'Num -';
       VK_MULTIPLY: Result := 'Num *';
       VK_DIVIDE: Result := 'Num /';
       VK_DECIMAL: Result := 'Num .';
  end;
  if (Result <> '') then
     exit(Result);

  // Get key name
  for i := Low(keyState) to High(keyState) do
      keyState[i] := 0;
  keyState[vk] := $80;
  if (ToUnicode(vk, MapVirtualKey(vk, 0), keyState, @uc[0], Length(uc), 0) > 0) then
     Result := Trim(UTF8Encode(UnicodeString(UC)));

  // Fallback
  if (Result = '') then
     Result := KeyAndShiftStateToKeyString(vk, []);
end;
{$ELSE}
var
  xdisplay: PDisplay;

function GetPlatformKeyName(vk: Word): string;
var
  lsym: TKeySym;
  pName: PChar;
begin
  Result := '';
  if (xdisplay <> nil) then
     begin
       lsym := TKeySym(vk);
       XKeysymToString(lsym);
       pName := XKeysymToString(lsym);
       if (pName <> nil) then
          Result := Trim(StrPas(pName));
     end;
end;
{$ENDIF}

function GetKeyName(vk: Word): string;
begin
  if (vk = 0) then
     exit('');
  Result := Trim(GetPlatformKeyName(vk));
  if (Length(Result) < 1) then
    Result := Format('VK %d', [vk])
  {$IFDEF MSWINDOWS}
  else if (Ord(Result[1]) <= 127) then
    Result[1] := UpCase(Result[1]);
  {$ENDIF}
end;

{$R *.lfm}

{ TFrmKeyEditor }

procedure TFrmKeyEditor.SetKeycode(key: Word);
begin
  if (key = VK_ESCAPE) then
     key := 0;
  myKeycode := key;
  KvKeyEdit.Text := GetKeyName(myKeycode);
end;

procedure TFrmKeyEditor.ev_AcquireKey(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  locKeyCode: DWORD;
  {$IFDEF LINUX}
  eventKey: PGdkEventKey;
  {$ENDIF}
begin
  if KeyPreview then
     begin
       {$IFDEF MSWINDOWS}
       locKeyCode := Key;
       case locKeyCode of
            VK_SHIFT:
              begin
                if (GetKeyState(VK_LSHIFT) < 0) then
                   locKeyCode := VK_LSHIFT
                else
                   locKeyCode := VK_RSHIFT;
              end;
            VK_CONTROL:
              begin
                if (GetKeyState(VK_LCONTROL) < 0) then
                   locKeyCode := VK_LCONTROL
                else
                   locKeyCode := VK_RCONTROL;
              end;
            VK_MENU:
              begin
                if (GetKeyState(VK_LMENU) < 0) then
                   locKeyCode := VK_LMENU
                else
                   locKeyCode := VK_RMENU;
              end;
            else
              locKeyCode := Key;
       end;
       {$ELSE}
       eventKey := PGdkEventKey(gtk_get_current_event);
       if (eventKey <> nil) then
          begin
            locKeyCode := eventKey^.keyval;
            if (locKeyCode = GDK_KEY_Escape) then
               locKeyCode := VK_ESCAPE; // Manual override - ESC is the Unbind key!
            gdk_event_free(PGdkEvent(eventKey));
          end
       else
          locKeyCode := 0;
       {$ENDIF}
       if (locKeyCode <> 0) and (locKeyCode <> VK_ESCAPE) then
          SetKeycode(locKeyCode);
       KvKeyEdit.Enabled := true;
       KeUnbind.Enabled := true;
       KeWaitingIcon.Visible := false;
       LbkKeyWaitingState.Visible := false;
       KeyPreview := false;
       Key := 0;
     end;
end;

procedure TFrmKeyEditor.ev_CloseWindow(Sender: TObject; var CloseAction: TCloseAction);
begin
  KvKeyEdit.Enabled := true;
  KeUnbind.Enabled := true;
  KeWaitingIcon.Visible := false;
  LbkKeyWaitingState.Visible := false;
  KeyPreview := false;
end;

procedure TFrmKeyEditor.ev_InitWindow(Sender: TObject);
begin
  SetKeycode(0);
  KeyPreview := false;
  UpdateForm(self);
end;

procedure TFrmKeyEditor.ev_StartAcquireKey(Sender: TObject);
begin
  if not KeyPreview then
     begin
       KvKeyEdit.Enabled := false;
       KeUnbind.Enabled := false;
       KeWaitingIcon.Visible := true;
       LbkKeyWaitingState.Visible := true;
       KeyPreview := true;
     end;
end;

procedure TFrmKeyEditor.ev_Unbind(Sender: TObject);
begin
  SetKeycode(0);
end;

{$IFDEF LINUX}
initialization
  xdisplay := XOpenDisplay(nil);

finalization
  if (xdisplay <> nil) then
     XCloseDisplay(xdisplay);
{$ENDIF}

end.


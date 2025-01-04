unit editor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Spin, Windows, IniFiles;

type

  { TFrmEditor }

  TFrmEditor = class(TForm)
    BtkModifier1: TButton;
    BtkModifier2: TButton;
    BtSelectFile: TButton;
    BtkNextStation: TButton;
    BtkPrevStation: TButton;
    BtkReloadMod: TButton;
    BtkReplayMP3: TButton;
    BtkSkipMP3: TButton;
    GbrStationProps: TGroupBox;
    GbrSlotProps: TGroupBox;
    LbrName: TLabel;
    LbrSelectSlot: TLabel;
    LbrSlotDampeningFactor: TLabel;
    LbrSlotFileName: TLabel;
    LbrSlotCount: TLabel;
    LbrMasterLoudnessFactor: TLabel;
    LbrSlotLoudnessFactor: TLabel;
    LbrSlotOwnerList: TLabel;
    PrSlotOnlyProps: TPanel;
    RvName: TEdit;
    RvMasterLoudnessFactor: TTrackBar;
    RvSlotDampeningFactor: TTrackBar;
    RvSlotFileName: TEdit;
    RvSelectSlot: TComboBox;
    RvSelectStation: TComboBox;
    LbrSelectStation: TLabel;
    MvName: TEdit;
    LbmName: TLabel;
    MvLoudnessFactor: TTrackBar;
    LbmLoudnessFactor: TLabel;
    MvEnable: TComboBox;
    GvRandomizeTracks: TComboBox;
    GvLatency: TSpinEdit;
    GvOnlineStreams: TComboBox;
    GvLinearVolume: TComboBox;
    LbmEnable: TLabel;
    LbgLoudnessFactor: TLabel;
    LbgLinearVolume: TLabel;
    LbgOnlineStreams: TLabel;
    LbgRandomizeTracks: TLabel;
    LbgLatency: TLabel;
    LbgNoOfStations: TLabel;
    LbkModifier1: TLabel;
    BtkvModifier1: TLabel;
    LbkModifier2: TLabel;
    LbkvModifier2: TLabel;
    LbkNextStation: TLabel;
    LbkvNextStation: TLabel;
    LbkPrevStation: TLabel;
    LbkvPrevStation: TLabel;
    LbkReloadMod: TLabel;
    LbkvReloadMod: TLabel;
    LbkReplayMP3: TLabel;
    LbkvReplayMP3: TLabel;
    LbkSkipMP3: TLabel;
    LbkvSkipMP3: TLabel;
    DlgSelectFile: TOpenDialog;
    PgEditorPages: TPageControl;
    PgEditGlobal: TTabSheet;
    PgEditKeys: TTabSheet;
    GvNoOfStations: TSpinEdit;
    PgEditMP3: TTabSheet;
    PgEditRs: TTabSheet;
    RvSlotCount: TSpinEdit;
    RvSlotLoudnessFactor: TTrackBar;
    RvSlotOwnerList: TEdit;
    TmrUpdate: TTimer;
    GvLoudnessFactor: TTrackBar;
    procedure ev_CanClose(Sender: TObject; var CanClose: boolean);
    procedure ev_Change_gLatency(Sender: TObject);
    procedure ev_Change_gLinearVolume(Sender: TObject);
    procedure ev_Change_gLoudnessFactor(Sender: TObject);
    procedure ev_Change_gNoOfStations(Sender: TObject);
    procedure ev_Change_gOnlineStreams(Sender: TObject);
    procedure ev_Change_gRandomizeTracks(Sender: TObject);
    procedure ev_Change_Keys(Sender: TObject);
    procedure ev_Change_mEnable(Sender: TObject);
    procedure ev_Change_mLoudnessFactor(Sender: TObject);
    procedure ev_Change_mName(Sender: TObject);
    procedure ev_Change_rLoudnessFactor(Sender: TObject);
    procedure ev_Change_rName(Sender: TObject);
    procedure ev_Change_rSlotCount(Sender: TObject);
    procedure ev_Change_rSlotDampeningFactor(Sender: TObject);
    procedure ev_Change_rSlotFileName(Sender: TObject);
    procedure ev_Change_rSlotLoudnessFactor(Sender: TObject);
    procedure ev_Change_rSlotOwnerList(Sender: TObject);
    procedure ev_Draw(Sender: TObject);
    procedure ev_Free(Sender: TObject);
    procedure ev_Init(Sender: TObject);
    procedure ev_KeyPress(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ev_SelectFile(Sender: TObject);
    procedure ev_SelectSlot(Sender: TObject);
    procedure ev_SelectStation(Sender: TObject);
    procedure ev_Update(Sender: TObject);
  private
    settings: TIniFile;
    lastkey: word;
    keys: array [1..7] of integer;
    doUpdateIni: boolean;
    procedure ShowWriteFailedError;
  public
    { public declarations }
  end;

var
  FrmEditor: TFrmEditor;

implementation

function ToUnicodeEx(wVirtKey, wScanCode: UINT; lpKeyState: PByte;  pwszBuff: PWideChar; cchBuff: Integer; wFlags: UINT; dwhkl: HKL): Integer; stdcall; external 'user32.dll';

function StandardKeyToStringW(WindowHandle: HWND; VKey: DWORD): widestring;
var
  name: array [0..31] of widechar;
  kbState: array [0..255] of byte;
  idThread: DWORD;
  code: LONG;
begin
  ZeroMemory(@name[0], Length(name));
  ZeroMemory(@kbState[0], Length(kbState));
  idThread := GetWindowThreadProcessId(WindowHandle, nil);
  code := MapVirtualKeyExW(VKey, 0, GetKeyboardLayout(idThread));
  case VKey of
       VK_LEFT,
       VK_UP,
       VK_RIGHT,
       VK_DOWN,
       VK_PRIOR,
       VK_NEXT,
       VK_END,
       VK_HOME,
       VK_INSERT,
       VK_DELETE,
       VK_DIVIDE,
       VK_NUMLOCK:
         code := code or $100; // set extended bit
  end;
  code := code shl 16;
  ToUnicodeEx(VKey, code, kbState, name, 32, 0, GetKeyboardLayout(idThread));
  Result := WideString(name);
  if (Trim(Result) = '') then
     begin
       GetKeyNameTextW(code, name, 32);
       Result := WideString(name);
     end;
  Result := UpCase(Result);
end;

{$R *.lfm}

{ TFrmEditor }

procedure TFrmEditor.ShowWriteFailedError;
begin
  Application.MessageBox('Failed to write new value to file!', '', MB_OK + MB_ICONERROR);
end;

procedure TFrmEditor.ev_CanClose(Sender: TObject; var CanClose: boolean);
begin
  // Prevent closing the window, if we're waiting for a keypress
  CanClose := PgEditorPages.Visible or BtSelectFile.Visible;
end;

procedure TFrmEditor.ev_Change_gLatency(Sender: TObject);
begin
  if doUpdateIni and Assigned(settings) then
     try
       settings.WriteInteger('Global', 'Latency', GvLatency.Value);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_gLinearVolume(Sender: TObject);
begin
  if doUpdateIni and Assigned(settings) then
     try
       if (GvLinearVolume.ItemIndex = 0) then
          settings.WriteInteger('Global', 'UseLinearVolume', 0)
       else
          settings.WriteInteger('Global', 'UseLinearVolume', 1);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_gLoudnessFactor(Sender: TObject);
begin
  if doUpdateIni and Assigned(settings) then
     try
       settings.WriteFloat('Global', 'LoudnessFactor', GvLoudnessFactor.Position / 100.0);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_gNoOfStations(Sender: TObject);
var
  stationcount, i: integer;
  section: string;
begin
  if doUpdateIni and Assigned(settings) then
     try
       stationcount := settings.ReadInteger('Global', 'NumberOfStations', 0);
       settings.WriteInteger('Global', 'NumberOfStations', GvNoOfStations.Value);
       if (GvNoOfStations.Value < stationcount) then
          for i := GvNoOfStations.Value + 1 to stationcount do
              begin
                section := Format('Radio_%d', [i]);
                if settings.SectionExists(section) then
                   settings.EraseSection(section);
              end;
     except
       ShowWriteFailedError;
       exit;
     end;

  // Update editor
  RvSelectStation.Items.Clear;
  if (GvNoOfStations.Value > 0) then
     begin
       for i := 1 to GvNoOfStations.Value do
           RvSelectStation.Items.Add('Station %d', [i]);
       RvSelectStation.ItemIndex := 0;
     end
  else
     RvSelectStation.ItemIndex := -1;
  GbrStationProps.Visible := RvSelectStation.ItemIndex >= 0;
  RvSelectStation.Enabled := GvNoOfStations.Value > 0;
  if Assigned(RvSelectStation.OnChange) then
     RvSelectStation.OnChange(RvSelectStation);
end;

procedure TFrmEditor.ev_Change_gOnlineStreams(Sender: TObject);
begin
  if doUpdateIni and Assigned(settings) then
     try
       if (GvOnlineStreams.ItemIndex = 0) then
          settings.WriteInteger('Global', 'NoOnlineStreams', 1)
       else
          settings.WriteInteger('Global', 'NoOnlineStreams', 0);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_gRandomizeTracks(Sender: TObject);
begin
  if doUpdateIni and Assigned(settings) then
     try
       if (GvRandomizeTracks.ItemIndex = 0) then
          settings.WriteInteger('Global', 'RandomizeTracks', 0)
       else
          settings.WriteInteger('Global', 'RandomizeTracks', 1);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_Keys(Sender: TObject);
var
  index: integer;
  prop: string;
  i: integer;
begin
  PgEditorPages.Visible := false;
  try
    index := 0;
    if (Sender = BtkModifier1) then
       begin
         index := 1;
         prop := 'Modifier_1';
       end
    else if (Sender = BtkModifier2) then
       begin
         index := 2;
         prop := 'Modifier_2';
       end
    else if (Sender = BtkPrevStation) then
       begin
         index := 3;
         prop := 'Func_PrevStation';
       end
    else if (Sender = BtkNextStation) then
       begin
         index := 4;
         prop := 'Func_NextStation';
       end
    else if (Sender = BtkReplayMP3) then
       begin
         index := 5;
         prop := 'Func_ReplayThisMP3';
       end
    else if (Sender = BtkSkipMP3) then
       begin
         index := 6;
         prop := 'Func_SkipThisMP3';
       end
    else if (Sender = BtkReloadMod) then
       begin
         index := 7;
         prop := 'Func_ReloadApp';
       end;
    if (index > 0) then
       begin
         while (lastkey = 0) and (lastkey <> VK_ESCAPE) do
               begin
                 Repaint;
                 Application.ProcessMessages;
               end;
         if (lastkey <> VK_ESCAPE) then
            begin
              for i := Low(keys) to High(keys) do
                  if (i <> index) and (lastkey <> 0) and (lastkey = keys[i]) then
                     begin
                       Application.MessageBox('Cannot use the same key twice!', '', MB_OK + MB_ICONERROR);
                       exit;
                     end;
            end
         else
            lastkey := 0;
         try
           settings.WriteInteger('Keys', prop, lastkey);
           keys[index] := lastkey;
         except
           ShowWriteFailedError;
         end;
       end;
  finally
    PgEditorPages.Visible := true;
    ev_Update(Sender);
    Repaint;
    lastkey := 0;
  end;
end;

procedure TFrmEditor.ev_Change_mEnable(Sender: TObject);
begin
  if doUpdateIni and Assigned(settings) then
     try
       if (MvEnable.ItemIndex = 0) then
          settings.WriteInteger('Radio_MP3', 'Enabled', 0)
       else
          settings.WriteInteger('Radio_MP3', 'Enabled', 1);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_mLoudnessFactor(Sender: TObject);
begin
  if doUpdateIni and Assigned(settings) then
     try
       settings.WriteFloat('Radio_MP3', 'LoudnessFactor', MvLoudnessFactor.Position / 100.0);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_mName(Sender: TObject);
begin
  if doUpdateIni and Assigned(settings) then
     try
       settings.WriteString('Radio_MP3', 'RadioText', MvName.Text);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_rLoudnessFactor(Sender: TObject);
var
  section: string;
begin
  if doUpdateIni and Assigned(settings) then
     try
       section := Format('Radio_%d', [RvSelectStation.ItemIndex + 1]);
       if (RvSlotCount.Value > 0) then
          settings.WriteFloat(section, 'MasterLoudnessFactor', RvMasterLoudnessFactor.Position / 100.0)
       else
          settings.WriteFloat(section, 'LoudnessFactor', RvMasterLoudnessFactor.Position / 100.0);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_rName(Sender: TObject);
var
  section: string;
begin
  if doUpdateIni and Assigned(settings) then
     try
       section := Format('Radio_%d', [RvSelectStation.ItemIndex + 1]);
       settings.WriteString(section, 'RadioText', RvName.Text);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_rSlotCount(Sender: TObject);
var
  section, key: string;
  slotcount, i: integer;
begin
  if doUpdateIni and Assigned(settings) then
     try
       section := Format('Radio_%d', [RvSelectStation.ItemIndex + 1]);
       slotcount := settings.ReadInteger(section, 'SlotCount', 0);
       settings.WriteInteger(section, 'SlotCount', RvSlotCount.Value);
       if (RvSlotCount.Value = 0) and (slotcount > 0) then
          begin
            // Convert Slot 1 to default slot
            settings.WriteFloat(section, 'LoudnessFactor', settings.ReadFloat(section, 'MasterLoudnessFactor', 0.0));
            settings.DeleteKey(section, 'MasterLoudnessFactor');
            settings.WriteString(section, 'FileName', settings.ReadString(section, 'SlotFileName_1', ''));
            settings.DeleteKey(section, 'SlotFileName_1');
            settings.WriteString(section, 'Owner', settings.ReadString(section, 'SlotOwner_1', ''));
            settings.DeleteKey(section, 'SlotOwner_1');
            settings.DeleteKey(section, 'SlotLoudnessFactor_1');
            settings.DeleteKey(section, 'SlotDampeningFactor_1');
          end
       else if (RvSlotCount.Value > 0) and (slotcount = 0) then
          begin
            // Convert default slot to Slot 1
            settings.WriteFloat(section, 'MasterLoudnessFactor', settings.ReadFloat(section, 'LoudnessFactor', 0.0));
            settings.DeleteKey(section, 'LoudnessFactor');
            settings.WriteString(section, 'SlotFileName_1', settings.ReadString(section, 'FileName', ''));
            settings.DeleteKey(section, 'FileName');
            settings.WriteString(section, 'SlotOwner_1', settings.ReadString(section, 'Owner', ''));
            settings.DeleteKey(section, 'Owner');
            settings.WriteFloat(section, 'SlotLoudnessFactor_1', 1.0);
            settings.WriteFloat(section, 'SlotDampeningFactor_1', 1.0);
          end;
       if (RvSlotCount.Value < slotcount) then
          for i := RvSlotCount.Value + 1 to slotcount do
              begin
                key := Format('SlotFileName_%d', [i]);
                settings.DeleteKey(section, key);
                key := Format('SlotOwner_%d', [i]);
                settings.DeleteKey(section, key);
                key := Format('SlotLoudnessFactor_%d', [i]);
                settings.DeleteKey(section, key);
                key := Format('SlotDampeningFactor_%d', [i]);
                settings.DeleteKey(section, key);
              end;
     except
       ShowWriteFailedError;
       exit;
     end;

  // Update editor
  RvSelectSlot.Items.Clear;
  if (RvSlotCount.Value > 0) then
     begin
       RvSelectSlot.Enabled := true;
       for i := 1 to RvSlotCount.Value do
         RvSelectSlot.Items.Add('Slot %d', [i]);
     end
  else
     begin
       RvSelectSlot.Items.Add('default');
       RvSelectSlot.Enabled := false;
     end;
  RvSelectSlot.ItemIndex := 0;
  if Assigned(RvSelectSlot.OnChange) then
     RvSelectSlot.OnChange(RvSelectSlot);
end;

procedure TFrmEditor.ev_Change_rSlotDampeningFactor(Sender: TObject);
var
  section, key: string;
begin
  if doUpdateIni and Assigned(settings) and (RvSlotCount.Value > 0) then
     try
       section := Format('Radio_%d', [RvSelectStation.ItemIndex + 1]);
       key := Format('SlotDampeningFactor_%d', [RvSelectSlot.ItemIndex + 1]);
       settings.WriteFloat(section, key, RvSlotDampeningFactor.Position / 100.0);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_rSlotFileName(Sender: TObject);
var
  section, key: string;
begin
  if doUpdateIni and Assigned(settings) then
     try
       section := Format('Radio_%d', [RvSelectStation.ItemIndex + 1]);
       if (RvSlotCount.Value > 0) then
          key := Format('SlotFileName_%d', [RvSelectSlot.ItemIndex + 1])
       else
          key := 'FileName';
       settings.WriteString(section, key, RvSlotFileName.Text);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_rSlotLoudnessFactor(Sender: TObject);
var
  section, key: string;
begin
  if doUpdateIni and Assigned(settings) and (RvSlotCount.Value > 0) then
     try
       section := Format('Radio_%d', [RvSelectStation.ItemIndex + 1]);
       key := Format('SlotLoudnessFactor_%d', [RvSelectSlot.ItemIndex + 1]);
       settings.WriteFloat(section, key, RvSlotLoudnessFactor.Position / 100.0);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Change_rSlotOwnerList(Sender: TObject);
var
  section, key: string;
begin
  if doUpdateIni and Assigned(settings) then
     try
       section := Format('Radio_%d', [RvSelectStation.ItemIndex + 1]);
       if (RvSlotCount.Value > 0) then
          key := Format('SlotOwner_%d', [RvSelectSlot.ItemIndex + 1])
       else
          key := 'Owner';
       settings.WriteString(section, key, RvSlotOwnerList.Text);
     except
       ShowWriteFailedError;
     end;
end;

procedure TFrmEditor.ev_Draw(Sender: TObject);
var
  textStyle: TTextStyle;
begin
  // When waiting for keypress!
  if (not PgEditorPages.Visible) and (not BtSelectFile.Visible) then
     begin
       textStyle := Canvas.TextStyle;
       textStyle.Alignment := taCenter;
       textStyle.Layout := tlCenter;
       textStyle.SingleLine := false;
       textStyle.Wordbreak := true;
       Canvas.Pen.Style := psClear;
       Canvas.Brush.Style := bsSolid;
       Canvas.Brush.Color := Canvas.Font.Color xor High(TColor);
       Canvas.Rectangle(0, 0, Width, Height);
       Canvas.TextRect(Classes.Rect(0, 0, Width, Height), 0, 0,
                                        'Waiting for User Input'#13#10 +
                                        'ESC = unbind function key'#13#10 +
                                        'Any other key = bind to function',
                                        textStyle);
     end;
end;

procedure TFrmEditor.ev_Free(Sender: TObject);
begin
  if Assigned(settings) then
     settings.Free;
end;

procedure TFrmEditor.ev_Init(Sender: TObject);
begin
  // Init
  settings := nil;
  lastkey := 0;
  ZeroMemory(@keys[1], Length(keys) * sizeof(integer));
  doUpdateIni := true;

  // GUI setup
  SetBounds(Left, Top, PgEditorPages.Width, PgEditorPages.Height);
  PgEditorPages.Visible := false;
  BtSelectFile.Left := (Width div 2) - (BtSelectFile.Width div 2);
  BtSelectFile.Top := (Height div 2) - (BtSelectFile.Height div 2);
  ev_Update(Sender);
end;

procedure TFrmEditor.ev_KeyPress(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  // When waiting for keypress!
  if (not PgEditorPages.Visible) and (not BtSelectFile.Visible) then
     lastkey := Key;
  Key := 0;
end;

procedure TFrmEditor.ev_SelectFile(Sender: TObject);
begin
  if DlgSelectFile.Execute then
     begin
       if Assigned(settings) then
          settings.Free;
       settings := TIniFile.Create(DlgSelectFile.FileName, [ifoFormatSettingsActive]);
       settings.FormatSettings.DecimalSeparator := '.';
       settings.CacheUpdates := false;
       doUpdateIni := false; // Disallow file updates
       try
         // Global settings
         GvNoOfStations.Value := settings.ReadInteger('Global', 'NumberOfStations', 0);
         GvLatency.Value := settings.ReadInteger('Global', 'Latency', 1000);
         if (settings.ReadInteger('Global', 'RandomizeTracks', 0) <> 0) then
            GvRandomizeTracks.ItemIndex := 1
         else
            GvRandomizeTracks.ItemIndex := 0;
         if (settings.ReadInteger('Global', 'NoOnlineStreams', 0) <> 0) then
            GvOnlineStreams.ItemIndex := 0
         else
            GvOnlineStreams.ItemIndex := 1;
         if (settings.ReadInteger('Global', 'UseLinearVolume', 0) <> 0) then
            GvLinearVolume.ItemIndex := 1
         else
            GvLinearVolume.ItemIndex := 0;
         GvLoudnessFactor.Position := round(settings.ReadFloat('Global', 'LoudnessFactor', 1.0) * 100);

         // Key bindings
         keys[1] := settings.ReadInteger('Keys', 'Modifier_1', 0);
         keys[2] := settings.ReadInteger('Keys', 'Modifier_2', 0);
         keys[3] := settings.ReadInteger('Keys', 'Func_PrevStation', 0);
         keys[4] := settings.ReadInteger('Keys', 'Func_NextStation', 0);
         keys[5] := settings.ReadInteger('Keys', 'Func_ReplayThisMP3', 0);
         keys[6] := settings.ReadInteger('Keys', 'Func_SkipThisMP3', 0);
         keys[7] := settings.ReadInteger('Keys', 'Func_ReloadApp', 0);

         // MP3 player settings
         if (settings.ReadInteger('Radio_MP3', 'Enabled', 0) <> 0) then
            MvEnable.ItemIndex := 1
         else
            MvEnable.ItemIndex := 0;
         MvLoudnessFactor.Position := round(settings.ReadFloat('Radio_MP3', 'LoudnessFactor', 0.0) * 100);
         MvName.Text := settings.ReadString('Radio_MP3', 'RadioText', '?Unnamed MP3 Station?');

         // Show the UI
         BtSelectFile.Visible := false;
         PgEditorPages.Visible := true;
       except
         // Error - set back to defaults
         GvNoOfStations.Value := 0;
         GvLatency.Value := 10;
         GvRandomizeTracks.ItemIndex := 0;
         GvOnlineStreams.ItemIndex := 1;
         GvLinearVolume.ItemIndex := 0;
         GvLoudnessFactor.Position := 100;
         ZeroMemory(@keys[1], Length(keys) * sizeof(integer));
         MvEnable.ItemIndex := 0;
         MvLoudnessFactor.Position := 0;
         MvName.Text := '?Unnamed MP3 Station?';
         settings.Free;
         settings := nil;
       end;
       if Assigned(GvNoOfStations.OnChange) then
            GvNoOfStations.OnChange(GvNoOfStations);
       doUpdateIni := true;
       ev_Update(Sender);
     end;
end;

procedure TFrmEditor.ev_SelectSlot(Sender: TObject);
var
  locAllowUpdates: boolean;
  section, key: string;
begin
  locAllowUpdates := doUpdateIni;
  doUpdateIni := false;
  PrSlotOnlyProps.Visible := RvSlotCount.Value > 0;
  section := Format('Radio_%d', [RvSelectStation.ItemIndex + 1]);
  if Assigned(settings) and settings.SectionExists(section) then
     begin
       try
         if (RvSlotCount.Value > 0) then
            key := Format('SlotFileName_%d', [RvSelectSlot.ItemIndex + 1])
         else
            key := 'FileName';
         RvSlotFileName.Text := settings.ReadString(section, key, '');
         if (RvSlotCount.Value > 0) then
            key := Format('SlotOwner_%d', [RvSelectSlot.ItemIndex + 1])
         else
            key := 'Owner';
         RvSlotOwnerList.Text := settings.ReadString(section, key, '');
         if (RvSlotCount.Value > 0) then
            begin
              key := Format('SlotLoudnessFactor_%d', [RvSelectSlot.ItemIndex + 1]);
              RvSlotLoudnessFactor.Position := round(settings.ReadFloat(section, key, 0.0) * 100);
              key := Format('SlotDampeningFactor_%d', [RvSelectSlot.ItemIndex + 1]);
              RvSlotDampeningFactor.Position := round(settings.ReadFloat(section, key, 1.0) * 100);
            end
         else
            begin
              RvSlotLoudnessFactor.Position := 0;
              RvSlotDampeningFactor.Position := 100;
            end;
       except
         RvSlotFileName.Text := '';
         RvSlotOwnerList.Text := '';
         RvSlotLoudnessFactor.Position := 0;
         RvSlotDampeningFactor.Position := 100;
       end;
     end;

  if locAllowUpdates then
     doUpdateIni := true;
end;

procedure TFrmEditor.ev_SelectStation(Sender: TObject);
var
  locAllowUpdates: boolean;
  section: string;
begin
  locAllowUpdates := doUpdateIni;
  doUpdateIni := false;
  section := Format('Radio_%d', [RvSelectStation.ItemIndex + 1]);
  if Assigned(settings) and settings.SectionExists(section) then
     begin
       try
         RvSlotCount.Value := settings.ReadInteger(section, 'SlotCount', 0);
         if (RvSlotCount.Value > 0) then
            RvMasterLoudnessFactor.Position := round(settings.ReadFloat(section, 'MasterLoudnessFactor', 0.0) * 100)
         else
            RvMasterLoudnessFactor.Position := round(settings.ReadFloat(section, 'LoudnessFactor', 0.0) * 100);
         RvName.Text := settings.ReadString(section, 'RadioText', '?Unnamed Station?');
       except
         RvSlotCount.Value := 0;
         RvMasterLoudnessFactor.Position := 0;
         RvName.Text := '?Unnamed Station?';
       end;
     end
  else if Assigned(settings) then
     begin
       try
         settings.WriteInteger(section, 'SlotCount', 0);
         RvSlotCount.Value := 0;
         settings.WriteFloat(section, 'LoudnessFactor', 0.0);
         RvMasterLoudnessFactor.Position := 0;
         settings.WriteString(section, 'RadioText', '?Unnamed Station?');
         RvName.Text := '?Unnamed Station?';
       except
         RvSlotCount.Value := 0;
         RvMasterLoudnessFactor.Position := 0;
         RvName.Text := '?Unnamed Station?';
       end;
     end;
  if Assigned(RvSlotCount.OnChange) then
     RvSlotCount.OnChange(RvSlotCount);
  if locAllowUpdates then
     doUpdateIni := true;
end;

procedure TFrmEditor.ev_Update(Sender: TObject);
begin
  if PgEditorPages.Visible and (PgEditorPages.TabIndex = 1) then
     begin
       BtkvModifier1.Caption := StandardKeyToStringW(Handle, keys[1]);
       LbkvModifier2.Caption := StandardKeyToStringW(Handle, keys[2]);
       LbkvPrevStation.Caption := StandardKeyToStringW(Handle, keys[3]);
       LbkvNextStation.Caption := StandardKeyToStringW(Handle, keys[4]);
       LbkvReplayMP3.Caption := StandardKeyToStringW(Handle, keys[5]);
       LbkvSkipMP3.Caption := StandardKeyToStringW(Handle, keys[6]);
       LbkvReloadMod.Caption := StandardKeyToStringW(Handle, keys[7]);
     end;
end;

end.


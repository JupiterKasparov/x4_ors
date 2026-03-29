unit editor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, Menus,
  StdCtrls, Spin, EditBtn, ExtCtrls, PairSplitter, LCLType, LCLIntf, Buttons,
  Math, fpjson, u_filechooser, u_texteditor, u_keyeditor, u_jsonmanager,
  u_oldconvert, u_osutils;

type

  { TFrmEditor }

  TFrmEditor = class(TForm)
    RseMoveStationUp: TBitBtn;
    DlgOpenFile: TOpenDialog;
    DlgOpenFileOld: TOpenDialog;
    LbrSlotFileName: TLabel;
    LbrSlotIsMP3: TLabel;
    LbrSlotLoudnessFactor: TLabel;
    LbrSlotOrdered: TLabel;
    LbrSlotOwnerList: TLabel;
    LbrSlotRangeKm: TLabel;
    MnuHelp_ShowHelp: TMenuItem;
    MnuFile_New: TMenuItem;
    RseMoveStationDown: TBitBtn;
    RvSlotOrderList: TMemo;
    RseStationEditorSlotPropertiesPn: TGroupBox;
    LbrEnabled: TLabel;
    LbrLoudnessFactor: TLabel;
    LbrName: TLabel;
    RseAddSlot: TButton;
    RseDelSlot: TButton;
    RseStationEditorSlotManagePn: TPanel;
    RseStationEditorSlotEditor: TPairSplitter;
    RseStationEditorSlotSelectPn: TPairSplitterSide;
    RseStationEditorSlotEditPn: TPairSplitterSide;
    RseAddStation: TButton;
    RseDelStation: TButton;
    RseStationEditor: TPairSplitter;
    RseStationEditorPropertiesPn: TGroupBox;
    RseStationEditorManagePn: TPanel;
    RseStationEditorSelectPn: TPairSplitterSide;
    RseStationEditorEditPn: TPairSplitterSide;
    RseStationEditorSelect: TListBox;
    KvModifier1: TEditButton;
    GvRandomTracks: TComboBox;
    GvLinearVolume: TComboBox;
    KvModifier2: TEditButton;
    KvReloadMod: TEditButton;
    KvReplayMP3: TEditButton;
    KvPrevStation: TEditButton;
    KvNextStation: TEditButton;
    KvNextMP3: TEditButton;
    LbgLatency: TLabel;
    LbkModifier1: TLabel;
    LbgLoudnessFactor: TLabel;
    LbgRandomTracks: TLabel;
    LbgLinearVolume: TLabel;
    LbkModifier2: TLabel;
    LbkReload: TLabel;
    LbkReplayMP3: TLabel;
    LbkPrevStation: TLabel;
    LbkNextStation: TLabel;
    LbkNextMP3: TLabel;
    MnuHelp_ConvertOld: TMenuItem;
    MnuHelp_About: TMenuItem;
    MnuMain_Images: TImageList;
    MnuFile_Exit: TMenuItem;
    MnuFile_Close: TMenuItem;
    Mnu_Help: TMenuItem;
    MnuFile_Save: TMenuItem;
    MnuFile_Load: TMenuItem;
    MnuFile: TMenuItem;
    MnuMain: TMainMenu;
    PgEditorPages: TPageControl;
    PgEditGlobal: TTabSheet;
    PgEditKeys: TTabSheet;
    PgEditStations: TTabSheet;
    GvMaxLatency: TSpinEdit;
    GvLoudnessFactor: TTrackBar;
    RseStationEditorSlotSelect: TListBox;
    RvEnabled: TComboBox;
    RvLoudnessFactor: TTrackBar;
    RvName: TEdit;
    RvSlotFileName: TEditButton;
    RvSlotIsMP3: TComboBox;
    RvSlotLoudnessFactor: TTrackBar;
    RvSlotOrdered: TComboBox;
    RvSlotOwnerList: TEditButton;
    RvSlotRangeKm: TFloatSpinEdit;
    RseStationEditorSlotPropertiesPnScroll: TScrollBox;
    DlgSaveFile: TSaveDialog;
    procedure ev_gpe_LinearVolume(Sender: TObject);
    procedure ev_gpe_LoudnessFactor(Sender: TObject);
    procedure ev_gpe_MaxLatency(Sender: TObject);
    procedure ev_gpe_RandomTracks(Sender: TObject);
    procedure ev_kbe_Modifier1(Sender: TObject);
    procedure ev_kbe_Modifier2(Sender: TObject);
    procedure ev_kbe_NextMP3(Sender: TObject);
    procedure ev_kbe_NextStation(Sender: TObject);
    procedure ev_kbe_PrevStation(Sender: TObject);
    procedure ev_kbe_ReloadMod(Sender: TObject);
    procedure ev_kbe_ReplayMP3(Sender: TObject);
    procedure ev_MnuAbout(Sender: TObject);
    procedure ev_MnuClose(Sender: TObject);
    procedure ev_MnuConvertOld(Sender: TObject);
    procedure ev_MnuExit(Sender: TObject);
    procedure ev_MnuLoad(Sender: TObject);
    procedure ev_MnuNew(Sender: TObject);
    procedure ev_MnuSave(Sender: TObject);
    procedure ev_MnuShowHelp(Sender: TObject);
    procedure ev_rse_AddRadioSlot(Sender: TObject);
    procedure ev_rse_AddRadioStation(Sender: TObject);
    procedure ev_rse_DelRadioSlot(Sender: TObject);
    procedure ev_rse_DelRadioStation(Sender: TObject);
    procedure ev_rse_Enabled(Sender: TObject);
    procedure ev_rse_LoudnessFactor(Sender: TObject);
    procedure ev_rse_MoveRadioStation_Down(Sender: TObject);
    procedure ev_rse_MoveRadioStation_Up(Sender: TObject);
    procedure ev_rse_Name(Sender: TObject);
    procedure ev_rse_SelectRadioStation(Sender: TObject; User: boolean);
    procedure ev_rse_SelectRadioStationSlot(Sender: TObject; User: boolean);
    procedure ev_rse_SlotFileName(Sender: TObject);
    procedure ev_rse_SlotIsMP3(Sender: TObject);
    procedure ev_rse_SlotLoudnessFactor(Sender: TObject);
    procedure ev_rse_SlotOrdered(Sender: TObject);
    procedure ev_rse_SlotOrderList(Sender: TObject);
    procedure ev_rse_SlotOwnerList(Sender: TObject);
    procedure ev_rse_SlotRangeKm(Sender: TObject);
    procedure ev_WindowDestroy(Sender: TObject);
    procedure ev_WindowInit(Sender: TObject);
    procedure ev_WindowTryClose(Sender: TObject; var CanClose: Boolean);
  private
    bLoadingSettings, bChangingRadioStation, bChangingRadioSlot: boolean;
    settingsData: TJSONData;
  public
    procedure LoadSettings(data: TJSONData);
    procedure CloseSettings;
  end;

var
  FrmEditor: TFrmEditor;

implementation

function GetDampFactor(rangeKm: double): double;
begin
  if (rangeKm >= 1000000.0) then
     rangeKm := 1000000.0
  else if (rangeKm < 0.01) then
     rangeKm := 0.01;
  Result := power(exp(1.0), Math.logn(exp(1.0), 0.5) / rangeKm);
end;

function GetRangeKm(dampFactor: double): double;
begin
  if (dampFactor > 0.999999999) then
     dampFactor := 0.999999999
  else if (dampFactor < 0.01) then
     dampFactor := 0.01;
  Result := logn(dampFactor, 0.5);
end;

function IsNetFile(fn: string): boolean;
begin
  fn := Trim(fn);
  if (Pos('://', fn) > 0) then
     exit(true);
  exit(false);
end;

{$R *.lfm}

{ TFrmEditor }

procedure TFrmEditor.LoadSettings(data: TJSONData);
var
  arr: TJSONArray;
  i: integer;
begin
  bLoadingSettings := true;
  try
    CloseSettings;
    try
      if (data = nil) then
         begin
           Application.MessageBox('Failed to read the file!', '', MB_OK + MB_ICONERROR);
           exit;
         end;

      settingsData := data;

      // Mod properties
      GvMaxLatency.Value := min(5000, max(10, GetIntegerSetting(settingsData, 'global.maxLatency', 500)));
      if GetBooleanSetting(settingsData, 'global.randomizeTracks', true) then
         GvRandomTracks.ItemIndex := 1
      else
         GvRandomTracks.ItemIndex := 0;
      if GetBooleanSetting(settingsData, 'global.linearVolumeScale') then
         GvLinearVolume.ItemIndex := 1
      else
         GvLinearVolume.ItemIndex := 0;
      GvLoudnessFactor.Position := round(min(1.0, max(0.0, GetFloatSetting(settingsData, 'global.masterLoudness', 1.0))) * 100);

      // Key bindings
      arr := SetListSetting(settingsData, 'global.keyBindings');
      while (arr.Count < 7) do
            arr.Add(0);
      KvModifier1.Text := GetKeyName(arr[0].AsInteger);
      KvModifier2.Text := GetKeyName(arr[1].AsInteger);
      KvPrevStation.Text :=GetKeyName(arr[2].AsInteger);
      KvNextStation.Text := GetKeyName(arr[3].AsInteger);
      KvReplayMP3.Text := GetKeyName(arr[4].AsInteger);
      KvNextMP3.Text := GetKeyName(arr[5].AsInteger);
      KvReloadMod.Text := GetKeyName(arr[6].AsInteger);

      // Radio station editor
      RseStationEditorSelect.ItemIndex := -1;
      RseStationEditorSelect.Items.Clear;
      arr := SetListSetting(settingsData, 'radioStations');
      for i := 0 to arr.Count - 1 do
          RseStationEditorSelect.Items.Add(GetStringSetting(arr[i], 'name', '???'));

      // Update radio station editor
      if Assigned(RseStationEditorSelect.OnSelectionChange) then
         RseStationEditorSelect.OnSelectionChange(RseStationEditorSelect, true);

      // GUI access
      MnuFile_Save.Enabled := true;
      MnuFile_Close.Enabled := true;
      PgEditorPages.Visible := true;

      // Info (if necessary)
      if (GetStringSetting(settingsData, 'global._os_') <> JsonOperatingSystemString) then
         Application.MessageBox('Your configuration file was made for a different operating system! Please check the key bindings and file paths before using this configuration file with the mod!', '', MB_OK + MB_ICONWARNING);
    except
      CloseSettings;
      Application.MessageBox('Failed to load the file!', '', MB_OK + MB_ICONERROR);
    end;
  finally
    bLoadingSettings := false;
  end;
end;

procedure TFrmEditor.CloseSettings;
begin
  if (settingsData <> nil) then
     settingsData.Free;
  settingsData := nil;
  MnuFile_Save.Enabled := false;
  MnuFile_Close.Enabled := false;
  PgEditorPages.Visible := false;
end;

procedure TFrmEditor.ev_MnuExit(Sender: TObject);
begin
  Close;
end;

procedure TFrmEditor.ev_MnuLoad(Sender: TObject);
begin
  if not DlgOpenFile.Execute then
     exit;
  if (settingsData <> nil) and (Application.MessageBox('Are you sure you want to load another file? Any unsaved changes will be lost!', '', MB_OKCANCEL + MB_ICONQUESTION) = IDCANCEL) then
     exit;
  LoadSettings(u_jsonmanager.LoadSettings((DlgOpenFile.FileName)));
end;

procedure TFrmEditor.ev_MnuNew(Sender: TObject);
var
  newsettings: TJSONObject;
begin
  if (settingsData <> nil) and (Application.MessageBox('Are you sure you want to start from a blank template? Any unsaved changes will be lost!', '', MB_OKCANCEL + MB_ICONQUESTION) = IDCANCEL) then
     exit;
  CloseSettings;
  newsettings := TJSONObject.Create;
  SetStringSetting(newsettings, 'global._os_', JsonOperatingSystemString);
  LoadSettings(newsettings);
end;

procedure TFrmEditor.ev_MnuSave(Sender: TObject);
begin
  if not DlgSaveFile.Execute then
     exit;
  SetStringSetting(settingsData, 'global._os_', JsonOperatingSystemString);
  if not SaveSettings(settingsData, DlgSaveFile.FileName) then
     Application.MessageBox('Failed to save the file!', '', MB_OK + MB_ICONERROR);
end;

procedure TFrmEditor.ev_MnuShowHelp(Sender: TObject);
const
  helpFileName: string = 'x4 ors editor help.pdf';
begin
  if not FileExists(helpFileName) then
     Application.MessageBox('The help file couldn''t be found!', '', MB_OK + MB_ICONWARNING)
  else if not OpenDocument(helpFileName) then
     Application.MessageBox('The help file couldn''t be opened!', '', MB_OK + MB_ICONWARNING);
end;

procedure TFrmEditor.ev_rse_AddRadioSlot(Sender: TObject);
var
  arr: TJSONArray;
  rsData: TJSONData;
  rs, slot: TJSONObject;
  slotName: string;
begin
  arr := SetListSetting(settingsData, 'radioStations');
  rsData := arr[RseStationEditorSelect.ItemIndex];
  if (rsData.JSONType <> jtObject) then
     begin
       Application.MessageBox('Failed to add new track, the file may be corrupt!', '', MB_OK + MB_ICONERROR);
       exit;
     end;
  rs := TJSONObject(rsData);
  arr := SetListSetting(rs, 'slots');
  if (arr.Count >= 16)then
     begin
       Application.MessageBox('Cannot add any more tracks to this radio station!', '', MB_OK + MB_ICONINFORMATION);
       exit;
     end;
  slotName := Format('Track %d', [arr.Count + 1]);
  slot := TJSONObject.Create;
  arr.Add(slot);
  RseStationEditorSlotSelect.Items.Add(slotName);

  // Update slot editor
  RseStationEditorSlotSelect.ItemIndex := RseStationEditorSlotSelect.Items.Count - 1;
  if Assigned(RseStationEditorSlotSelect.OnSelectionChange) then
     RseStationEditorSlotSelect.OnSelectionChange(RseStationEditorSlotSelect, true);
end;

procedure TFrmEditor.ev_rse_AddRadioStation(Sender: TObject);
var
  arr: TJSONArray;
  rs: TJSONObject;
  rsName: string;
begin
  arr := SetListSetting(settingsData, 'radioStations');
  if (arr.Count >= 32)then
     begin
       Application.MessageBox('Cannot add any more radio stations!', '', MB_OK + MB_ICONINFORMATION);
       exit;
     end;
  rsName := Format('Radio Station %d', [arr.Count + 1]);
  rs := TJSONObject.Create;
  rs.Strings['name'] := rsName;
  arr.Add(rs);
  RseStationEditorSelect.Items.Add(rsName);

  // Update radio station editor
  RseStationEditorSelect.ItemIndex := RseStationEditorSelect.Items.Count - 1;
  if Assigned(RseStationEditorSelect.OnSelectionChange) then
     RseStationEditorSelect.OnSelectionChange(RseStationEditorSelect, true);
end;

procedure TFrmEditor.ev_rse_DelRadioSlot(Sender: TObject);
var
  arr: TJSONArray;
  rsData: TJSONData;
  rs: TJSONObject;
begin
  arr := GetListSetting(settingsData, 'radioStations');
  rsData := arr[RseStationEditorSelect.ItemIndex];
  if (rsData.JSONType <> jtObject) then
     begin
       Application.MessageBox('Failed to remove track, the file may be corrupt!', 'Add radio slot', MB_OK + MB_ICONERROR);
       exit;
     end;
  rs := TJSONObject(rsData);
  arr := SetListSetting(rs, 'slots');
  arr.Delete(RseStationEditorSlotSelect.ItemIndex);
  RseStationEditorSlotSelect.Items.Delete(RseStationEditorSlotSelect.ItemIndex);

  // Update slot editor
  RseStationEditorSlotSelect.ItemIndex := -1;
  if Assigned(RseStationEditorSlotSelect.OnSelectionChange) then
     RseStationEditorSlotSelect.OnSelectionChange(RseStationEditorSlotSelect, true);
end;

procedure TFrmEditor.ev_rse_DelRadioStation(Sender: TObject);
var
  arr: TJSONArray;
begin
  arr := GetListSetting(settingsData, 'radioStations');
  arr.Delete(RseStationEditorSelect.ItemIndex);
  RseStationEditorSelect.Items.Delete(RseStationEditorSelect.ItemIndex);

  // Update radio station editor
  RseStationEditorSelect.ItemIndex := -1;
  if Assigned(RseStationEditorSelect.OnSelectionChange) then
     RseStationEditorSelect.OnSelectionChange(RseStationEditorSelect, true);
end;

procedure TFrmEditor.ev_rse_Enabled(Sender: TObject);
var
  arr: TJSONArray;
begin
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  arr := SetListSetting(settingsData, 'radioStations', RseStationEditorSelect.Items.Count);
  TJSONObject(arr[RseStationEditorSelect.ItemIndex]).Booleans['enabled'] := RvEnabled.ItemIndex <> 0;
end;

procedure TFrmEditor.ev_rse_LoudnessFactor(Sender: TObject);
var
  arr: TJSONArray;
begin
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  arr := SetListSetting(settingsData, 'radioStations', RseStationEditorSelect.Items.Count);
  TJSONObject(arr[RseStationEditorSelect.ItemIndex]).Floats['masterLoudness'] := RvLoudnessFactor.Position / 100.0;
end;

procedure TFrmEditor.ev_rse_MoveRadioStation_Down(Sender: TObject);
var
  index, slotindex: integer;
  arr: TJSONArray;
begin
  index := RseStationEditorSelect.ItemIndex;
  if (index < (RseStationEditorSelect.Items.Count - 1)) then
     begin
       arr := SetListSetting(settingsData, 'radioStations');
       arr.Exchange(index, index + 1);
       RseStationEditorSelect.Items.Exchange(index, index + 1);

       // Update radio station editor
       slotindex := RseStationEditorSlotSelect.ItemIndex;
       RseStationEditorSelect.ItemIndex := index + 1;
       if Assigned(RseStationEditorSelect.OnSelectionChange) then
          RseStationEditorSelect.OnSelectionChange(RseStationEditorSelect, true);
       if (slotindex >= 0) then
          begin
            RseStationEditorSlotSelect.ItemIndex := slotindex;
            if Assigned(RseStationEditorSlotSelect.OnSelectionChange) then
               RseStationEditorSlotSelect.OnSelectionChange(RseStationEditorSlotSelect, true);
          end;
     end;
end;

procedure TFrmEditor.ev_rse_MoveRadioStation_Up(Sender: TObject);
var
  index, slotindex: integer;
  arr: TJSONArray;
begin
  index := RseStationEditorSelect.ItemIndex;
  if (index > 0) then
     begin
       arr := SetListSetting(settingsData, 'radioStations');
       arr.Exchange(index, index - 1);
       RseStationEditorSelect.Items.Exchange(index, index - 1);

       // Update radio station editor
       slotindex := RseStationEditorSlotSelect.ItemIndex;
       RseStationEditorSelect.ItemIndex := index - 1;
       if Assigned(RseStationEditorSelect.OnSelectionChange) then
          RseStationEditorSelect.OnSelectionChange(RseStationEditorSelect, true);
       if (slotindex >= 0) then
          begin
            RseStationEditorSlotSelect.ItemIndex := slotindex;
            if Assigned(RseStationEditorSlotSelect.OnSelectionChange) then
               RseStationEditorSlotSelect.OnSelectionChange(RseStationEditorSlotSelect, true);
          end;
     end;
end;

procedure TFrmEditor.ev_rse_Name(Sender: TObject);
var
  arr: TJSONArray;
  nameText: string;
begin
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  nameText := Trim(RvName.Text);
  if (nameText = '') then
     nameText := '???';
  arr := SetListSetting(settingsData, 'radioStations', RseStationEditorSelect.Items.Count);
  TJSONObject(arr[RseStationEditorSelect.ItemIndex]).Strings['name'] := nameText;
  RseStationEditorSelect.Items[RseStationEditorSelect.ItemIndex] := nameText;
end;

procedure TFrmEditor.ev_rse_SelectRadioStation(Sender: TObject; User: boolean);
var
  arr: TJSONArray;
  rs: TJSONObject;
  i: integer;
begin
  bChangingRadioStation := true;
  try
    // Radio station editor
    RseStationEditorPropertiesPn.Visible := (RseStationEditorSelect.ItemIndex >= 0) and (RseStationEditorSelect.Items.Count >= (RseStationEditorSelect.ItemIndex + 1));
    RseDelStation.Enabled := RseStationEditorPropertiesPn.Visible;
    RseMoveStationUp.Enabled := RseStationEditorPropertiesPn.Visible and (RseStationEditorSelect.Items.Count > 1) and (RseStationEditorSelect.ItemIndex > 0);
    RseMoveStationDown.Enabled := RseStationEditorPropertiesPn.Visible and (RseStationEditorSelect.Items.Count > 1) and (RseStationEditorSelect.ItemIndex < (RseStationEditorSelect.Items.Count - 1));
    if (RseStationEditorPropertiesPn.Visible) then
       begin
         arr := SetListSetting(settingsData, 'radioStations', RseStationEditorSelect.Items.Count);
         rs := TJSONObject(arr[RseStationEditorSelect.ItemIndex]);
         if (rs.JSONType <> jtObject) then
            begin
              Application.MessageBox('Failed to select radio station, the file may be corrupt!', '', MB_OK + MB_ICONERROR);
              exit;
            end;
         RvLoudnessFactor.Position := round(min(1.0, max(0.0, GetFloatSetting(rs, 'masterLoudness', 1.0))) * 100);
         RvName.Text := GetStringSetting(rs, 'name');
         if GetBooleanSetting(rs, 'enabled', true) then
            RvEnabled.ItemIndex := 1
         else
            RvEnabled.ItemIndex := 0;

         // Slot editor
         RseStationEditorSlotSelect.ItemIndex := -1;
         RseStationEditorSlotSelect.Items.Clear;
         arr := GetListSetting(rs, 'slots');
         if (arr <> nil) then
            for i := 0 to arr.Count - 1 do
                RseStationEditorSlotSelect.Items.Add('Track %d', [i + 1]);
       end;

    // Update slot editor
    if Assigned(RseStationEditorSlotSelect.OnSelectionChange) then
       RseStationEditorSlotSelect.OnSelectionChange(RseStationEditorSlotSelect, true);
  finally
    bChangingRadioStation := false;
  end;
end;

procedure TFrmEditor.ev_rse_SelectRadioStationSlot(Sender: TObject; User: boolean);
var
  arr: TJSONArray;
  rs, slot: TJSONObject;
  i: integer;
begin
  bChangingRadioSlot := true;
  try
    // Slot editor
    RseStationEditorSlotPropertiesPn.Visible := RseStationEditorPropertiesPn.Visible and (RseStationEditorSlotSelect.ItemIndex >= 0) and (RseStationEditorSlotSelect.Items.Count >= (RseStationEditorSlotSelect.ItemIndex + 1));
    RseDelSlot.Enabled := RseStationEditorSlotPropertiesPn.Visible;
    if RseStationEditorSlotPropertiesPn.Visible then
       begin
         arr := SetListSetting(settingsData, 'radioStations', RseStationEditorSelect.Items.Count);
         rs := TJSONObject(arr[RseStationEditorSelect.ItemIndex]);
         if (rs.JSONType <> jtObject) then
            begin
              Application.MessageBox('Failed to select track, the file may be corrupt!', '', MB_OK + MB_ICONERROR);
              exit;
            end;
         arr := SetListSetting(rs, 'slots');
         slot := TJSONObject(arr[RseStationEditorSlotSelect.ItemIndex]);
         RvSlotLoudnessFactor.Position := round(GetFloatSetting(slot, 'loudness') * 100);
         RvSlotRangeKm.Value := GetRangeKm(GetFloatSetting(slot, 'dampFactor', 0.0));
         RvSlotOwnerList.Text := GetStringSetting(slot, 'owners');
         if GetBooleanSetting(slot, 'isMP3Player') then
            begin
              if GetBooleanSetting(slot, 'disableUserInteraction') then
                 RvSlotIsMP3.ItemIndex := 2
              else
                 RvSlotIsMP3.ItemIndex := 1;
            end
         else
            RvSlotIsMP3.ItemIndex := 0;
         if Assigned(RvSlotIsMP3.OnChange) then
            RvSlotIsMP3.OnChange(RvSlotIsMP3);
         RvSlotFileName.Text := GetStringSetting(slot, 'url');
         if GetBooleanSetting(slot, 'isOrdered') then
            RvSlotOrdered.ItemIndex := 1
         else
            RvSlotOrdered.ItemIndex := 0;
         if Assigned(RvSlotOrdered.OnChange) then
            RvSlotOrdered.OnChange(RvSlotOrdered);
         RvSlotOrderList.Lines.Clear;
         arr := GetListSetting(slot, 'orderByList');
         if (arr <> nil) then
            for i := 0 to arr.Count - 1 do
                RvSlotOrderList.Lines.Add(GetStringSetting(arr[i], ''));
       end;
  finally
    bChangingRadioSlot := false;
  end;
end;

procedure TFrmEditor.ev_rse_SlotFileName(Sender: TObject);
var
  arr: TJSONArray;
  rs, slot: TJSONObject;
  url: string;
begin
  arr := SetListSetting(settingsData, 'radioStations');
  rs := TJSONObject(arr[RseStationEditorSelect.ItemIndex]);
  arr := GetListSetting(rs, 'slots');
  slot := TJSONObject(arr[RseStationEditorSlotSelect.ItemIndex]);
  url := GetStringSetting(slot, 'url');
  if (RvSlotIsMP3.ItemIndex = 0) then
     begin
       if IsNetFile(url) then
          FrmFileChooser.LocationType := ffcltURL
       else
          FrmFileChooser.LocationType := ffcltFile;
     end
  else
     FrmFileChooser.LocationType := ffcltDirectory;
  FrmFileChooser.FileName := url;
  if (FrmFileChooser.ShowModal = mrOK) then
     begin
       slot.Strings['url'] := FrmFileChooser.FileName;
       RvSlotFileName.Text := FrmFileChooser.FileName;
     end;
end;

procedure TFrmEditor.ev_rse_SlotIsMP3(Sender: TObject);
var
  arr: TJSONArray;
  rs, slot: TJSONObject;
begin
  // UI update first
  RvSlotOrdered.Enabled := RvSlotIsMP3.ItemIndex <> 0;
  if Assigned(RvSlotOrdered.OnChange) then
     RvSlotOrdered.OnChange(RvSlotOrdered);

  // Property update
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  arr := SetListSetting(settingsData, 'radioStations');
  rs := TJSONObject(arr[RseStationEditorSelect.ItemIndex]);
  arr := GetListSetting(rs, 'slots');
  slot := TJSONObject(arr[RseStationEditorSlotSelect.ItemIndex]);
  slot.Booleans['isMP3Player'] := RvSlotIsMP3.ItemIndex <> 0;
  slot.Booleans['disableUserInteraction'] := RvSlotIsMP3.ItemIndex = 2;
end;

procedure TFrmEditor.ev_rse_SlotLoudnessFactor(Sender: TObject);
var
  arr: TJSONArray;
  rs, slot: TJSONObject;
begin
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  arr := SetListSetting(settingsData, 'radioStations');
  rs := TJSONObject(arr[RseStationEditorSelect.ItemIndex]);
  arr := GetListSetting(rs, 'slots');
  slot := TJSONObject(arr[RseStationEditorSlotSelect.ItemIndex]);
  slot.Floats['loudness'] := RvSlotLoudnessFactor.Position / 100.0;
end;

procedure TFrmEditor.ev_rse_SlotOrdered(Sender: TObject);
var
  arr: TJSONArray;
  rs, slot: TJSONObject;
begin
  // UI update first
  RvSlotOrderList.Enabled := RvSlotOrdered.Enabled and (RvSlotOrdered.ItemIndex <> 0);

  // Property update
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  arr := SetListSetting(settingsData, 'radioStations');
  rs := TJSONObject(arr[RseStationEditorSelect.ItemIndex]);
  arr := GetListSetting(rs, 'slots');
  slot := TJSONObject(arr[RseStationEditorSlotSelect.ItemIndex]);
  slot.Booleans['isOrdered'] := RvSlotOrdered.ItemIndex <> 0;
end;

procedure TFrmEditor.ev_rse_SlotOrderList(Sender: TObject);
var
  arr: TJSONArray;
  rs, slot: TJSONObject;
  i: integer;
begin
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  arr := SetListSetting(settingsData, 'radioStations');
  rs := TJSONObject(arr[RseStationEditorSelect.ItemIndex]);
  arr := GetListSetting(rs, 'slots');
  slot := TJSONObject(arr[RseStationEditorSlotSelect.ItemIndex]);
  arr := TJSONArray.Create;
  slot.Arrays['orderByList'] := arr;
  for i := 0 to RvSlotOrderList.Lines.Count - 1 do
      arr.Add(RvSlotOrderList.Lines[i]);
end;

procedure TFrmEditor.ev_rse_SlotOwnerList(Sender: TObject);
var
  arr: TJSONArray;
  rs, slot: TJSONObject;
begin
  arr := SetListSetting(settingsData, 'radioStations');
  rs := TJSONObject(arr[RseStationEditorSelect.ItemIndex]);
  arr := GetListSetting(rs, 'slots');
  slot := TJSONObject(arr[RseStationEditorSlotSelect.ItemIndex]);
  FrmStringEditor.EditText := GetStringSetting(slot, 'owners');
  if (FrmStringEditor.ShowModal = mrOK) then
     begin
       slot.Strings['owners'] := FrmStringEditor.EditText;
       RvSlotOwnerList.Text := FrmStringEditor.EditText;
     end;
end;

procedure TFrmEditor.ev_rse_SlotRangeKm(Sender: TObject);
var
  arr: TJSONArray;
  rs, slot: TJSONObject;
begin
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  arr := SetListSetting(settingsData, 'radioStations');
  rs := TJSONObject(arr[RseStationEditorSelect.ItemIndex]);
  arr := GetListSetting(rs, 'slots');
  slot := TJSONObject(arr[RseStationEditorSlotSelect.ItemIndex]);
  slot.Floats['dampFactor'] := GetDampFactor(RvSlotRangeKm.Value);
end;

procedure TFrmEditor.ev_MnuClose(Sender: TObject);
begin
  if (settingsData <> nil) and (Application.MessageBox('Are you sure you want to close your current session? Any unsaved changes will be lost!', '', MB_OKCANCEL + MB_ICONQUESTION) = IDCANCEL) then
     exit;
  CloseSettings;
end;

procedure TFrmEditor.ev_MnuConvertOld(Sender: TObject);
begin
  Application.MessageBox('This utility allows you to load your old X4 ORS configuration into this application. You can then save the configuration in the new file format.',  '', MB_OK + MB_ICONINFORMATION);
  if not DlgOpenFileOld.Execute then
     exit;
  if (settingsData <> nil) and (Application.MessageBox('Are you sure you want to load another file? Any unsaved changes will be lost!', '', MB_OKCANCEL + MB_ICONQUESTION) = IDCANCEL) then
     exit;
  LoadSettings(ConvertOldSettings(DlgOpenFileOld.FileName));
end;

procedure TFrmEditor.ev_MnuAbout(Sender: TObject);
begin
  Application.MessageBox('This application allows you to edit the X4 ORS configuration file, without requiring manual editions, or knowledge about the file format itself.', '', MB_OK + MB_ICONINFORMATION);
end;

procedure TFrmEditor.ev_gpe_MaxLatency(Sender: TObject);
begin
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  SetIntegerSetting(settingsData, 'global.maxLatency', GvMaxLatency.Value);
end;

procedure TFrmEditor.ev_gpe_LinearVolume(Sender: TObject);
begin
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  SetBooleanSetting(settingsData, 'global.linearVolumeScale', GvLinearVolume.ItemIndex <> 0);
end;

procedure TFrmEditor.ev_gpe_LoudnessFactor(Sender: TObject);
begin
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  SetFloatSetting(settingsData, 'global.masterLoudness', GvLoudnessFactor.Position / 100.0);
end;

procedure TFrmEditor.ev_gpe_RandomTracks(Sender: TObject);
begin
  if bLoadingSettings or bChangingRadioStation or bChangingRadioSlot then
     exit;
  SetBooleanSetting(settingsData, 'global.randomizeTracks', GvRandomTracks.ItemIndex <> 0);
end;

procedure TFrmEditor.ev_kbe_Modifier1(Sender: TObject);
var
  arr: TJSONArray;
begin
  arr := GetListSetting(settingsData, 'global.keyBindings');
  if (arr <> nil) and (arr.Count >= 1) then
     FrmKeyEditor.KeyCode := GetIntegerSetting(arr[0], '')
  else
     FrmKeyEditor.KeyCode := 0;
  if (FrmKeyEditor.ShowModal = mrOK) then
     begin
       arr := SetListSetting(settingsData, 'global.keyBindings', 1);
       arr.Integers[0] := FrmKeyEditor.KeyCode;
       KvModifier1.Text := GetKeyName(FrmKeyEditor.KeyCode);
     end;
end;

procedure TFrmEditor.ev_kbe_Modifier2(Sender: TObject);
var
  arr: TJSONArray;
begin
  arr := GetListSetting(settingsData, 'global.keyBindings');
  if (arr <> nil) and (arr.Count >= 2) then
     FrmKeyEditor.KeyCode := GetIntegerSetting(arr[1], '')
  else
     FrmKeyEditor.KeyCode := 0;
  if (FrmKeyEditor.ShowModal = mrOK) then
     begin
       arr := SetListSetting(settingsData, 'global.keyBindings', 2);
       arr.Integers[1] := FrmKeyEditor.KeyCode;
       KvModifier2.Text := GetKeyName(FrmKeyEditor.KeyCode);
     end;
end;

procedure TFrmEditor.ev_kbe_NextMP3(Sender: TObject);
var
  arr: TJSONArray;
begin
  arr := GetListSetting(settingsData, 'global.keyBindings');
  if (arr <> nil) and (arr.Count >= 6) then
     FrmKeyEditor.KeyCode := GetIntegerSetting(arr[5], '')
  else
     FrmKeyEditor.KeyCode := 0;
  if (FrmKeyEditor.ShowModal = mrOK) then
     begin
       arr := SetListSetting(settingsData, 'global.keyBindings', 6);
       arr.Integers[5] := FrmKeyEditor.KeyCode;
       KvNextMP3.Text := GetKeyName(FrmKeyEditor.KeyCode);
     end;
end;

procedure TFrmEditor.ev_kbe_NextStation(Sender: TObject);
var
  arr: TJSONArray;
begin
  arr := GetListSetting(settingsData, 'global.keyBindings');
  if (arr <> nil) and (arr.Count >= 4) then
     FrmKeyEditor.KeyCode := GetIntegerSetting(arr[3], '')
  else
     FrmKeyEditor.KeyCode := 0;
  if (FrmKeyEditor.ShowModal = mrOK) then
     begin
       arr := SetListSetting(settingsData, 'global.keyBindings', 4);
       arr.Integers[3] := FrmKeyEditor.KeyCode;
       KvNextStation.Text := GetKeyName(FrmKeyEditor.KeyCode);
     end;
end;

procedure TFrmEditor.ev_kbe_PrevStation(Sender: TObject);
var
  arr: TJSONArray;
begin
  arr := GetListSetting(settingsData, 'global.keyBindings');
  if (arr <> nil) and (arr.Count >= 3) then
     FrmKeyEditor.KeyCode := GetIntegerSetting(arr[2], '')
  else
     FrmKeyEditor.KeyCode := 0;
  if (FrmKeyEditor.ShowModal = mrOK) then
     begin
       arr := SetListSetting(settingsData, 'global.keyBindings', 3);
       arr.Integers[2] := FrmKeyEditor.KeyCode;
       KvPrevStation.Text := GetKeyName(FrmKeyEditor.KeyCode);
     end;
end;

procedure TFrmEditor.ev_kbe_ReloadMod(Sender: TObject);
var
  arr: TJSONArray;
begin
  arr := GetListSetting(settingsData, 'global.keyBindings');
  if (arr <> nil) and (arr.Count >= 7) then
     FrmKeyEditor.KeyCode := GetIntegerSetting(arr[6], '')
  else
     FrmKeyEditor.KeyCode := 0;
  if (FrmKeyEditor.ShowModal = mrOK) then
     begin
       arr := SetListSetting(settingsData, 'global.keyBindings', 7);
       arr.Integers[6] := FrmKeyEditor.KeyCode;
       KvReloadMod.Text := GetKeyName(FrmKeyEditor.KeyCode);
     end;
end;

procedure TFrmEditor.ev_kbe_ReplayMP3(Sender: TObject);
var
  arr: TJSONArray;
begin
  arr := GetListSetting(settingsData, 'global.keyBindings');
  if (arr <> nil) and (arr.Count >= 5) then
     FrmKeyEditor.KeyCode := GetIntegerSetting(arr[4], '')
  else
     FrmKeyEditor.KeyCode := 0;
  if (FrmKeyEditor.ShowModal = mrOK) then
     begin
       arr := SetListSetting(settingsData, 'global.keyBindings', 5);
       arr.Integers[4] := FrmKeyEditor.KeyCode;
       KvReplayMP3.Text := GetKeyName(FrmKeyEditor.KeyCode);
     end;
end;

procedure TFrmEditor.ev_WindowDestroy(Sender: TObject);
begin
  CloseSettings;
end;

procedure TFrmEditor.ev_WindowInit(Sender: TObject);
begin
  bLoadingSettings := false;
  bChangingRadioStation := false;
  bChangingRadioSlot := false;
  settingsData := nil;
  CloseSettings;
  DlgOpenFile.InitialDir := GetUserDir;
  DlgSaveFile.InitialDir := GetUserDir;
  UpdateForm(self);
end;

procedure TFrmEditor.ev_WindowTryClose(Sender: TObject; var CanClose: Boolean);
begin
  if (settingsData <> nil) then
     CanClose := Application.MessageBox('Are you sure you want to quit? Any unsaved changes will be lost!', '', MB_OKCANCEL + MB_ICONQUESTION) = IDOK;
end;

end.


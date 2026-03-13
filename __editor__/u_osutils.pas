unit u_osutils;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, StdCtrls, ComCtrls;

const
  JsonOperatingSystemString = {$IFDEF MSWINDOWS}'_is_windows_'{$ELSE}'_is_linux_'{$ENDIF};

procedure UpdateForm(frm: TForm);

implementation

procedure UpdateForm(frm: TForm);
{$IFDEF MSWINDOWS}
begin;
end;
{$ELSE}
var
  i: integer;
  comp: TComponent;
begin
  frm.Font.Size := 8;
  for i := 0 to frm.ComponentCount - 1 do
      begin
        comp := frm.Components[i];
        if (comp is TComboBox) then
           TComboBox(comp).Height := 24
        else if (comp is TTrackBar) then
           begin
             TTrackBar(comp).Constraints.MaxHeight := 24;
             TTrackBar(comp).TickStyle := tsNone;
           end;
      end;
end;
{$ENDIF}

end.


unit NES.Controller;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  NES.Types;

type
  TNESButton = (nbA, nbB, nbSelect, nbStart, nbUp, nbDown, nbLeft, nbRight);

  TController = class
  private
    FState: UInt8;
    FShift: UInt8;
    FStrobe: Boolean;
  public
    procedure SetButton(Button: TNESButton; Pressed: Boolean);
    procedure Write(Value: UInt8);
    function Read: UInt8;
  end;

implementation

procedure TController.SetButton(Button: TNESButton; Pressed: Boolean);
const
  MASKS: array[TNESButton] of UInt8 = ($01, $02, $04, $08, $10, $20, $40, $80);
begin
  if Pressed then
    FState := FState or MASKS[Button]
  else
    FState := FState and not MASKS[Button];

  if FStrobe then
    FShift := FState;
end;

procedure TController.Write(Value: UInt8);
var
  NewStrobe: Boolean;
begin
  NewStrobe := (Value and 1) <> 0;
  if FStrobe and not NewStrobe then
    FShift := FState;
  FStrobe := NewStrobe;
  if FStrobe then
    FShift := FState;
end;

function TController.Read: UInt8;
begin
  if FStrobe then
    Exit(FState and 1);
  Result := FShift and 1;
  FShift := (FShift shr 1) or $80;
end;

end.

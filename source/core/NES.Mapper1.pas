unit NES.Mapper1;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  NES.Types,
  NES.Mapper;

type
  TMapper001 = class(TMapper)
  private
    FPrg: TByteArray;
    FChr: TByteArray;
    FPrgRam: array[0..$1FFF] of UInt8;
    FChrRam: Boolean;
    FBoardMirrorMode: TMirrorMode;
    FShiftRegister: UInt8;
    FWriteCount: Integer;
    FControl: UInt8;
    FChrBank0: UInt8;
    FChrBank1: UInt8;
    FPrgBank: UInt8;
    function GetPrgBankCount: Integer;
    function GetChrBankCount4K: Integer;
    function MapPrgBank(Bank: Integer): Integer;
    function MapChrBank4K(Bank: Integer): Integer;
  public
    constructor Create(const APrg, AChr: TByteArray; AChrRam: Boolean; AMirrorMode: TMirrorMode);
    function CpuRead(Address: UInt16; out Value: UInt8): Boolean; override;
    function CpuWrite(Address: UInt16; Value: UInt8): Boolean; override;
    function PpuRead(Address: UInt16; out Value: UInt8): Boolean; override;
    function PpuWrite(Address: UInt16; Value: UInt8): Boolean; override;
    function GetMirrorMode: TMirrorMode; override;
    procedure Reset; override;
  end;

implementation

constructor TMapper001.Create(const APrg, AChr: TByteArray; AChrRam: Boolean; AMirrorMode: TMirrorMode);
begin
  inherited Create;
  FPrg := Copy(APrg);
  FChr := Copy(AChr);
  FChrRam := AChrRam;
  FBoardMirrorMode := AMirrorMode;
  if Length(FChr) = 0 then
    SetLength(FChr, $2000);
  Reset;
end;

function TMapper001.GetPrgBankCount: Integer;
begin
  Result := Length(FPrg) div $4000;
  if Result <= 0 then
    Result := 1;
end;

function TMapper001.GetChrBankCount4K: Integer;
begin
  Result := Length(FChr) div $1000;
  if Result <= 0 then
    Result := 1;
end;

function TMapper001.MapPrgBank(Bank: Integer): Integer;
begin
  Result := Bank mod GetPrgBankCount;
  if Result < 0 then
    Inc(Result, GetPrgBankCount);
end;

function TMapper001.MapChrBank4K(Bank: Integer): Integer;
begin
  Result := Bank mod GetChrBankCount4K;
  if Result < 0 then
    Inc(Result, GetChrBankCount4K);
end;

function TMapper001.CpuRead(Address: UInt16; out Value: UInt8): Boolean;
var
  PrgMode: Integer;
  Bank16K: Integer;
  Offset: Integer;
begin
  if (Address >= $6000) and (Address < $8000) then
  begin
    Value := FPrgRam[Address and $1FFF];
    Exit(True);
  end;

  Result := Address >= $8000;
  if not Result then
    Exit;

  PrgMode := (FControl shr 2) and 3;
  case PrgMode of
    0, 1:
      begin
        Bank16K := MapPrgBank((FPrgBank and $0E) + ((Address - $8000) div $4000));
        Offset := Bank16K * $4000 + ((Address - $8000) and $3FFF);
      end;
    2:
      begin
        if Address < $C000 then
          Bank16K := 0
        else
          Bank16K := MapPrgBank(FPrgBank and $0F);
        Offset := Bank16K * $4000 + (Address and $3FFF);
      end;
  else
    begin
      if Address < $C000 then
        Bank16K := MapPrgBank(FPrgBank and $0F)
      else
        Bank16K := GetPrgBankCount - 1;
      Offset := Bank16K * $4000 + (Address and $3FFF);
    end;
  end;

  Value := FPrg[Offset mod Length(FPrg)];
end;

function TMapper001.CpuWrite(Address: UInt16; Value: UInt8): Boolean;
var
  RegisterValue: UInt8;
begin
  if (Address >= $6000) and (Address < $8000) then
  begin
    FPrgRam[Address and $1FFF] := Value;
    Exit(True);
  end;

  Result := Address >= $8000;
  if not Result then
    Exit;

  if (Value and $80) <> 0 then
  begin
    FShiftRegister := $10;
    FWriteCount := 0;
    FControl := FControl or $0C;
    Exit;
  end;

  FShiftRegister := (FShiftRegister shr 1) or ((Value and 1) shl 4);
  Inc(FWriteCount);
  if FWriteCount < 5 then
    Exit;

  RegisterValue := FShiftRegister and $1F;
  case (Address shr 13) and 3 of
    0: FControl := RegisterValue;
    1: FChrBank0 := RegisterValue;
    2: FChrBank1 := RegisterValue;
    3: FPrgBank := RegisterValue;
  end;

  FShiftRegister := $10;
  FWriteCount := 0;
end;

function TMapper001.PpuRead(Address: UInt16; out Value: UInt8): Boolean;
var
  ChrMode: Integer;
  Bank4K: Integer;
  Offset: Integer;
begin
  Result := Address < $2000;
  if not Result then
    Exit;

  ChrMode := (FControl shr 4) and 1;
  if ChrMode = 0 then
  begin
    Bank4K := MapChrBank4K((FChrBank0 and $1E) + (Address div $1000));
    Offset := Bank4K * $1000 + (Address and $0FFF);
  end
  else
  begin
    if Address < $1000 then
      Bank4K := MapChrBank4K(FChrBank0)
    else
      Bank4K := MapChrBank4K(FChrBank1);
    Offset := Bank4K * $1000 + (Address and $0FFF);
  end;

  Value := FChr[Offset mod Length(FChr)];
end;

function TMapper001.PpuWrite(Address: UInt16; Value: UInt8): Boolean;
var
  ChrMode: Integer;
  Bank4K: Integer;
  Offset: Integer;
begin
  Result := (Address < $2000) and FChrRam;
  if not Result then
    Exit;

  ChrMode := (FControl shr 4) and 1;
  if ChrMode = 0 then
  begin
    Bank4K := MapChrBank4K((FChrBank0 and $1E) + (Address div $1000));
    Offset := Bank4K * $1000 + (Address and $0FFF);
  end
  else
  begin
    if Address < $1000 then
      Bank4K := MapChrBank4K(FChrBank0)
    else
      Bank4K := MapChrBank4K(FChrBank1);
    Offset := Bank4K * $1000 + (Address and $0FFF);
  end;

  FChr[Offset mod Length(FChr)] := Value;
end;

function TMapper001.GetMirrorMode: TMirrorMode;
begin
  if FBoardMirrorMode = mmFourScreen then
    Exit(mmFourScreen);

  case FControl and 3 of
    0: Result := mmSingle0;
    1: Result := mmSingle1;
    2: Result := mmVertical;
  else
    Result := mmHorizontal;
  end;
end;

procedure TMapper001.Reset;
var
  I: Integer;
begin
  for I := Low(FPrgRam) to High(FPrgRam) do
    FPrgRam[I] := 0;
  FShiftRegister := $10;
  FWriteCount := 0;
  FControl := $0C;
  FChrBank0 := 0;
  FChrBank1 := 0;
  FPrgBank := 0;
end;

end.

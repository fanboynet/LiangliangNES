unit NES.Mapper2;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  NES.Types,
  NES.Mapper;

type
  TMapper002 = class(TMapper)
  private
    FPrg: TByteArray;
    FChr: TByteArray;
    FPrgRam: array[0..$1FFF] of UInt8;
    FChrRam: Boolean;
    FMirrorMode: TMirrorMode;
    FBankSelect: UInt8;
    function GetPrgBankCount: Integer;
    function NormalizeBank(Bank: Integer): Integer;
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

constructor TMapper002.Create(const APrg, AChr: TByteArray; AChrRam: Boolean; AMirrorMode: TMirrorMode);
begin
  inherited Create;
  FPrg := Copy(APrg);
  FChr := Copy(AChr);
  FChrRam := AChrRam;
  FMirrorMode := AMirrorMode;
  if Length(FChr) = 0 then
    SetLength(FChr, $2000);
  Reset;
end;

function TMapper002.GetPrgBankCount: Integer;
begin
  Result := Length(FPrg) div $4000;
  if Result <= 0 then
    Result := 1;
end;

function TMapper002.NormalizeBank(Bank: Integer): Integer;
begin
  Result := Bank mod GetPrgBankCount;
  if Result < 0 then
    Inc(Result, GetPrgBankCount);
end;

function TMapper002.CpuRead(Address: UInt16; out Value: UInt8): Boolean;
var
  Bank: Integer;
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

  if Address < $C000 then
    Bank := NormalizeBank(FBankSelect)
  else
    Bank := GetPrgBankCount - 1;

  Offset := Bank * $4000 + (Address and $3FFF);
  Value := FPrg[Offset mod Length(FPrg)];
end;

function TMapper002.CpuWrite(Address: UInt16; Value: UInt8): Boolean;
begin
  if (Address >= $6000) and (Address < $8000) then
  begin
    FPrgRam[Address and $1FFF] := Value;
    Exit(True);
  end;

  Result := Address >= $8000;
  if Result then
    FBankSelect := Value and $0F;
end;

function TMapper002.PpuRead(Address: UInt16; out Value: UInt8): Boolean;
begin
  Result := Address < $2000;
  if Result then
    Value := FChr[Address and $1FFF];
end;

function TMapper002.PpuWrite(Address: UInt16; Value: UInt8): Boolean;
begin
  Result := (Address < $2000) and FChrRam;
  if Result then
    FChr[Address and $1FFF] := Value;
end;

function TMapper002.GetMirrorMode: TMirrorMode;
begin
  Result := FMirrorMode;
end;

procedure TMapper002.Reset;
var
  I: Integer;
begin
  for I := Low(FPrgRam) to High(FPrgRam) do
    FPrgRam[I] := 0;
  FBankSelect := 0;
end;

end.

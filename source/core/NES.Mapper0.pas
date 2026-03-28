unit NES.Mapper0;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  NES.Types,
  NES.Mapper;

type
  TMapper000 = class(TMapper)
  private
    FPrg: TByteArray;
    FChr: TByteArray;
    FPrgRam: array[0..$1FFF] of UInt8;
    FChrRam: Boolean;
    FMirrorMode: TMirrorMode;
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

constructor TMapper000.Create(const APrg, AChr: TByteArray; AChrRam: Boolean; AMirrorMode: TMirrorMode);
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

function TMapper000.CpuRead(Address: UInt16; out Value: UInt8): Boolean;
var
  Offset: UInt16;
begin
  if (Address >= $6000) and (Address < $8000) then
  begin
    Value := FPrgRam[Address and $1FFF];
    Exit(True);
  end;

  Result := Address >= $8000;
  if not Result then
    Exit;

  Offset := Address - $8000;
  if Length(FPrg) = $4000 then
    Offset := Offset and $3FFF
  else
    Offset := Offset and $7FFF;
  Value := FPrg[Offset];
end;

function TMapper000.CpuWrite(Address: UInt16; Value: UInt8): Boolean;
begin
  if (Address >= $6000) and (Address < $8000) then
  begin
    FPrgRam[Address and $1FFF] := Value;
    Exit(True);
  end;
  Result := Address >= $8000;
end;

function TMapper000.PpuRead(Address: UInt16; out Value: UInt8): Boolean;
begin
  Result := Address < $2000;
  if Result then
    Value := FChr[Address and $1FFF];
end;

function TMapper000.PpuWrite(Address: UInt16; Value: UInt8): Boolean;
begin
  Result := (Address < $2000) and FChrRam;
  if Result then
    FChr[Address and $1FFF] := Value;
end;

function TMapper000.GetMirrorMode: TMirrorMode;
begin
  Result := FMirrorMode;
end;

procedure TMapper000.Reset;
var
  I: Integer;
begin
  for I := Low(FPrgRam) to High(FPrgRam) do
    FPrgRam[I] := 0;
end;

end.

unit NES.Bus;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  NES.Types,
  NES.PPU,
  NES.Cartridge,
  NES.Controller,
  NES.APU;

type
  TNESBus = class
  private
    FRam: array[0..$07FF] of UInt8;
    FCartridge: TCartridge;
    FPPU: TPPU;
    FAPU: TAPU;
    FController1: TController;
    FController2: TController;
    FDmaActive: Boolean;
    FDmaDummy: Boolean;
    FDmaAlign: Boolean;
    FDmaPage: UInt8;
    FDmaAddr: UInt8;
    FDmaData: UInt8;
  public
    constructor Create;
    procedure Connect(Cartridge: TCartridge; PPU: TPPU; APU: TAPU; Controller1, Controller2: TController);
    function CpuRead(Address: UInt16): UInt8;
    procedure CpuWrite(Address: UInt16; Value: UInt8);
    function IsDmaActive: Boolean;
    procedure ClockDma(CpuCycleOdd: Boolean);
    function DebugCpuRead(Address: UInt16): UInt8;
  end;

implementation

constructor TNESBus.Create;
var I: Integer;
begin
  inherited Create;
  for I := Low(FRam) to High(FRam) do FRam[I] := 0;
  FDmaActive := False;
  FDmaDummy := True;
  FDmaAlign := False;
  FDmaPage := 0;
  FDmaAddr := 0;
  FDmaData := 0;
end;

procedure TNESBus.Connect(Cartridge: TCartridge; PPU: TPPU; APU: TAPU; Controller1, Controller2: TController);
begin
  FCartridge := Cartridge;
  FPPU := PPU;
  FAPU := APU;
  FController1 := Controller1;
  FController2 := Controller2;
end;

function TNESBus.CpuRead(Address: UInt16): UInt8;
var Value: UInt8;
begin
  if Address < $2000 then Exit(FRam[Address and $07FF]);
  if Address < $4000 then Exit(FPPU.CpuRead($2000 or (Address and 7)));

  case Address of
    $4015: Exit(FAPU.CpuReadStatus);
    $4016: Exit(FController1.Read);
    $4017: Exit(FController2.Read);
  end;

  if (FCartridge <> nil) and (FCartridge.Mapper <> nil) and FCartridge.Mapper.CpuRead(Address, Value) then
    Exit(Value);
  Result := 0;
end;

procedure TNESBus.CpuWrite(Address: UInt16; Value: UInt8);

begin
  if Address < $2000 then
  begin
    FRam[Address and $07FF] := Value;
    Exit;
  end;
  if Address < $4000 then
  begin
    FPPU.CpuWrite($2000 or (Address and 7), Value);
    Exit;
  end;

  case Address of
    $4000..$4013, $4015, $4017:
      begin
        FAPU.CpuWrite(Address, Value);
        if Address = $4016 then
        begin
          FController1.Write(Value);
          FController2.Write(Value);
        end;
        Exit;
      end;
    $4014:
      begin
        FDmaPage := Value;
        FDmaAddr := 0;
        FDmaDummy := True;
        FDmaAlign := False;
        FDmaActive := True;
        Exit;
      end;
    $4016:
      begin
        FController1.Write(Value);
        FController2.Write(Value);
        Exit;
      end;
  end;

  if (FCartridge <> nil) and (FCartridge.Mapper <> nil) and FCartridge.Mapper.CpuWrite(Address, Value) then
    Exit;
end;

function TNESBus.IsDmaActive: Boolean;
begin
  Result := FDmaActive;
end;

procedure TNESBus.ClockDma(CpuCycleOdd: Boolean);
begin
  if not FDmaActive then
    Exit;

  if FDmaDummy then
  begin
    FDmaDummy := False;
    FDmaAlign := CpuCycleOdd;
    Exit;
  end;

  if FDmaAlign then
  begin
    FDmaAlign := False;
    Exit;
  end;

  if CpuCycleOdd then
    FDmaData := CpuRead((UInt16(FDmaPage) shl 8) or FDmaAddr)
  else
  begin
    FPPU.WriteOAMDMA(FDmaAddr, FDmaData);
    Inc(FDmaAddr);
    if FDmaAddr = 0 then
    begin
      FDmaActive := False;
      FDmaDummy := True;
      FDmaAlign := False;
    end;
  end;
end;

function TNESBus.DebugCpuRead(Address: UInt16): UInt8;
begin
  Result := CpuRead(Address);
end;

end.








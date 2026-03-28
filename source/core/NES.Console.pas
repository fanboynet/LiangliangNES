unit NES.Console;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils,
  NES.Types,
  NES.CPU,
  NES.PPU,
  NES.APU,
  NES.Bus,
  NES.Cartridge,
  NES.Controller;

type
  TNESConsole = class
  private
    FCPU: TCPU6502;
    FPPU: TPPU;
    FAPU: TAPU;
    FBus: TNESBus;
    FCartridge: TCartridge;
    FController1: TController;
    FController2: TController;
    FMasterClock: UInt32;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadROM(const FileName: string);
    procedure Reset;
    procedure Clock;
    procedure RunFrame;
    function HasCartridge: Boolean;
    function DebugCpuRead(Address: UInt16): UInt8;
    property CPU: TCPU6502 read FCPU;
    property PPU: TPPU read FPPU;
    property APU: TAPU read FAPU;
    property Controller1: TController read FController1;
  end;

implementation

constructor TNESConsole.Create;
begin
  inherited Create;
  FCPU := TCPU6502.Create;
  FPPU := TPPU.Create;
  FAPU := TAPU.Create;
  FBus := TNESBus.Create;
  FCartridge := TCartridge.Create;
  FController1 := TController.Create;
  FController2 := TController.Create;
  FBus.Connect(FCartridge, FPPU, FAPU, FController1, FController2);
  FCPU.Connect(FBus.CpuRead, FBus.CpuWrite);
end;

destructor TNESConsole.Destroy;
begin
  FController2.Free;
  FController1.Free;
  FCartridge.Free;
  FBus.Free;
  FAPU.Free;
  FPPU.Free;
  FCPU.Free;
  inherited Destroy;
end;

procedure TNESConsole.LoadROM(const FileName: string);
begin
  FCartridge.LoadFromFile(FileName);
  FPPU.ConnectMapper(FCartridge.Mapper);
  Reset;
end;

procedure TNESConsole.Reset;
begin
  if FCartridge.Valid then FCartridge.Reset;
  FPPU.Reset;
  FPPU.ConnectMapper(FCartridge.Mapper);
  FAPU.Reset;
  FCPU.Reset;
  FMasterClock := 0;
end;

procedure TNESConsole.Clock;
begin
  FPPU.Clock;
  FPPU.Clock;
  FPPU.Clock;

  if FPPU.ConsumeNmi then
    FCPU.TriggerNmi;

  FAPU.Clock;
  FCPU.SetIrqLine(FAPU.IrqPending);

  if FBus.IsDmaActive then
    FBus.ClockDma((((FMasterClock div 3) and 1) <> 0))
  else
    FCPU.Clock;

  Inc(FMasterClock, 3);
end;

procedure TNESConsole.RunFrame;
begin
  FPPU.FrameReady := False;
  while not FPPU.FrameReady do
    Clock;
  FPPU.RebuildFrame;
end;

function TNESConsole.HasCartridge: Boolean;
begin
  Result := FCartridge.Valid;
end;

function TNESConsole.DebugCpuRead(Address: UInt16): UInt8;
begin
  Result := FBus.DebugCpuRead(Address);
end;

end.














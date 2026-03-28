unit NES.CPU;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  NES.Types;

const
  FLAG_CARRY     = $01;
  FLAG_ZERO      = $02;
  FLAG_INTERRUPT = $04;
  FLAG_DECIMAL   = $08;
  FLAG_BREAK     = $10;
  FLAG_UNUSED    = $20;
  FLAG_OVERFLOW  = $40;
  FLAG_NEGATIVE  = $80;

type
  TCPUReadFunc = function(Address: UInt16): UInt8 of object;
  TCPUWriteProc = procedure(Address: UInt16; Value: UInt8) of object;

  TInterruptKind = (ikNone, ikIRQ, ikNMI);

  TCPU6502 = class
  private
    FRead: TCPUReadFunc;
    FWrite: TCPUWriteProc;
    FPendingNmi: Boolean;
    FPendingIrq: Boolean;
    FNmiAfterInstruction: Boolean;
    FIrqAfterInstruction: Boolean;
    FUnknownOpcodeCount: Integer;
    FInterruptSequenceActive: Boolean;
    FInterruptKind: TInterruptKind;
    FInterruptBreakFlag: Boolean;
    FInterruptLatchedPC: UInt16;
    FInterruptLatchedP: UInt8;
    FInterruptVectorLow: UInt8;
    FDelayIrqOneInstruction: Boolean;
    FLastUnknownOpcode: UInt8;
    FLastUnknownPC: UInt16;
    function Read(Address: UInt16): UInt8;
    procedure Write(Address: UInt16; Value: UInt8);
    procedure Push(Value: UInt8);
    function Pull: UInt8;
    function Read16(Address: UInt16): UInt16;
    function Read16Bug(Address: UInt16): UInt16;
    function GetFlag(Flag: UInt8): Boolean;
    procedure SetFlag(Flag: UInt8; Value: Boolean);
    procedure SetZN(Value: UInt8);
    function Imm: UInt16;
    function Zp0: UInt16;
    function Zpx: UInt16;
    function Zpy: UInt16;
    function AbsAddr: UInt16;
    function Abx(out PageCrossed: Boolean): UInt16;
    function Aby(out PageCrossed: Boolean): UInt16;
    function Ind: UInt16;
    function Izx: UInt16;
    function Izy(out PageCrossed: Boolean): UInt16;
    function Rel: Int16;
    procedure ADC(Value: UInt8);
    procedure SBC(Value: UInt8);
    procedure CMP(RegValue, Value: UInt8);
    procedure BIT(Value: UInt8);
    procedure OpSLO(Address: UInt16);
    procedure OpRLA(Address: UInt16);
    procedure OpSRE(Address: UInt16);
    procedure OpRRA(Address: UInt16);
    procedure OpDCP(Address: UInt16);
    procedure OpISC(Address: UInt16);
    procedure LAXValue(Value: UInt8);
    procedure ANC(Value: UInt8);
    procedure ALR(Value: UInt8);
    procedure ARR(Value: UInt8);
    procedure ATX(Value: UInt8);
    procedure LXA(Value: UInt8);
    procedure Branch(Condition: Boolean; Offset: Int16; out Cycles: Integer);
    procedure Interrupt(Vector: UInt16; BreakFlag: Boolean);
    procedure BeginInterruptSequence(Kind: TInterruptKind; BreakFlag: Boolean);
    procedure ExecuteOpcode(Opcode: UInt8);
  public
    A: UInt8;
    X: UInt8;
    Y: UInt8;
    SP: UInt8;
    PC: UInt16;
    P: UInt8;
    CyclesRemaining: Integer;
    TotalCycles: UInt32;
    constructor Create;
    procedure Connect(Reader: TCPUReadFunc; Writer: TCPUWriteProc);
    procedure Reset;
    procedure Clock;
    procedure TriggerNmi;
    procedure TriggerIrq;
    procedure SetIrqLine(Active: Boolean);
    property UnknownOpcodeCount: Integer read FUnknownOpcodeCount;
    property LastUnknownOpcode: UInt8 read FLastUnknownOpcode;
    property LastUnknownPC: UInt16 read FLastUnknownPC;
  end;

implementation

constructor TCPU6502.Create;
begin
  inherited Create;
  Reset;
end;

procedure TCPU6502.Connect(Reader: TCPUReadFunc; Writer: TCPUWriteProc);
begin
  FRead := Reader;
  FWrite := Writer;
end;

function TCPU6502.Read(Address: UInt16): UInt8;
begin
  Result := FRead(Address);
end;

procedure TCPU6502.Write(Address: UInt16; Value: UInt8);
begin
  FWrite(Address, Value);
end;

procedure TCPU6502.Push(Value: UInt8);
begin
  Write($0100 or SP, Value);
  Dec(SP);
end;

function TCPU6502.Pull: UInt8;
begin
  Inc(SP);
  Result := Read($0100 or SP);
end;

function TCPU6502.Read16(Address: UInt16): UInt16;
var
  Lo, Hi: UInt8;
begin
  Lo := Read(Address);
  Hi := Read(Address + 1);
  Result := Lo or (UInt16(Hi) shl 8);
end;

function TCPU6502.Read16Bug(Address: UInt16): UInt16;
var
  Lo, Hi: UInt8;
  WrapAddr: UInt16;
begin
  Lo := Read(Address);
  WrapAddr := (Address and $FF00) or ((Address + 1) and $00FF);
  Hi := Read(WrapAddr);
  Result := Lo or (UInt16(Hi) shl 8);
end;

function TCPU6502.GetFlag(Flag: UInt8): Boolean;
begin
  Result := (P and Flag) <> 0;
end;

procedure TCPU6502.SetFlag(Flag: UInt8; Value: Boolean);
begin
  if Value then
    P := P or Flag
  else
    P := P and not Flag;
end;

procedure TCPU6502.SetZN(Value: UInt8);
begin
  SetFlag(FLAG_ZERO, Value = 0);
  SetFlag(FLAG_NEGATIVE, (Value and $80) <> 0);
end;

function TCPU6502.Imm: UInt16;
begin
  Result := PC;
  Inc(PC);
end;

function TCPU6502.Zp0: UInt16;
begin
  Result := Read(PC);
  Inc(PC);
end;

function TCPU6502.Zpx: UInt16;
begin
  Result := (Read(PC) + X) and $FF;
  Inc(PC);
end;

function TCPU6502.Zpy: UInt16;
begin
  Result := (Read(PC) + Y) and $FF;
  Inc(PC);
end;

function TCPU6502.AbsAddr: UInt16;
begin
  Result := Read16(PC);
  Inc(PC, 2);
end;

function TCPU6502.Abx(out PageCrossed: Boolean): UInt16;
var
  Base: UInt16;
begin
  Base := Read16(PC);
  Inc(PC, 2);
  Result := Base + X;
  PageCrossed := (Base and $FF00) <> (Result and $FF00);
end;

function TCPU6502.Aby(out PageCrossed: Boolean): UInt16;
var
  Base: UInt16;
begin
  Base := Read16(PC);
  Inc(PC, 2);
  Result := Base + Y;
  PageCrossed := (Base and $FF00) <> (Result and $FF00);
end;

function TCPU6502.Ind: UInt16;
var
  Ptr: UInt16;
begin
  Ptr := Read16(PC);
  Inc(PC, 2);
  Result := Read16Bug(Ptr);
end;

function TCPU6502.Izx: UInt16;
var
  Ptr: UInt8;
  Lo, Hi: UInt8;
begin
  Ptr := (Read(PC) + X) and $FF;
  Inc(PC);
  Lo := Read(Ptr);
  Hi := Read((Ptr + 1) and $FF);
  Result := Lo or (UInt16(Hi) shl 8);
end;

function TCPU6502.Izy(out PageCrossed: Boolean): UInt16;
var
  Ptr: UInt8;
  Base: UInt16;
  Lo, Hi: UInt8;
begin
  Ptr := Read(PC);
  Inc(PC);
  Lo := Read(Ptr);
  Hi := Read((Ptr + 1) and $FF);
  Base := Lo or (UInt16(Hi) shl 8);
  Result := Base + Y;
  PageCrossed := (Base and $FF00) <> (Result and $FF00);
end;

function TCPU6502.Rel: Int16;
var
  Offset: UInt8;
begin
  Offset := Read(PC);
  Inc(PC);
  if Offset < $80 then Result := Offset else Result := Offset - $100;
end;

procedure TCPU6502.ADC(Value: UInt8);
var Sum: UInt16; Result8: UInt8; CarryIn: UInt16;
begin
  if GetFlag(FLAG_CARRY) then CarryIn := 1 else CarryIn := 0;
  Sum := UInt16(A) + UInt16(Value) + CarryIn;
  Result8 := Sum and $FF;
  SetFlag(FLAG_CARRY, Sum > $FF);
  SetFlag(FLAG_OVERFLOW, ((not (A xor Value)) and (A xor Result8) and $80) <> 0);
  A := Result8;
  SetZN(A);
end;

procedure TCPU6502.SBC(Value: UInt8);
begin
  ADC(Value xor $FF);
end;

procedure TCPU6502.CMP(RegValue, Value: UInt8);
var Temp: UInt16;
begin
  Temp := UInt16(RegValue) - UInt16(Value);
  SetFlag(FLAG_CARRY, RegValue >= Value);
  SetFlag(FLAG_ZERO, (Temp and $FF) = 0);
  SetFlag(FLAG_NEGATIVE, (Temp and $80) <> 0);
end;

procedure TCPU6502.BIT(Value: UInt8);
begin
  SetFlag(FLAG_ZERO, (A and Value) = 0);
  SetFlag(FLAG_OVERFLOW, (Value and $40) <> 0);
  SetFlag(FLAG_NEGATIVE, (Value and $80) <> 0);
end;

procedure TCPU6502.OpSLO(Address: UInt16);
var
  Value: UInt8;
begin
  Value := Read(Address);
  SetFlag(FLAG_CARRY, (Value and $80) <> 0);
  Value := Value shl 1;
  Write(Address, Value);
  A := A or Value;
  SetZN(A);
end;

procedure TCPU6502.OpRLA(Address: UInt16);
var
  Value: UInt8;
  Carry: UInt8;
begin
  Value := Read(Address);
  Carry := Ord(GetFlag(FLAG_CARRY));
  SetFlag(FLAG_CARRY, (Value and $80) <> 0);
  Value := (Value shl 1) or Carry;
  Write(Address, Value);
  A := A and Value;
  SetZN(A);
end;

procedure TCPU6502.OpSRE(Address: UInt16);
var
  Value: UInt8;
begin
  Value := Read(Address);
  SetFlag(FLAG_CARRY, (Value and 1) <> 0);
  Value := Value shr 1;
  Write(Address, Value);
  A := A xor Value;
  SetZN(A);
end;

procedure TCPU6502.OpRRA(Address: UInt16);
var
  Value: UInt8;
  Carry: UInt8;
begin
  Value := Read(Address);
  Carry := Ord(GetFlag(FLAG_CARRY));
  SetFlag(FLAG_CARRY, (Value and 1) <> 0);
  Value := (Value shr 1) or (Carry shl 7);
  Write(Address, Value);
  ADC(Value);
end;

procedure TCPU6502.OpDCP(Address: UInt16);
var
  Value: UInt8;
begin
  Value := Read(Address);
  Dec(Value);
  Write(Address, Value);
  CMP(A, Value);
end;

procedure TCPU6502.OpISC(Address: UInt16);
var
  Value: UInt8;
begin
  Value := Read(Address);
  Inc(Value);
  Write(Address, Value);
  SBC(Value);
end;

procedure TCPU6502.LAXValue(Value: UInt8);
begin
  A := Value;
  X := Value;
  SetZN(A);
end;

procedure TCPU6502.ANC(Value: UInt8);
begin
  A := A and Value;
  SetZN(A);
  SetFlag(FLAG_CARRY, (A and $80) <> 0);
end;

procedure TCPU6502.ALR(Value: UInt8);
begin
  A := A and Value;
  SetFlag(FLAG_CARRY, (A and 1) <> 0);
  A := A shr 1;
  SetZN(A);
end;

procedure TCPU6502.ARR(Value: UInt8);
var
  Carry: UInt8;
begin
  A := A and Value;
  Carry := Ord(GetFlag(FLAG_CARRY));
  A := (A shr 1) or (Carry shl 7);
  SetZN(A);
  SetFlag(FLAG_CARRY, (A and $40) <> 0);
  SetFlag(FLAG_OVERFLOW, (((A shr 6) xor (A shr 5)) and 1) <> 0);
end;

procedure TCPU6502.ATX(Value: UInt8);
begin
  A := A and Value;
  X := A;
  SetZN(A);
end;

procedure TCPU6502.LXA(Value: UInt8);
begin
  A := (A or $EE) and Value;
  X := A;
  SetZN(A);
end;
procedure TCPU6502.Branch(Condition: Boolean; Offset: Int16; out Cycles: Integer);
var OldPC, NewPC: UInt16;
begin
  Cycles := 2;
  if Condition then
  begin
    Inc(Cycles);
    OldPC := PC;
    NewPC := UInt16(Int32(PC) + Offset);
    if (OldPC and $FF00) <> (NewPC and $FF00) then Inc(Cycles);
    PC := NewPC;
  end;
end;

procedure TCPU6502.BeginInterruptSequence(Kind: TInterruptKind; BreakFlag: Boolean);
begin
  FInterruptSequenceActive := True;
  FInterruptKind := Kind;
  FInterruptBreakFlag := BreakFlag;
  CyclesRemaining := 7;
end;

procedure TCPU6502.Interrupt(Vector: UInt16; BreakFlag: Boolean);
var FlagsToPush: UInt8;
begin
  Push((PC shr 8) and $FF);
  Push(PC and $FF);
  FlagsToPush := P or FLAG_UNUSED;
  if BreakFlag then FlagsToPush := FlagsToPush or FLAG_BREAK else FlagsToPush := FlagsToPush and not FLAG_BREAK;
  Push(FlagsToPush);
  SetFlag(FLAG_INTERRUPT, True);
  PC := Read16(Vector);
end;

procedure TCPU6502.Reset;
begin
  A := 0; X := 0; Y := 0; SP := $FD; P := FLAG_UNUSED or FLAG_INTERRUPT;
  if Assigned(FRead) then PC := Read16($FFFC) else PC := 0;
  CyclesRemaining := 7; TotalCycles := 0; FPendingNmi := False; FPendingIrq := False; FNmiAfterInstruction := False; FIrqAfterInstruction := False;
  FInterruptSequenceActive := False; FInterruptKind := ikNone; FInterruptBreakFlag := False;
  FInterruptLatchedPC := 0; FInterruptLatchedP := 0; FInterruptVectorLow := 0;
  FDelayIrqOneInstruction := False;
  FUnknownOpcodeCount := 0; FLastUnknownOpcode := 0; FLastUnknownPC := 0;
end;

procedure TCPU6502.TriggerNmi; begin FPendingNmi := True; end;
procedure TCPU6502.TriggerIrq; begin FPendingIrq := True; end;
procedure TCPU6502.SetIrqLine(Active: Boolean); begin FPendingIrq := Active; end;

procedure TCPU6502.Clock;
var
  Opcode: UInt8;
  NmiSample: Boolean;
  IrqSample: Boolean;
begin
  if FInterruptSequenceActive and (FInterruptKind <> ikNMI) and FPendingNmi then
  begin
    if (not FInterruptBreakFlag) or (CyclesRemaining > 3) then
      FInterruptKind := ikNMI;
  end;

  if CyclesRemaining = 0 then
  begin
    if FInterruptSequenceActive then
    begin
      case FInterruptKind of
        ikNMI:
          begin
            Interrupt($FFFA, FInterruptBreakFlag);
            FPendingNmi := False;
          end;
        ikIRQ:
          begin
            Interrupt($FFFE, FInterruptBreakFlag);
          end;
      end;
      FInterruptSequenceActive := False;
      FInterruptKind := ikNone;
      FInterruptBreakFlag := False;
    end
    else if FNmiAfterInstruction then
    begin
      FNmiAfterInstruction := False;
      FIrqAfterInstruction := False;
      BeginInterruptSequence(ikNMI, False);
    end
    else if FIrqAfterInstruction then
    begin
      FIrqAfterInstruction := False;
      BeginInterruptSequence(ikIRQ, False);
    end
    else
    begin
      Opcode := Read(PC);
      NmiSample := FPendingNmi;
      if FDelayIrqOneInstruction then
        IrqSample := False
      else
        IrqSample := FPendingIrq and not GetFlag(FLAG_INTERRUPT);
      ExecuteOpcode(Opcode);
      if Opcode = $40 then
      begin
        FNmiAfterInstruction := FPendingNmi;
        if FDelayIrqOneInstruction then
        begin
          FIrqAfterInstruction := False;
          FDelayIrqOneInstruction := False;
          if FPendingIrq and not GetFlag(FLAG_INTERRUPT) then
            FIrqAfterInstruction := True;
        end
        else
          FIrqAfterInstruction := FPendingIrq and not GetFlag(FLAG_INTERRUPT);
      end
      else if Opcode = $00 then
      begin
        FNmiAfterInstruction := False;
        FIrqAfterInstruction := False;
      end
      else if (Opcode = $28) or (Opcode = $58) or (Opcode = $78) then
      begin
        FNmiAfterInstruction := FPendingNmi;
        if FDelayIrqOneInstruction then
        begin
          FIrqAfterInstruction := False;
          FDelayIrqOneInstruction := False;
          if FPendingIrq and not GetFlag(FLAG_INTERRUPT) then
            FIrqAfterInstruction := True;
        end
        else
          FIrqAfterInstruction := IrqSample;
      end
      else
      begin
        FNmiAfterInstruction := FPendingNmi;
        if FDelayIrqOneInstruction then
        begin
          FIrqAfterInstruction := False;
          FDelayIrqOneInstruction := False;
          if FPendingIrq and not GetFlag(FLAG_INTERRUPT) then
            FIrqAfterInstruction := True;
        end
        else if (not IrqSample) and FPendingIrq and not GetFlag(FLAG_INTERRUPT) and
                (((Opcode = $10) or (Opcode = $30) or (Opcode = $50) or (Opcode = $70) or
                  (Opcode = $90) or (Opcode = $B0) or (Opcode = $D0) or (Opcode = $F0)) and
                 (CyclesRemaining = 3)) then
        begin
          FIrqAfterInstruction := False;
          FDelayIrqOneInstruction := True;
        end
        else
          FIrqAfterInstruction := FPendingIrq and not GetFlag(FLAG_INTERRUPT);
      end;
      if NmiSample and (Opcode <> $00) then
        FPendingNmi := False;
    end;
  end;
  if CyclesRemaining > 0 then
    Dec(CyclesRemaining);
  Inc(TotalCycles);
end;

procedure TCPU6502.ExecuteOpcode(Opcode: UInt8);
var Addr, Base: UInt16; Value, Mask, Ptr: UInt8; PageCrossed: Boolean; Cycles: Integer; Offset: Int16; Carry: UInt8; OpPC: UInt16;
begin
  OpPC := PC;
  Inc(PC);
  PageCrossed := False;
  Cycles := 2;
  case Opcode of
    $00: begin Inc(PC); BeginInterruptSequence(ikIRQ, True); Cycles := 7; end;
    $01: begin Addr := Izx; A := A or Read(Addr); SetZN(A); Cycles := 6; end;
    $03: begin Addr := Izx; OpSLO(Addr); Cycles := 8; end;
    $04, $44, $64: begin Addr := Zp0; Cycles := 3; end;
    $05: begin Addr := Zp0; A := A or Read(Addr); SetZN(A); Cycles := 3; end;
    $07: begin Addr := Zp0; OpSLO(Addr); Cycles := 5; end;
    $06: begin Addr := Zp0; Value := Read(Addr); SetFlag(FLAG_CARRY, (Value and $80) <> 0); Value := Value shl 1; Write(Addr, Value); SetZN(Value); Cycles := 5; end;
    $08: begin Push(P or FLAG_BREAK or FLAG_UNUSED); Cycles := 3; end;
    $0B, $2B: begin Addr := Imm; ANC(Read(Addr)); Cycles := 2; end;
    $09: begin Addr := Imm; A := A or Read(Addr); SetZN(A); Cycles := 2; end;
    $0A: begin SetFlag(FLAG_CARRY, (A and $80) <> 0); A := A shl 1; SetZN(A); Cycles := 2; end;
    $0C: begin Addr := AbsAddr; Cycles := 4; end;
    $0D: begin Addr := AbsAddr; A := A or Read(Addr); SetZN(A); Cycles := 4; end;
    $0E: begin Addr := AbsAddr; Value := Read(Addr); SetFlag(FLAG_CARRY, (Value and $80) <> 0); Value := Value shl 1; Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $0F: begin Addr := AbsAddr; OpSLO(Addr); Cycles := 6; end;
    $10: begin Offset := Rel; Branch(not GetFlag(FLAG_NEGATIVE), Offset, Cycles); end;
    $11: begin Addr := Izy(PageCrossed); A := A or Read(Addr); SetZN(A); Cycles := 5 + Ord(PageCrossed); end;
    $13: begin Addr := Izy(PageCrossed); OpSLO(Addr); Cycles := 8; end;
    $14, $34, $54, $74, $D4, $F4: begin Addr := Zpx; Cycles := 4; end;
    $15: begin Addr := Zpx; A := A or Read(Addr); SetZN(A); Cycles := 4; end;
    $16: begin Addr := Zpx; Value := Read(Addr); SetFlag(FLAG_CARRY, (Value and $80) <> 0); Value := Value shl 1; Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $17: begin Addr := Zpx; OpSLO(Addr); Cycles := 6; end;
    $18: begin SetFlag(FLAG_CARRY, False); Cycles := 2; end;
    $19: begin Addr := Aby(PageCrossed); A := A or Read(Addr); SetZN(A); Cycles := 4 + Ord(PageCrossed); end;
    $1B: begin Addr := Aby(PageCrossed); OpSLO(Addr); Cycles := 7; end;
    $1A, $3A, $5A, $7A, $DA, $FA: begin Cycles := 2; end;
    $1C, $3C, $5C, $7C, $DC, $FC: begin Addr := Abx(PageCrossed); Cycles := 4 + Ord(PageCrossed); end;
    $1D: begin Addr := Abx(PageCrossed); A := A or Read(Addr); SetZN(A); Cycles := 4 + Ord(PageCrossed); end;
    $1F: begin Addr := Abx(PageCrossed); OpSLO(Addr); Cycles := 7; end;
    $1E: begin Addr := Abx(PageCrossed); Value := Read(Addr); SetFlag(FLAG_CARRY, (Value and $80) <> 0); Value := Value shl 1; Write(Addr, Value); SetZN(Value); Cycles := 7; end;
    $20: begin Addr := AbsAddr; Push(((PC - 1) shr 8) and $FF); Push((PC - 1) and $FF); PC := Addr; Cycles := 6; end;
    $21: begin Addr := Izx; A := A and Read(Addr); SetZN(A); Cycles := 6; end;
    $23: begin Addr := Izx; OpRLA(Addr); Cycles := 8; end;
    $24: begin Addr := Zp0; BIT(Read(Addr)); Cycles := 3; end;
    $25: begin Addr := Zp0; A := A and Read(Addr); SetZN(A); Cycles := 3; end;
    $27: begin Addr := Zp0; OpRLA(Addr); Cycles := 5; end;
    $26: begin Addr := Zp0; Value := Read(Addr); Carry := Ord(GetFlag(FLAG_CARRY)); SetFlag(FLAG_CARRY, (Value and $80) <> 0); Value := (Value shl 1) or Carry; Write(Addr, Value); SetZN(Value); Cycles := 5; end;
    $28: begin P := Pull; P := (P or FLAG_UNUSED) and not FLAG_BREAK; Cycles := 4; end;
    $29: begin Addr := Imm; A := A and Read(Addr); SetZN(A); Cycles := 2; end;
    $2A: begin Carry := Ord(GetFlag(FLAG_CARRY)); SetFlag(FLAG_CARRY, (A and $80) <> 0); A := (A shl 1) or Carry; SetZN(A); Cycles := 2; end;
    $2C: begin Addr := AbsAddr; BIT(Read(Addr)); Cycles := 4; end;
    $2D: begin Addr := AbsAddr; A := A and Read(Addr); SetZN(A); Cycles := 4; end;
    $2E: begin Addr := AbsAddr; Value := Read(Addr); Carry := Ord(GetFlag(FLAG_CARRY)); SetFlag(FLAG_CARRY, (Value and $80) <> 0); Value := (Value shl 1) or Carry; Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $2F: begin Addr := AbsAddr; OpRLA(Addr); Cycles := 6; end;
    $30: begin Offset := Rel; Branch(GetFlag(FLAG_NEGATIVE), Offset, Cycles); end;
    $31: begin Addr := Izy(PageCrossed); A := A and Read(Addr); SetZN(A); Cycles := 5 + Ord(PageCrossed); end;
    $33: begin Addr := Izy(PageCrossed); OpRLA(Addr); Cycles := 8; end;
    $35: begin Addr := Zpx; A := A and Read(Addr); SetZN(A); Cycles := 4; end;
    $36: begin Addr := Zpx; Value := Read(Addr); Carry := Ord(GetFlag(FLAG_CARRY)); SetFlag(FLAG_CARRY, (Value and $80) <> 0); Value := (Value shl 1) or Carry; Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $37: begin Addr := Zpx; OpRLA(Addr); Cycles := 6; end;
    $38: begin SetFlag(FLAG_CARRY, True); Cycles := 2; end;
    $39: begin Addr := Aby(PageCrossed); A := A and Read(Addr); SetZN(A); Cycles := 4 + Ord(PageCrossed); end;
    $3B: begin Addr := Aby(PageCrossed); OpRLA(Addr); Cycles := 7; end;
    $3D: begin Addr := Abx(PageCrossed); A := A and Read(Addr); SetZN(A); Cycles := 4 + Ord(PageCrossed); end;
    $3F: begin Addr := Abx(PageCrossed); OpRLA(Addr); Cycles := 7; end;
    $3E: begin Addr := Abx(PageCrossed); Value := Read(Addr); Carry := Ord(GetFlag(FLAG_CARRY)); SetFlag(FLAG_CARRY, (Value and $80) <> 0); Value := (Value shl 1) or Carry; Write(Addr, Value); SetZN(Value); Cycles := 7; end;
    $40: begin P := Pull; P := (P or FLAG_UNUSED) and not FLAG_BREAK; Value := Pull; PC := Value; Value := Pull; PC := PC or (UInt16(Value) shl 8); Cycles := 6; end;
    $41: begin Addr := Izx; A := A xor Read(Addr); SetZN(A); Cycles := 6; end;
    $43: begin Addr := Izx; OpSRE(Addr); Cycles := 8; end;
    $45: begin Addr := Zp0; A := A xor Read(Addr); SetZN(A); Cycles := 3; end;
    $47: begin Addr := Zp0; OpSRE(Addr); Cycles := 5; end;
    $46: begin Addr := Zp0; Value := Read(Addr); SetFlag(FLAG_CARRY, (Value and 1) <> 0); Value := Value shr 1; Write(Addr, Value); SetZN(Value); Cycles := 5; end;
    $48: begin Push(A); Cycles := 3; end;
    $49: begin Addr := Imm; A := A xor Read(Addr); SetZN(A); Cycles := 2; end;
    $4B: begin Addr := Imm; ALR(Read(Addr)); Cycles := 2; end;
    $4A: begin SetFlag(FLAG_CARRY, (A and 1) <> 0); A := A shr 1; SetZN(A); Cycles := 2; end;
    $4C: begin PC := AbsAddr; Cycles := 3; end;
    $4D: begin Addr := AbsAddr; A := A xor Read(Addr); SetZN(A); Cycles := 4; end;
    $4E: begin Addr := AbsAddr; Value := Read(Addr); SetFlag(FLAG_CARRY, (Value and 1) <> 0); Value := Value shr 1; Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $4F: begin Addr := AbsAddr; OpSRE(Addr); Cycles := 6; end;
    $50: begin Offset := Rel; Branch(not GetFlag(FLAG_OVERFLOW), Offset, Cycles); end;
    $51: begin Addr := Izy(PageCrossed); A := A xor Read(Addr); SetZN(A); Cycles := 5 + Ord(PageCrossed); end;
    $53: begin Addr := Izy(PageCrossed); OpSRE(Addr); Cycles := 8; end;
    $55: begin Addr := Zpx; A := A xor Read(Addr); SetZN(A); Cycles := 4; end;
    $56: begin Addr := Zpx; Value := Read(Addr); SetFlag(FLAG_CARRY, (Value and 1) <> 0); Value := Value shr 1; Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $57: begin Addr := Zpx; OpSRE(Addr); Cycles := 6; end;
    $58: begin SetFlag(FLAG_INTERRUPT, False); Cycles := 2; end;
    $59: begin Addr := Aby(PageCrossed); A := A xor Read(Addr); SetZN(A); Cycles := 4 + Ord(PageCrossed); end;
    $5B: begin Addr := Aby(PageCrossed); OpSRE(Addr); Cycles := 7; end;
    $5D: begin Addr := Abx(PageCrossed); A := A xor Read(Addr); SetZN(A); Cycles := 4 + Ord(PageCrossed); end;
    $5F: begin Addr := Abx(PageCrossed); OpSRE(Addr); Cycles := 7; end;
    $5E: begin Addr := Abx(PageCrossed); Value := Read(Addr); SetFlag(FLAG_CARRY, (Value and 1) <> 0); Value := Value shr 1; Write(Addr, Value); SetZN(Value); Cycles := 7; end;
    $60: begin Value := Pull; PC := Value; Value := Pull; PC := PC or (UInt16(Value) shl 8); Inc(PC); Cycles := 6; end;
    $61: begin Addr := Izx; ADC(Read(Addr)); Cycles := 6; end;
    $63: begin Addr := Izx; OpRRA(Addr); Cycles := 8; end;
    $65: begin Addr := Zp0; ADC(Read(Addr)); Cycles := 3; end;
    $67: begin Addr := Zp0; OpRRA(Addr); Cycles := 5; end;
    $66: begin Addr := Zp0; Value := Read(Addr); Carry := Ord(GetFlag(FLAG_CARRY)); SetFlag(FLAG_CARRY, (Value and 1) <> 0); Value := (Value shr 1) or (Carry shl 7); Write(Addr, Value); SetZN(Value); Cycles := 5; end;
    $68: begin A := Pull; SetZN(A); Cycles := 4; end;
    $69: begin Addr := Imm; ADC(Read(Addr)); Cycles := 2; end;
    $6B: begin Addr := Imm; ARR(Read(Addr)); Cycles := 2; end;
    $6A: begin Carry := Ord(GetFlag(FLAG_CARRY)); SetFlag(FLAG_CARRY, (A and 1) <> 0); A := (A shr 1) or (Carry shl 7); SetZN(A); Cycles := 2; end;
    $6C: begin PC := Ind; Cycles := 5; end;
    $6D: begin Addr := AbsAddr; ADC(Read(Addr)); Cycles := 4; end;
    $6E: begin Addr := AbsAddr; Value := Read(Addr); Carry := Ord(GetFlag(FLAG_CARRY)); SetFlag(FLAG_CARRY, (Value and 1) <> 0); Value := (Value shr 1) or (Carry shl 7); Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $6F: begin Addr := AbsAddr; OpRRA(Addr); Cycles := 6; end;
    $70: begin Offset := Rel; Branch(GetFlag(FLAG_OVERFLOW), Offset, Cycles); end;
    $71: begin Addr := Izy(PageCrossed); ADC(Read(Addr)); Cycles := 5 + Ord(PageCrossed); end;
    $73: begin Addr := Izy(PageCrossed); OpRRA(Addr); Cycles := 8; end;
    $75: begin Addr := Zpx; ADC(Read(Addr)); Cycles := 4; end;
    $76: begin Addr := Zpx; Value := Read(Addr); Carry := Ord(GetFlag(FLAG_CARRY)); SetFlag(FLAG_CARRY, (Value and 1) <> 0); Value := (Value shr 1) or (Carry shl 7); Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $77: begin Addr := Zpx; OpRRA(Addr); Cycles := 6; end;
    $78: begin SetFlag(FLAG_INTERRUPT, True); Cycles := 2; end;
    $79: begin Addr := Aby(PageCrossed); ADC(Read(Addr)); Cycles := 4 + Ord(PageCrossed); end;
    $7B: begin Addr := Aby(PageCrossed); OpRRA(Addr); Cycles := 7; end;
    $7D: begin Addr := Abx(PageCrossed); ADC(Read(Addr)); Cycles := 4 + Ord(PageCrossed); end;
    $7F: begin Addr := Abx(PageCrossed); OpRRA(Addr); Cycles := 7; end;
    $7E: begin Addr := Abx(PageCrossed); Value := Read(Addr); Carry := Ord(GetFlag(FLAG_CARRY)); SetFlag(FLAG_CARRY, (Value and 1) <> 0); Value := (Value shr 1) or (Carry shl 7); Write(Addr, Value); SetZN(Value); Cycles := 7; end;
    $80, $82, $89, $C2, $E2: begin Addr := Imm; Cycles := 2; end;
    $81: begin Addr := Izx; Write(Addr, A); Cycles := 6; end;
    $83: begin Addr := Izx; Write(Addr, A and X); Cycles := 6; end;
    $84: begin Addr := Zp0; Write(Addr, Y); Cycles := 3; end;
    $85: begin Addr := Zp0; Write(Addr, A); Cycles := 3; end;
    $86: begin Addr := Zp0; Write(Addr, X); Cycles := 3; end;
    $87: begin Addr := Zp0; Write(Addr, A and X); Cycles := 3; end;
    $88: begin Dec(Y); SetZN(Y); Cycles := 2; end;
    $8A: begin A := X; SetZN(A); Cycles := 2; end;
    $8B: begin Addr := Imm; ATX(Read(Addr)); Cycles := 2; end;
    $8C: begin Addr := AbsAddr; Write(Addr, Y); Cycles := 4; end;
    $8D: begin Addr := AbsAddr; Write(Addr, A); Cycles := 4; end;
    $8E: begin Addr := AbsAddr; Write(Addr, X); Cycles := 4; end;
    $8F: begin Addr := AbsAddr; Write(Addr, A and X); Cycles := 4; end;
    $90: begin Offset := Rel; Branch(not GetFlag(FLAG_CARRY), Offset, Cycles); end;
    $91: begin Addr := Izy(PageCrossed); Write(Addr, A); Cycles := 6; end;
    $93: begin Ptr := Read(PC); Inc(PC); Value := Read(Ptr); Mask := Read((Ptr + 1) and $FF); Base := Value or (UInt16(Mask) shl 8); Addr := Base + Y; Mask := A and X and UInt8((((Base shr 8) + 1) and $FF)); if (Base and $FF00) <> (Addr and $FF00) then Addr := (Addr and $00FF) or (UInt16(Mask) shl 8); Write(Addr, Mask); Cycles := 6; end;
    $94: begin Addr := Zpx; Write(Addr, Y); Cycles := 4; end;
    $95: begin Addr := Zpx; Write(Addr, A); Cycles := 4; end;
    $96: begin Addr := Zpy; Write(Addr, X); Cycles := 4; end;
    $97: begin Addr := Zpy; Write(Addr, A and X); Cycles := 4; end;
    $98: begin A := Y; SetZN(A); Cycles := 2; end;
    $99: begin Addr := Aby(PageCrossed); Write(Addr, A); Cycles := 5; end;
    $9B: begin Base := AbsAddr; Addr := Base + Y; SP := A and X; Mask := SP and UInt8((((Base shr 8) + 1) and $FF)); if (Base and $FF00) <> (Addr and $FF00) then Addr := (Addr and $00FF) or (UInt16(Mask) shl 8); Write(Addr, Mask); Cycles := 5; end;
    $9C: begin Base := AbsAddr; Addr := Base + X; Mask := Y and UInt8((((Base shr 8) + 1) and $FF)); if (Base and $FF00) <> (Addr and $FF00) then Addr := (Addr and $00FF) or (UInt16(Mask) shl 8); Write(Addr, Mask); Cycles := 5; end;
    $9A: begin SP := X; Cycles := 2; end;
    $9D: begin Addr := Abx(PageCrossed); Write(Addr, A); Cycles := 5; end;
    $9E: begin Base := AbsAddr; Addr := Base + Y; Mask := X and UInt8((((Base shr 8) + 1) and $FF)); if (Base and $FF00) <> (Addr and $FF00) then Addr := (Addr and $00FF) or (UInt16(Mask) shl 8); Write(Addr, Mask); Cycles := 5; end;
    $9F: begin Base := AbsAddr; Addr := Base + Y; Mask := A and X and UInt8((((Base shr 8) + 1) and $FF)); if (Base and $FF00) <> (Addr and $FF00) then Addr := (Addr and $00FF) or (UInt16(Mask) shl 8); Write(Addr, Mask); Cycles := 5; end;
    $A0: begin Addr := Imm; Y := Read(Addr); SetZN(Y); Cycles := 2; end;
    $A1: begin Addr := Izx; A := Read(Addr); SetZN(A); Cycles := 6; end;
    $A3: begin Addr := Izx; LAXValue(Read(Addr)); Cycles := 6; end;
    $A2: begin Addr := Imm; X := Read(Addr); SetZN(X); Cycles := 2; end;
    $A4: begin Addr := Zp0; Y := Read(Addr); SetZN(Y); Cycles := 3; end;
    $A5: begin Addr := Zp0; A := Read(Addr); SetZN(A); Cycles := 3; end;
    $A6: begin Addr := Zp0; X := Read(Addr); SetZN(X); Cycles := 3; end;
    $A7: begin Addr := Zp0; LAXValue(Read(Addr)); Cycles := 3; end;
    $A8: begin Y := A; SetZN(Y); Cycles := 2; end;
    $A9: begin Addr := Imm; A := Read(Addr); SetZN(A); Cycles := 2; end;
    $AB: begin Addr := Imm; ATX(Read(Addr)); Cycles := 2; end;
    $AA: begin X := A; SetZN(X); Cycles := 2; end;
    $AC: begin Addr := AbsAddr; Y := Read(Addr); SetZN(Y); Cycles := 4; end;
    $AD: begin Addr := AbsAddr; A := Read(Addr); SetZN(A); Cycles := 4; end;
    $AE: begin Addr := AbsAddr; X := Read(Addr); SetZN(X); Cycles := 4; end;
    $AF: begin Addr := AbsAddr; LAXValue(Read(Addr)); Cycles := 4; end;
    $B0: begin Offset := Rel; Branch(GetFlag(FLAG_CARRY), Offset, Cycles); end;
    $B1: begin Addr := Izy(PageCrossed); A := Read(Addr); SetZN(A); Cycles := 5 + Ord(PageCrossed); end;
    $B3: begin Addr := Izy(PageCrossed); LAXValue(Read(Addr)); Cycles := 5 + Ord(PageCrossed); end;
    $B4: begin Addr := Zpx; Y := Read(Addr); SetZN(Y); Cycles := 4; end;
    $B5: begin Addr := Zpx; A := Read(Addr); SetZN(A); Cycles := 4; end;
    $B6: begin Addr := Zpy; X := Read(Addr); SetZN(X); Cycles := 4; end;
    $B7: begin Addr := Zpy; LAXValue(Read(Addr)); Cycles := 4; end;
    $B8: begin SetFlag(FLAG_OVERFLOW, False); Cycles := 2; end;
    $B9: begin Addr := Aby(PageCrossed); A := Read(Addr); SetZN(A); Cycles := 4 + Ord(PageCrossed); end;
    $BA: begin X := SP; SetZN(X); Cycles := 2; end;
    $BB: begin Addr := Aby(PageCrossed); Value := Read(Addr) and SP; A := Value; X := Value; SP := Value; SetZN(Value); Cycles := 4 + Ord(PageCrossed); end;
    $BC: begin Addr := Abx(PageCrossed); Y := Read(Addr); SetZN(Y); Cycles := 4 + Ord(PageCrossed); end;
    $BD: begin Addr := Abx(PageCrossed); A := Read(Addr); SetZN(A); Cycles := 4 + Ord(PageCrossed); end;
    $BE: begin Addr := Aby(PageCrossed); X := Read(Addr); SetZN(X); Cycles := 4 + Ord(PageCrossed); end;
    $BF: begin Addr := Aby(PageCrossed); LAXValue(Read(Addr)); Cycles := 4 + Ord(PageCrossed); end;
    $C0: begin Addr := Imm; CMP(Y, Read(Addr)); Cycles := 2; end;
    $C1: begin Addr := Izx; CMP(A, Read(Addr)); Cycles := 6; end;
    $C3: begin Addr := Izx; OpDCP(Addr); Cycles := 8; end;
    $C4: begin Addr := Zp0; CMP(Y, Read(Addr)); Cycles := 3; end;
    $C5: begin Addr := Zp0; CMP(A, Read(Addr)); Cycles := 3; end;
    $C6: begin Addr := Zp0; Value := Read(Addr); Dec(Value); Write(Addr, Value); SetZN(Value); Cycles := 5; end;
    $C7: begin Addr := Zp0; OpDCP(Addr); Cycles := 5; end;
    $C8: begin Inc(Y); SetZN(Y); Cycles := 2; end;
    $C9: begin Addr := Imm; CMP(A, Read(Addr)); Cycles := 2; end;
    $CA: begin Dec(X); SetZN(X); Cycles := 2; end;
    $CB: begin Addr := Imm; Value := Read(Addr); Carry := A and X; SetFlag(FLAG_CARRY, Carry >= Value); X := UInt8(Carry - Value); SetZN(X); Cycles := 2; end;
    $CC: begin Addr := AbsAddr; CMP(Y, Read(Addr)); Cycles := 4; end;
    $CD: begin Addr := AbsAddr; CMP(A, Read(Addr)); Cycles := 4; end;
    $CE: begin Addr := AbsAddr; Value := Read(Addr); Dec(Value); Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $CF: begin Addr := AbsAddr; OpDCP(Addr); Cycles := 6; end;
    $D0: begin Offset := Rel; Branch(not GetFlag(FLAG_ZERO), Offset, Cycles); end;
    $D1: begin Addr := Izy(PageCrossed); CMP(A, Read(Addr)); Cycles := 5 + Ord(PageCrossed); end;
    $D3: begin Addr := Izy(PageCrossed); OpDCP(Addr); Cycles := 8; end;
    $D5: begin Addr := Zpx; CMP(A, Read(Addr)); Cycles := 4; end;
    $D6: begin Addr := Zpx; Value := Read(Addr); Dec(Value); Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $D7: begin Addr := Zpx; OpDCP(Addr); Cycles := 6; end;
    $D8: begin SetFlag(FLAG_DECIMAL, False); Cycles := 2; end;
    $D9: begin Addr := Aby(PageCrossed); CMP(A, Read(Addr)); Cycles := 4 + Ord(PageCrossed); end;
    $DB: begin Addr := Aby(PageCrossed); OpDCP(Addr); Cycles := 7; end;
    $DD: begin Addr := Abx(PageCrossed); CMP(A, Read(Addr)); Cycles := 4 + Ord(PageCrossed); end;
    $DF: begin Addr := Abx(PageCrossed); OpDCP(Addr); Cycles := 7; end;
    $DE: begin Addr := Abx(PageCrossed); Value := Read(Addr); Dec(Value); Write(Addr, Value); SetZN(Value); Cycles := 7; end;
    $E0: begin Addr := Imm; CMP(X, Read(Addr)); Cycles := 2; end;
    $E1: begin Addr := Izx; SBC(Read(Addr)); Cycles := 6; end;
    $E3: begin Addr := Izx; OpISC(Addr); Cycles := 8; end;
    $E4: begin Addr := Zp0; CMP(X, Read(Addr)); Cycles := 3; end;
    $E5: begin Addr := Zp0; SBC(Read(Addr)); Cycles := 3; end;
    $E6: begin Addr := Zp0; Value := Read(Addr); Inc(Value); Write(Addr, Value); SetZN(Value); Cycles := 5; end;
    $E7: begin Addr := Zp0; OpISC(Addr); Cycles := 5; end;
    $E8: begin Inc(X); SetZN(X); Cycles := 2; end;
    $E9, $EB: begin Addr := Imm; SBC(Read(Addr)); Cycles := 2; end;
    $EA: begin Cycles := 2; end;
    $EC: begin Addr := AbsAddr; CMP(X, Read(Addr)); Cycles := 4; end;
    $ED: begin Addr := AbsAddr; SBC(Read(Addr)); Cycles := 4; end;
    $EE: begin Addr := AbsAddr; Value := Read(Addr); Inc(Value); Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $EF: begin Addr := AbsAddr; OpISC(Addr); Cycles := 6; end;
    $F0: begin Offset := Rel; Branch(GetFlag(FLAG_ZERO), Offset, Cycles); end;
    $F1: begin Addr := Izy(PageCrossed); SBC(Read(Addr)); Cycles := 5 + Ord(PageCrossed); end;
    $F3: begin Addr := Izy(PageCrossed); OpISC(Addr); Cycles := 8; end;
    $F5: begin Addr := Zpx; SBC(Read(Addr)); Cycles := 4; end;
    $F6: begin Addr := Zpx; Value := Read(Addr); Inc(Value); Write(Addr, Value); SetZN(Value); Cycles := 6; end;
    $F7: begin Addr := Zpx; OpISC(Addr); Cycles := 6; end;
    $F8: begin SetFlag(FLAG_DECIMAL, True); Cycles := 2; end;
    $F9: begin Addr := Aby(PageCrossed); SBC(Read(Addr)); Cycles := 4 + Ord(PageCrossed); end;
    $FB: begin Addr := Aby(PageCrossed); OpISC(Addr); Cycles := 7; end;
    $FD: begin Addr := Abx(PageCrossed); SBC(Read(Addr)); Cycles := 4 + Ord(PageCrossed); end;
    $FF: begin Addr := Abx(PageCrossed); OpISC(Addr); Cycles := 7; end;
    $FE: begin Addr := Abx(PageCrossed); Value := Read(Addr); Inc(Value); Write(Addr, Value); SetZN(Value); Cycles := 7; end;
  else
    begin
      Inc(FUnknownOpcodeCount);
      FLastUnknownOpcode := Opcode;
      FLastUnknownPC := OpPC;
      Cycles := 2;
    end;
  end;
  CyclesRemaining := Cycles;
end;

end.


































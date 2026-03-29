unit NES.APU;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
{$IFDEF FPC}
  Math,
{$ELSE}
  System.Math,
{$ENDIF}
  NES.Types;

type
  TPulseChannel = record
    Reg0: UInt8;
    Reg1: UInt8;
    Reg2: UInt8;
    Reg3: UInt8;
    Enabled: Boolean;
    LengthCounter: Integer;
    TimerReload: Integer;
    Timer: Integer;
    SequenceStep: Integer;
    EnvelopeStart: Boolean;
    EnvelopeDivider: Integer;
    EnvelopeDecay: Integer;
    SweepReload: Boolean;
    SweepDivider: Integer;
  end;

  TTriangleChannel = record
    Reg0: UInt8;
    Reg2: UInt8;
    Reg3: UInt8;
    Enabled: Boolean;
    LengthCounter: Integer;
    TimerReload: Integer;
    Timer: Integer;
    SequenceStep: Integer;
    LinearCounter: Integer;
    LinearReloadFlag: Boolean;
  end;

  TNoiseChannel = record
    Reg0: UInt8;
    Reg2: UInt8;
    Reg3: UInt8;
    Enabled: Boolean;
    LengthCounter: Integer;
    TimerReload: Integer;
    Timer: Integer;
    Shift: UInt16;
    EnvelopeStart: Boolean;
    EnvelopeDivider: Integer;
    EnvelopeDecay: Integer;
  end;

  TAPU = class
  private
    FPulse1: TPulseChannel;
    FPulse2: TPulseChannel;
    FTriangle: TTriangleChannel;
    FNoise: TNoiseChannel;
    FCycle: UInt32;
    FFrameCounter: UInt32;
    FFrameMode5: Boolean;
    FFrameIrqInhibit: Boolean;
    FPendingFrameMode5: Boolean;
    FPendingFrameIrqInhibit: Boolean;
    FFrameResetDelay: Integer;
    FFrameIrqFlag: Boolean;
    FFrameIrqRepeat: Integer;
    FSampleRate: Integer;
    FSampleTimer: Double;
    FSampleStep: Double;
    FBuffer: array of SmallInt;
    FWritePos: Integer;
    FReadPos: Integer;
    FCount: Integer;
    FWriteCounts: array[$4000..$4017] of Integer;
    FHP90Out: Double;
    FHP90In: Double;
    FHP440Out: Double;
    FHP440In: Double;
    FLP14Out: Double;
    FHP90Coef: Double;
    FHP440Coef: Double;
    FLP14Coef: Double;
    function LengthFromIndex(Index: UInt8): Integer;
    function PulseSweepTarget(const Channel: TPulseChannel; NegateExtra: Integer): Integer;
    function PulseVolume(const Channel: TPulseChannel): Integer;
    function NoiseVolume: Integer;
    function PulseRawOutput(const Channel: TPulseChannel; NegateExtra: Integer): Integer;
    function TriangleRawOutput: Integer;
    function NoiseRawOutput: Integer;
    procedure ClockPulseEnvelope(var Channel: TPulseChannel);
    procedure ClockNoiseEnvelope;
    procedure ClockLinearCounter;
    procedure ClockLengthCounters;
    procedure ClockSweep(var Channel: TPulseChannel; NegateExtra: Integer);
    procedure QuarterFrame;
    procedure HalfFrame;
    procedure PushSample(Value: SmallInt);
    function MixSample: Double;
    function FilterSample(Value: Double): Double;
  public
    constructor Create;
    procedure Reset;
    procedure SetSampleRate(Value: Integer);
    procedure CpuWrite(Address: UInt16; Value: UInt8);
    function CpuReadStatus: UInt8;
    function IrqPending: Boolean;
    procedure Clock;
    function PopSamples(Dest: Pointer; MaxSamples: Integer): Integer;
    function DebugStatus: UInt8;
    function DebugPulse1Reg0: UInt8;
    function DebugPulse1Length: Integer;
    function DebugPulse2Length: Integer;
    function DebugTriangleLength: Integer;
    function DebugNoiseLength: Integer;
    function DebugWriteCount(Address: UInt16): Integer;
    function DebugCycle: UInt32;
    function DebugFrameCounter: UInt32;
    function DebugFrameIrqFlag: Boolean;
  end;

implementation

const
  LENGTH_TABLE: array[0..31] of Integer = (
    10, 254, 20,  2, 40,  4, 80,  6,
    160, 8, 60, 10, 14, 12, 26, 14,
    12, 16, 24, 18, 48, 20, 96, 22,
    192,24, 72, 26, 16, 28, 32, 30
  );
  DUTY_TABLE: array[0..3, 0..7] of Integer = (
    (0,1,0,0,0,0,0,0),
    (0,1,1,0,0,0,0,0),
    (0,1,1,1,1,0,0,0),
    (1,0,0,1,1,1,1,1)
  );
  TRI_TABLE: array[0..31] of Integer = (
    15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0,
    0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
  );
  NOISE_PERIOD_TABLE: array[0..15] of Integer = (4,8,16,32,64,96,128,160,202,254,380,508,762,1016,2034,4068);

constructor TAPU.Create;
begin
  inherited Create;
  SetSampleRate(44100);
  SetLength(FBuffer, 16384);
  Reset;
end;

procedure TAPU.Reset;
begin
  FillChar(FPulse1, SizeOf(FPulse1), 0);
  FillChar(FPulse2, SizeOf(FPulse2), 0);
  FillChar(FTriangle, SizeOf(FTriangle), 0);
  FillChar(FNoise, SizeOf(FNoise), 0);
  FNoise.Shift := 1;
  FCycle := 0;
  FFrameCounter := 0;
  FFrameMode5 := False;
  FFrameIrqInhibit := False;
  FPendingFrameMode5 := False;
  FPendingFrameIrqInhibit := False;
  FFrameResetDelay := 0;
  FFrameIrqFlag := False;
  FFrameIrqRepeat := 0;
  FSampleTimer := 0;
  FWritePos := 0;
  FReadPos := 0;
  FCount := 0;
  FillChar(FWriteCounts, SizeOf(FWriteCounts), 0);
  FHP90Out := 0;
  FHP90In := 0;
  FHP440Out := 0;
  FHP440In := 0;
  FLP14Out := 0;
end;

procedure TAPU.SetSampleRate(Value: Integer);
var
  Dt: Double;
  Rc: Double;
begin
  if Value <= 0 then
    Value := 44100;
  FSampleRate := Value;
  FSampleStep := 1789773.0 / FSampleRate;
  Dt := 1.0 / FSampleRate;
  Rc := 1.0 / (2.0 * Pi * 90.0);
  FHP90Coef := Rc / (Rc + Dt);
  Rc := 1.0 / (2.0 * Pi * 440.0);
  FHP440Coef := Rc / (Rc + Dt);
  Rc := 1.0 / (2.0 * Pi * 14000.0);
  FLP14Coef := Dt / (Rc + Dt);
end;

function TAPU.LengthFromIndex(Index: UInt8): Integer;
begin
  Result := LENGTH_TABLE[Index and 31];
end;

function TAPU.PulseSweepTarget(const Channel: TPulseChannel; NegateExtra: Integer): Integer;
var
  Change: Integer;
begin
  Change := Channel.TimerReload shr (Channel.Reg1 and 7);
  if (Channel.Reg1 and $08) <> 0 then
    Result := Channel.TimerReload - Change - NegateExtra
  else
    Result := Channel.TimerReload + Change;
end;

function TAPU.PulseVolume(const Channel: TPulseChannel): Integer;
begin
  if (Channel.Reg0 and $10) <> 0 then
    Result := Channel.Reg0 and $0F
  else
    Result := Channel.EnvelopeDecay;
end;

function TAPU.NoiseVolume: Integer;
begin
  if (FNoise.Reg0 and $10) <> 0 then
    Result := FNoise.Reg0 and $0F
  else
    Result := FNoise.EnvelopeDecay;
end;

function TAPU.PulseRawOutput(const Channel: TPulseChannel; NegateExtra: Integer): Integer;
var
  Duty: Integer;
  SweepTarget: Integer;
begin
  Result := 0;
  if not Channel.Enabled or (Channel.LengthCounter = 0) then Exit;
  if Channel.TimerReload < 8 then Exit;
  if ((Channel.Reg1 and $80) <> 0) and ((Channel.Reg1 and 7) <> 0) then
  begin
    SweepTarget := PulseSweepTarget(Channel, NegateExtra);
    if (SweepTarget < 0) or (SweepTarget > $7FF) then Exit;
  end;
  Duty := (Channel.Reg0 shr 6) and 3;
  if DUTY_TABLE[Duty, Channel.SequenceStep and 7] = 0 then Exit;
  Result := PulseVolume(Channel);
end;

function TAPU.TriangleRawOutput: Integer;
begin
  Result := 0;
  if not FTriangle.Enabled then Exit;
  if (FTriangle.LengthCounter = 0) or (FTriangle.LinearCounter = 0) then Exit;
  if FTriangle.TimerReload < 2 then Exit;
  Result := TRI_TABLE[FTriangle.SequenceStep and 31];
end;

function TAPU.NoiseRawOutput: Integer;
begin
  Result := 0;
  if not FNoise.Enabled or (FNoise.LengthCounter = 0) then Exit;
  if (FNoise.Shift and 1) <> 0 then Exit;
  Result := NoiseVolume;
end;

procedure TAPU.ClockPulseEnvelope(var Channel: TPulseChannel);
begin
  if Channel.EnvelopeStart then
  begin
    Channel.EnvelopeStart := False;
    Channel.EnvelopeDecay := 15;
    Channel.EnvelopeDivider := (Channel.Reg0 and $0F) + 1;
  end
  else if Channel.EnvelopeDivider > 0 then
    Dec(Channel.EnvelopeDivider)
  else
  begin
    Channel.EnvelopeDivider := (Channel.Reg0 and $0F) + 1;
    if Channel.EnvelopeDecay > 0 then
      Dec(Channel.EnvelopeDecay)
    else if (Channel.Reg0 and $20) <> 0 then
      Channel.EnvelopeDecay := 15;
  end;
end;

procedure TAPU.ClockNoiseEnvelope;
begin
  if FNoise.EnvelopeStart then
  begin
    FNoise.EnvelopeStart := False;
    FNoise.EnvelopeDecay := 15;
    FNoise.EnvelopeDivider := (FNoise.Reg0 and $0F) + 1;
  end
  else if FNoise.EnvelopeDivider > 0 then
    Dec(FNoise.EnvelopeDivider)
  else
  begin
    FNoise.EnvelopeDivider := (FNoise.Reg0 and $0F) + 1;
    if FNoise.EnvelopeDecay > 0 then
      Dec(FNoise.EnvelopeDecay)
    else if (FNoise.Reg0 and $20) <> 0 then
      FNoise.EnvelopeDecay := 15;
  end;
end;

procedure TAPU.ClockLinearCounter;
begin
  if FTriangle.LinearReloadFlag then
    FTriangle.LinearCounter := FTriangle.Reg0 and $7F
  else if FTriangle.LinearCounter > 0 then
    Dec(FTriangle.LinearCounter);

  if (FTriangle.Reg0 and $80) = 0 then
    FTriangle.LinearReloadFlag := False;
end;

procedure TAPU.ClockLengthCounters;
begin
  if FPulse1.Enabled and (FPulse1.LengthCounter > 0) and ((FPulse1.Reg0 and $20) = 0) then Dec(FPulse1.LengthCounter);
  if FPulse2.Enabled and (FPulse2.LengthCounter > 0) and ((FPulse2.Reg0 and $20) = 0) then Dec(FPulse2.LengthCounter);
  if FTriangle.Enabled and (FTriangle.LengthCounter > 0) and ((FTriangle.Reg0 and $80) = 0) then Dec(FTriangle.LengthCounter);
  if FNoise.Enabled and (FNoise.LengthCounter > 0) and ((FNoise.Reg0 and $20) = 0) then Dec(FNoise.LengthCounter);
end;

procedure TAPU.ClockSweep(var Channel: TPulseChannel; NegateExtra: Integer);
var
  NewPeriod: Integer;
  DividerPeriod: Integer;
begin
  DividerPeriod := ((Channel.Reg1 shr 4) and 7) + 1;
  if Channel.SweepReload then
  begin
    Channel.SweepReload := False;
    Channel.SweepDivider := DividerPeriod;
  end
  else if Channel.SweepDivider > 0 then
    Dec(Channel.SweepDivider)
  else
  begin
    Channel.SweepDivider := DividerPeriod;
    if ((Channel.Reg1 and $80) <> 0) and ((Channel.Reg1 and 7) <> 0) then
    begin
      NewPeriod := PulseSweepTarget(Channel, NegateExtra);
      if (Channel.TimerReload >= 8) and (NewPeriod <= $7FF) and (NewPeriod >= 0) then
        Channel.TimerReload := NewPeriod;
    end;
  end;
end;

procedure TAPU.QuarterFrame;
begin
  ClockPulseEnvelope(FPulse1);
  ClockPulseEnvelope(FPulse2);
  ClockNoiseEnvelope;
  ClockLinearCounter;
end;

procedure TAPU.HalfFrame;
begin
  ClockLengthCounters;
  ClockSweep(FPulse1, 1);
  ClockSweep(FPulse2, 0);
end;

procedure TAPU.CpuWrite(Address: UInt16; Value: UInt8);
begin
  if (Address >= $4000) and (Address <= $4017) then
    Inc(FWriteCounts[Address]);

  case Address of
    $4000:
      begin
        FPulse1.Reg0 := Value;
        FPulse1.EnvelopeStart := True;
      end;
    $4001:
      begin
        FPulse1.Reg1 := Value;
        FPulse1.SweepReload := True;
      end;
    $4002:
      begin
        FPulse1.Reg2 := Value;
        FPulse1.TimerReload := ((FPulse1.Reg3 and 7) shl 8) or FPulse1.Reg2;
      end;
    $4003:
      begin
        FPulse1.Reg3 := Value;
        FPulse1.TimerReload := ((FPulse1.Reg3 and 7) shl 8) or FPulse1.Reg2;
        if FPulse1.Enabled then FPulse1.LengthCounter := LengthFromIndex(Value shr 3);
        FPulse1.SequenceStep := 0;
        FPulse1.EnvelopeStart := True;
      end;
    $4004:
      begin
        FPulse2.Reg0 := Value;
        FPulse2.EnvelopeStart := True;
      end;
    $4005:
      begin
        FPulse2.Reg1 := Value;
        FPulse2.SweepReload := True;
      end;
    $4006:
      begin
        FPulse2.Reg2 := Value;
        FPulse2.TimerReload := ((FPulse2.Reg3 and 7) shl 8) or FPulse2.Reg2;
      end;
    $4007:
      begin
        FPulse2.Reg3 := Value;
        FPulse2.TimerReload := ((FPulse2.Reg3 and 7) shl 8) or FPulse2.Reg2;
        if FPulse2.Enabled then FPulse2.LengthCounter := LengthFromIndex(Value shr 3);
        FPulse2.SequenceStep := 0;
        FPulse2.EnvelopeStart := True;
      end;
    $4008:
      FTriangle.Reg0 := Value;
    $400A:
      begin
        FTriangle.Reg2 := Value;
        FTriangle.TimerReload := ((FTriangle.Reg3 and 7) shl 8) or FTriangle.Reg2;
      end;
    $400B:
      begin
        FTriangle.Reg3 := Value;
        FTriangle.TimerReload := ((FTriangle.Reg3 and 7) shl 8) or FTriangle.Reg2;
        if FTriangle.Enabled then FTriangle.LengthCounter := LengthFromIndex(Value shr 3);
        FTriangle.LinearReloadFlag := True;
      end;
    $400C:
      begin
        FNoise.Reg0 := Value;
        FNoise.EnvelopeStart := True;
      end;
    $400E:
      begin
        FNoise.Reg2 := Value;
        FNoise.TimerReload := NOISE_PERIOD_TABLE[Value and $0F];
      end;
    $400F:
      begin
        FNoise.Reg3 := Value;
        if FNoise.Enabled then FNoise.LengthCounter := LengthFromIndex(Value shr 3);
        FNoise.EnvelopeStart := True;
      end;
    $4015:
      begin
        FPulse1.Enabled := (Value and $01) <> 0; if not FPulse1.Enabled then FPulse1.LengthCounter := 0;
        FPulse2.Enabled := (Value and $02) <> 0; if not FPulse2.Enabled then FPulse2.LengthCounter := 0;
        FTriangle.Enabled := (Value and $04) <> 0; if not FTriangle.Enabled then FTriangle.LengthCounter := 0;
        FNoise.Enabled := (Value and $08) <> 0; if not FNoise.Enabled then FNoise.LengthCounter := 0;
      end;
    $4017:
      begin
        FPendingFrameMode5 := (Value and $80) <> 0;
        FPendingFrameIrqInhibit := (Value and $40) <> 0;
        if FPendingFrameIrqInhibit then
        begin
          FFrameIrqInhibit := True;
          FFrameIrqFlag := False;
          FFrameIrqRepeat := 0;
        end;
        if (FCycle and 1) = 0 then
          FFrameResetDelay := 3
        else
          FFrameResetDelay := 4;
      end;
  end;
end;

function TAPU.CpuReadStatus: UInt8;
begin
  Result := 0;
  if FPulse1.LengthCounter > 0 then Result := Result or $01;
  if FPulse2.LengthCounter > 0 then Result := Result or $02;
  if FTriangle.LengthCounter > 0 then Result := Result or $04;
  if FNoise.LengthCounter > 0 then Result := Result or $08;
  if FFrameIrqFlag then Result := Result or $40;
  FFrameIrqFlag := False;
end;

function TAPU.IrqPending: Boolean;
begin
  Result := FFrameIrqFlag and (not FFrameIrqInhibit);
end;

function TAPU.FilterSample(Value: Double): Double;
begin
  FHP90Out := FHP90Coef * (FHP90Out + Value - FHP90In);
  FHP90In := Value;
  FHP440Out := FHP440Coef * (FHP440Out + FHP90Out - FHP440In);
  FHP440In := FHP90Out;
  FLP14Out := FLP14Out + FLP14Coef * (FHP440Out - FLP14Out);
  Result := FLP14Out;
end;
function TAPU.MixSample: Double;
var
  P1, P2, Tri, Noi: Integer;
  PulseMix, TndMix: Double;
  PulseDenom: Double;
  TndInput: Double;
  TndDenom: Double;
begin
  P1 := PulseRawOutput(FPulse1, 1);
  P2 := PulseRawOutput(FPulse2, 0);
  Tri := TriangleRawOutput;
  Noi := NoiseRawOutput;

  if (P1 + P2) = 0 then
    PulseMix := 0
  else
  begin
    PulseDenom := (8128.0 / (P1 + P2)) + 100.0;
    if PulseDenom <= 0 then
      PulseMix := 0
    else
      PulseMix := 95.88 / PulseDenom;
  end;

  if (Tri = 0) and (Noi = 0) then
    TndMix := 0
  else
  begin
    TndInput := (Tri / 8227.0) + (Noi / 12241.0);
    if TndInput <= 0 then
      TndMix := 0
    else
    begin
      TndDenom := (1.0 / TndInput) + 100.0;
      if TndDenom <= 0 then
        TndMix := 0
      else
        TndMix := 159.79 / TndDenom;
    end;
  end;

  Result := PulseMix + TndMix;
  if IsNan(Result) or IsInfinite(Result) then
    Result := 0;
  if Result < 0 then Result := 0;
  if Result > 1 then Result := 1;
end;
procedure TAPU.PushSample(Value: SmallInt);
begin
  if FCount >= Length(FBuffer) then
  begin
    FReadPos := (FReadPos + 1) mod Length(FBuffer);
    Dec(FCount);
  end;
  FBuffer[FWritePos] := Value;
  FWritePos := (FWritePos + 1) mod Length(FBuffer);
  Inc(FCount);
end;

procedure TAPU.Clock;
var
  Feedback: UInt16;
  Sample: Double;
begin
  Inc(FCycle);

  if FFrameResetDelay > 0 then
  begin
    Dec(FFrameResetDelay);
    if FFrameResetDelay = 0 then
    begin
      FFrameMode5 := FPendingFrameMode5;
      FFrameIrqInhibit := FPendingFrameIrqInhibit;
      FFrameCounter := 0;
      if FFrameMode5 then
      begin
        QuarterFrame;
        HalfFrame;
      end;
    end;
  end;

  Inc(FFrameCounter);

  if not FFrameMode5 then
  begin
    case FFrameCounter of
      7457, 22371: QuarterFrame;
      14913: begin QuarterFrame; HalfFrame; end;
      29829:
        begin
          QuarterFrame;
          HalfFrame;
          if not FFrameIrqInhibit then
            FFrameIrqFlag := True;
          FFrameCounter := 0;
        end;
    end;
  end
  else
  begin
    case FFrameCounter of
      7457, 22371: QuarterFrame;
      14913, 37281:
        begin
          QuarterFrame;
          HalfFrame;
        end;
      37282: FFrameCounter := 0;
    end;
  end;

  if (FCycle and 1) = 0 then
  begin
    if FPulse1.Timer <= 0 then
    begin
      FPulse1.Timer := FPulse1.TimerReload;
      FPulse1.SequenceStep := (FPulse1.SequenceStep + 1) and 7;
    end
    else
      Dec(FPulse1.Timer);

    if FPulse2.Timer <= 0 then
    begin
      FPulse2.Timer := FPulse2.TimerReload;
      FPulse2.SequenceStep := (FPulse2.SequenceStep + 1) and 7;
    end
    else
      Dec(FPulse2.Timer);

    if FNoise.Timer <= 0 then
    begin
      FNoise.Timer := FNoise.TimerReload;
      if (FNoise.Reg2 and $80) <> 0 then
        Feedback := ((FNoise.Shift and 1) xor ((FNoise.Shift shr 6) and 1))
      else
        Feedback := ((FNoise.Shift and 1) xor ((FNoise.Shift shr 1) and 1));
      FNoise.Shift := (FNoise.Shift shr 1) or (Feedback shl 14);
    end
    else
      Dec(FNoise.Timer);
  end;

  if FTriangle.Timer <= 0 then
  begin
    FTriangle.Timer := FTriangle.TimerReload;
    if (FTriangle.LengthCounter > 0) and (FTriangle.LinearCounter > 0) then
      FTriangle.SequenceStep := (FTriangle.SequenceStep + 1) and 31;
  end
  else
    Dec(FTriangle.Timer);

  FSampleTimer := FSampleTimer + 1.0;
  while FSampleTimer >= FSampleStep do
  begin
    FSampleTimer := FSampleTimer - FSampleStep;
    Sample := FilterSample(MixSample);
    if IsNan(Sample) or IsInfinite(Sample) then
      Sample := 0;
    if Sample > 1 then Sample := 1 else if Sample < -1 then Sample := -1;
    PushSample(Round(Sample * 16000));
  end;
end;

function TAPU.PopSamples(Dest: Pointer; MaxSamples: Integer): Integer;
var
  OutBuf: ^SmallInt;
  I: Integer;
begin
  Result := 0;
  OutBuf := Dest;
  for I := 0 to MaxSamples - 1 do
  begin
    if FCount = 0 then Break;
    OutBuf^ := FBuffer[FReadPos];
    Inc(OutBuf);
    FReadPos := (FReadPos + 1) mod Length(FBuffer);
    Dec(FCount);
    Inc(Result);
  end;
end;

function TAPU.DebugStatus: UInt8;
begin
  Result := CpuReadStatus;
end;

function TAPU.DebugPulse1Reg0: UInt8;
begin
  Result := FPulse1.Reg0;
end;

function TAPU.DebugPulse1Length: Integer;
begin
  Result := FPulse1.LengthCounter;
end;

function TAPU.DebugPulse2Length: Integer;
begin
  Result := FPulse2.LengthCounter;
end;

function TAPU.DebugTriangleLength: Integer;
begin
  Result := FTriangle.LengthCounter;
end;

function TAPU.DebugNoiseLength: Integer;
begin
  Result := FNoise.LengthCounter;
end;

function TAPU.DebugWriteCount(Address: UInt16): Integer;
begin
  if (Address >= $4000) and (Address <= $4017) then
    Result := FWriteCounts[Address]
  else
    Result := 0;
end;

function TAPU.DebugCycle: UInt32;
begin
  Result := FCycle;
end;

function TAPU.DebugFrameCounter: UInt32;
begin
  Result := FFrameCounter;
end;

function TAPU.DebugFrameIrqFlag: Boolean;
begin
  Result := FFrameIrqFlag;
end;

end.





















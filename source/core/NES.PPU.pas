unit NES.PPU;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  NES.Types,
  NES.Consts,
  NES.Mapper;

type
  TPPU = class
  private
    FMapper: TMapper;
    FNameTable: array[0..2047] of UInt8;
    FPaletteRam: array[0..31] of UInt8;
    FOAM: array[0..255] of UInt8;
    FFrame: TFrameBuffer;
    FCycle: Integer;
    FScanline: Integer;
    FFrameReady: Boolean;
    FFrameOdd: Boolean;
    FCtrl: UInt8;
    FMask: UInt8;
    FStatus: UInt8;
    FOAMAddr: UInt8;
    FAddrLatch: Boolean;
    FFineX: UInt8;
    FV: UInt16;
    FT: UInt16;
    FDataBuffer: UInt8;
    FOpenBus: UInt8;
    FNmiOccurred: Boolean;
    FNmiPending: Boolean;
    FNmiDelay: Integer;
    FNmiLine: Boolean;
    FVblSetSuppressed: Boolean;
    FOddFrameSkipEnabled: Boolean;
    FRenderV: UInt16;
    FRenderCtrl: UInt8;
    FRenderMask: UInt8;
    FRenderFineX: UInt8;
    FSplitActive: Boolean;
    FSplitY: Integer;
    FSplitV: UInt16;
    FSplitCtrl: UInt8;
    FSplitFineX: UInt8;
    FSplitMask: UInt8;
    FPreferredBaseNT: Integer;
    FSprite0HitX: Integer;
    FSprite0HitY: Integer;
    procedure IncrementX;
    procedure IncrementY;
    procedure CopyX;
    procedure CopyY;
    function MirrorNameTableAddress(Address: UInt16): UInt16;
    function PpuReadMemory(Address: UInt16): UInt8;
    procedure PpuWriteMemory(Address: UInt16; Value: UInt8);
    procedure SetVBlank(Value: Boolean);
    procedure UpdateNmiState;
    procedure CaptureSplitState;
    function SampleBackgroundPixel(X, Y: Integer; out PaletteIndex: UInt8): UInt8;
    function SampleSpritePixel(X, Y: Integer; out PaletteIndex: UInt8; out PriorityBehindBg: Boolean; out IsSpriteZero: Boolean): UInt8;
    function SampleSpriteZeroPixel(X, Y: Integer): UInt8;
    procedure UpdateSpriteZeroHit;
    procedure RenderFullFrame;
  public
    constructor Create;
    procedure ConnectMapper(AMapper: TMapper);
    procedure Reset;
    procedure Clock;
    function CpuRead(Address: UInt16): UInt8;
    procedure CpuWrite(Address: UInt16; Value: UInt8);
    procedure WriteOAMDMA(Index: Integer; Value: UInt8);
    function ConsumeNmi: Boolean;
    procedure RebuildFrame;
    function DebugReadMemory(Address: UInt16): UInt8;
    function DebugMask: UInt8;
    function DebugCtrl: UInt8;
    function DebugStatus: UInt8;
    function DebugV: UInt16;
    function DebugT: UInt16;
    function DebugBackgroundPixel(X, Y: Integer): UInt8;
    function DebugOAM(Index: Integer): UInt8;
    function DebugSprite0HitX: Integer;
    function DebugSprite0HitY: Integer;
    function DebugSplitActive: Boolean;
    function DebugSplitY: Integer;

    property FrameReady: Boolean read FFrameReady write FFrameReady;
    property Frame: TFrameBuffer read FFrame;
    property Cycle: Integer read FCycle;
    property Scanline: Integer read FScanline;
  end;

implementation

constructor TPPU.Create;
begin
  inherited Create;
  Reset;
end;

procedure TPPU.ConnectMapper(AMapper: TMapper);
begin
  FMapper := AMapper;
end;

procedure TPPU.Reset;
var
  I: Integer;
begin
  FCycle := 0;
  FScanline := 261;
  FFrameReady := False;
  FFrameOdd := False;
  FCtrl := 0;
  FMask := 0;
  FStatus := 0;
  FOAMAddr := 0;
  FAddrLatch := False;
  FFineX := 0;
  FV := 0;
  FT := 0;
  FDataBuffer := 0;
  FOpenBus := 0;
  FNmiOccurred := False;
  FNmiPending := False;
  FNmiDelay := 0;
  FNmiLine := False;
  FVblSetSuppressed := False;
  FOddFrameSkipEnabled := False;
  FRenderV := 0;
  FRenderCtrl := 0;
  FRenderMask := 0;
  FRenderFineX := 0;
  FSplitActive := False;
  FSplitY := 240;
  FSplitV := 0;
  FSplitCtrl := 0;
  FSplitFineX := 0;
  FSplitMask := 0;
  FPreferredBaseNT := -1;
  FSprite0HitX := -1;
  FSprite0HitY := -1;
  for I := Low(FNameTable) to High(FNameTable) do FNameTable[I] := 0;
  for I := Low(FPaletteRam) to High(FPaletteRam) do FPaletteRam[I] := 0;
  for I := Low(FOAM) to High(FOAM) do FOAM[I] := 0;
end;

procedure TPPU.IncrementX;
begin
  if (FV and $001F) = 31 then
  begin
    FV := FV and not UInt16($001F);
    FV := FV xor $0400;
  end
  else
    FV := FV + 1;
end;

procedure TPPU.IncrementY;
var
  Y: UInt16;
begin
  if (FV and $7000) <> $7000 then
    FV := FV + $1000
  else
  begin
    FV := FV and not UInt16($7000);
    Y := (FV and $03E0) shr 5;
    if Y = 29 then
    begin
      Y := 0;
      FV := FV xor $0800;
    end
    else if Y = 31 then
      Y := 0
    else
      Inc(Y);
    FV := (FV and not UInt16($03E0)) or (Y shl 5);
  end;
end;

procedure TPPU.CopyX;
begin
  FV := (FV and not UInt16($041F)) or (FT and $041F);
end;

procedure TPPU.CopyY;
begin
  FV := (FV and not UInt16($7BE0)) or (FT and $7BE0);
end;

function TPPU.MirrorNameTableAddress(Address: UInt16): UInt16;
var
  Index, TableIndex: UInt16;
begin
  Index := (Address - $2000) and $0FFF;
  TableIndex := Index shr 10;
  if FMapper = nil then
    Exit(Index and $07FF);

  case FMapper.GetMirrorMode of
    mmVertical:
      case TableIndex of
        0, 2: Result := Index and $03FF;
      else
        Result := $0400 + (Index and $03FF);
      end;
    mmHorizontal:
      case TableIndex of
        0, 1: Result := Index and $03FF;
      else
        Result := $0400 + (Index and $03FF);
      end;
    mmSingle0:
      Result := Index and $03FF;
    mmSingle1:
      Result := $0400 + (Index and $03FF);
    mmFourScreen:
      Result := Index and $07FF;
  else
    Result := Index and $07FF;
  end;
end;

function TPPU.PpuReadMemory(Address: UInt16): UInt8;
var
  Temp: UInt8;
  PalAddr: UInt16;
begin
  Address := Address and $3FFF;
  if (Address < $2000) and (FMapper <> nil) and FMapper.PpuRead(Address, Temp) then
    Exit(Temp);
  if Address < $3F00 then
    Exit(FNameTable[MirrorNameTableAddress(Address)]);

  PalAddr := (Address - $3F00) and $1F;
  case PalAddr of
    $10: PalAddr := 0;
    $14: PalAddr := 4;
    $18: PalAddr := 8;
    $1C: PalAddr := 12;
  end;
  Result := FPaletteRam[PalAddr] and $3F;
end;

procedure TPPU.PpuWriteMemory(Address: UInt16; Value: UInt8);
var
  PalAddr: UInt16;
begin
  Address := Address and $3FFF;
  if (Address < $2000) and (FMapper <> nil) and FMapper.PpuWrite(Address, Value) then
    Exit;
  if Address < $3F00 then
  begin
    FNameTable[MirrorNameTableAddress(Address)] := Value;
    Exit;
  end;

  PalAddr := (Address - $3F00) and $1F;
  case PalAddr of
    $10: PalAddr := 0;
    $14: PalAddr := 4;
    $18: PalAddr := 8;
    $1C: PalAddr := 12;
  end;
  FPaletteRam[PalAddr] := Value and $3F;
end;

procedure TPPU.UpdateNmiState;
var
  NewLine: Boolean;
begin
  NewLine := FNmiOccurred and ((FCtrl and $80) <> 0);
  if NewLine and not FNmiLine then
    FNmiDelay := 8
  else if not NewLine then
  begin
    if (FNmiDelay > 0) and (FNmiDelay <= 6) then
      FNmiPending := True;
    FNmiDelay := 0;
  end;
  FNmiLine := NewLine;
end;
procedure TPPU.CaptureSplitState;
begin
  if (FScanline < 0) or (FScanline >= 240) then
    Exit;
  if not FSplitActive then
  begin
    FSplitActive := True;
    FSplitY := FScanline;
  end;
  FSplitV := FT;
  FSplitCtrl := FCtrl;
  FSplitFineX := FFineX;
  FSplitMask := FMask;
end;

procedure TPPU.SetVBlank(Value: Boolean);
begin
  if Value then
  begin
    if FVblSetSuppressed then
    begin
      FVblSetSuppressed := False;
    FOddFrameSkipEnabled := False;
      FNmiOccurred := False;
      FNmiPending := False;
      FNmiDelay := 0;
      FNmiLine := False;
      Exit;
    end;
    FStatus := FStatus or $80;
    FNmiOccurred := True;
  end
  else
  begin
    FStatus := FStatus and not $80;
    FNmiOccurred := False;
  end;
  UpdateNmiState;
end;

procedure TPPU.Clock;
var
  RenderingEnabled: Boolean;
begin
  RenderingEnabled := (FMask and $18) <> 0;

  if FNmiDelay > 0 then
  begin
    Dec(FNmiDelay);
    if (FNmiDelay = 0) and FNmiLine then
      FNmiPending := True;
  end;

  if (FSprite0HitX >= 0) and (FSprite0HitY >= 0) then
    if (FScanline = FSprite0HitY) and (FCycle = FSprite0HitX + 1) then
      FStatus := FStatus or $40;

  if RenderingEnabled then
  begin
    if (((FScanline >= 0) and (FScanline < 240)) or (FScanline = 261)) then
    begin
      if (((FCycle >= 1) and (FCycle <= 256)) or ((FCycle >= 321) and (FCycle <= 336))) and (((FCycle - 1) mod 8) = 7) then
        IncrementX;
      if FCycle = 256 then
        IncrementY;
      if FCycle = 257 then
        CopyX;
      if (FScanline = 261) and (FCycle = 339) then
        FOddFrameSkipEnabled := RenderingEnabled;
      if (FScanline = 261) and (FCycle >= 280) and (FCycle <= 304) then
        CopyY;
    end;
  end;

  if (FScanline = 241) and (FCycle = 1) then
    SetVBlank(True);

  if (FScanline = 261) and (FCycle = 1) then
  begin
    FVblSetSuppressed := False;
    FOddFrameSkipEnabled := False;
    SetVBlank(False);
    FStatus := FStatus and not $40;
    FStatus := FStatus and not $20;
    FFrameReady := False;
  end;

  if FOddFrameSkipEnabled and FFrameOdd and (FScanline = 261) and (FCycle = 339) then
    FCycle := 340;

  Inc(FCycle);

  if FCycle > 340 then
  begin
    FCycle := 0;
    Inc(FScanline);
    if FScanline > 261 then
    begin
      FScanline := 0;
      FFrameReady := True;
      FFrameOdd := not FFrameOdd;
      FRenderV := FV;
      FRenderCtrl := FCtrl;
      FRenderMask := FMask;
      FRenderFineX := FFineX;
      UpdateSpriteZeroHit;
    end;
  end;
end;

function TPPU.CpuRead(Address: UInt16): UInt8;
var
  Addr: UInt16;
begin
  Result := FOpenBus;
  case Address and 7 of
    2:
      begin
        Result := (FStatus and $E0) or (FOpenBus and $1F);
        if ((Result and $80) = 0) and (FScanline = 241) and (FCycle = 1) then
        begin
          FVblSetSuppressed := True;
          FNmiPending := False;
        end;
        FStatus := FStatus and not $80;
        if (Result and $80) = 0 then
          FNmiPending := False
        else if (FNmiDelay > 0) and (FNmiDelay <= 6) then
          FNmiPending := True;
        FNmiOccurred := False;
        FNmiDelay := 0;
        FNmiLine := False;
        FAddrLatch := False;
      end;
    4:
      Result := FOAM[FOAMAddr];
    7:
      begin
        Addr := FV;
        if Addr < $3F00 then
        begin
          Result := FDataBuffer;
          FDataBuffer := PpuReadMemory(Addr);
        end
        else
        begin
          Result := PpuReadMemory(Addr);
          FDataBuffer := PpuReadMemory(Addr - $1000);
        end;
        if (FCtrl and $04) <> 0 then
          FV := FV + 32
        else
          FV := FV + 1;
      end;
  end;
  FOpenBus := Result;
end;

procedure TPPU.CpuWrite(Address: UInt16; Value: UInt8);
var
  OldCtrl: UInt8;
begin
  FOpenBus := Value;
  case Address and 7 of
    0:
      begin
        OldCtrl := FCtrl;
        FCtrl := Value;
        FT := (FT and $F3FF) or (UInt16(Value and 3) shl 10);
        if ((OldCtrl and $80) = 0) and ((FCtrl and $80) <> 0) and FNmiOccurred and not ((FScanline = 261) and (FCycle <= 1)) then
        begin
          FNmiLine := True;
          FNmiDelay := 0;
          FNmiPending := True;
        end
        else
          UpdateNmiState;
        CaptureSplitState;
      end;
    1:
      begin
        FMask := Value;
        CaptureSplitState;
      end;
    3:
      FOAMAddr := Value;
    4:
      begin
        FOAM[FOAMAddr] := Value;
        Inc(FOAMAddr);
      end;
    5:
      begin
        if not FAddrLatch then
        begin
          FFineX := Value and 7;
          FT := (FT and $7FE0) or (Value shr 3);
          FAddrLatch := True;
          CaptureSplitState;
        end
        else
        begin
          FT := (FT and $0C1F) or (UInt16(Value and 7) shl 12) or (UInt16(Value and $F8) shl 2);
          FAddrLatch := False;
          CaptureSplitState;
        end;
      end;
    6:
      begin
        if not FAddrLatch then
        begin
          FT := (FT and $00FF) or (UInt16(Value and $3F) shl 8);
          FAddrLatch := True;
        end
        else
        begin
          FT := (FT and $7F00) or Value;
          FV := FT;
          FAddrLatch := False;
        end;
      end;
    7:
      begin
        PpuWriteMemory(FV, Value);
        if (FCtrl and $04) <> 0 then
          FV := FV + 32
        else
          FV := FV + 1;
      end;
  end;
end;

procedure TPPU.WriteOAMDMA(Index: Integer; Value: UInt8);
begin
  FOAM[(FOAMAddr + Index) and $FF] := Value;
end;

function TPPU.ConsumeNmi: Boolean;
begin
  Result := FNmiPending;
  FNmiPending := False;
end;

function TPPU.SampleBackgroundPixel(X, Y: Integer; out PaletteIndex: UInt8): UInt8;
var
  ScrollX, ScrollY, BaseNT, WorldX, WorldY, TableX, TableY, Table, LocalX, LocalY: Integer;
  NameAddr, AttrAddr, PatternBase: UInt16;
  TileIndex, AttrByte, FineY, BitPos: UInt8;
  Lo, Hi: UInt8;
  RenderV: UInt16;
  RenderCtrl: UInt8;
  RenderMask: UInt8;
  RenderFineX: UInt8;
begin
  RenderV := FRenderV;
  RenderCtrl := FRenderCtrl;
  RenderMask := FRenderMask;
  RenderFineX := FRenderFineX;
  if FSplitActive and (Y >= FSplitY) then
  begin
    RenderV := FSplitV;
    RenderCtrl := FSplitCtrl;
    RenderMask := FSplitMask;
    RenderFineX := FSplitFineX;
  end;

  if (RenderMask and $08) = 0 then
  begin
    PaletteIndex := 0;
    Exit(0);
  end;
  if (X < 8) and ((RenderMask and $02) = 0) then
  begin
    PaletteIndex := 0;
    Exit(0);
  end;

  ScrollX := ((Integer(RenderV and $001F)) shl 3) or RenderFineX;
  Dec(ScrollX, 16);
  if FSplitActive and (Y >= FSplitY) then
    Inc(ScrollX, 16);
  while ScrollX < 0 do
    Inc(ScrollX, 512);
  ScrollY := (((Integer(RenderV shr 5)) and $1F) shl 3) or ((RenderV shr 12) and 7);
  BaseNT := RenderCtrl and 3;
  if FPreferredBaseNT >= 0 then
    BaseNT := FPreferredBaseNT;

  WorldX := (X + ScrollX) mod 512;
  WorldY := (Y + ScrollY) mod 480;
  TableX := ((BaseNT and 1) + (WorldX div 256)) and 1;
  TableY := (((BaseNT shr 1) and 1) + (WorldY div 240)) and 1;
  Table := (TableY shl 1) or TableX;
  LocalX := WorldX mod 256;
  LocalY := WorldY mod 240;

  NameAddr := $2000 + UInt16(Table) * $0400 + UInt16((LocalY div 8) * 32 + (LocalX div 8));
  TileIndex := PpuReadMemory(NameAddr);
  AttrAddr := $23C0 + UInt16(Table) * $0400 + UInt16((LocalY div 32) * 8 + (LocalX div 32));
  AttrByte := PpuReadMemory(AttrAddr);
  if (LocalY and $10) <> 0 then AttrByte := AttrByte shr 4;
  if (LocalX and $10) <> 0 then AttrByte := AttrByte shr 2;
  PaletteIndex := AttrByte and 3;

  FineY := LocalY and 7;
  PatternBase := UInt16((RenderCtrl and $10) shr 4) shl 12;
  Lo := PpuReadMemory(PatternBase + UInt16(TileIndex) * 16 + FineY);
  Hi := PpuReadMemory(PatternBase + UInt16(TileIndex) * 16 + FineY + 8);
  BitPos := 7 - (LocalX and 7);
  Result := (((Hi shr BitPos) and 1) shl 1) or ((Lo shr BitPos) and 1);
end;

function TPPU.SampleSpritePixel(X, Y: Integer; out PaletteIndex: UInt8; out PriorityBehindBg: Boolean; out IsSpriteZero: Boolean): UInt8;
var
  I, SpriteX, SpriteY, SpriteTop, SpriteHeight, Row, Col, BitPos: Integer;
  TileIndex, Attr: UInt8;
  PatternBase, Addr: UInt16;
  Lo, Hi: UInt8;
begin
  PaletteIndex := 0;
  PriorityBehindBg := False;
  IsSpriteZero := False;
  Result := 0;
  if (FRenderMask and $10) = 0 then Exit;
  if (X < 8) and ((FRenderMask and $04) = 0) then Exit;

  if (FRenderCtrl and $20) <> 0 then SpriteHeight := 16 else SpriteHeight := 8;
  for I := 0 to 63 do
  begin
    SpriteY := FOAM[I * 4 + 0];
    TileIndex := FOAM[I * 4 + 1];
    Attr := FOAM[I * 4 + 2];
    SpriteX := FOAM[I * 4 + 3];
    SpriteTop := SpriteY + 1;

    if (Y < SpriteTop) or (Y >= SpriteTop + SpriteHeight) then Continue;
    if (X < SpriteX) or (X >= SpriteX + 8) then Continue;

    Row := Y - SpriteTop;
    Col := X - SpriteX;
    if (Attr and $80) <> 0 then Row := SpriteHeight - 1 - Row;
    if (Attr and $40) <> 0 then Col := 7 - Col;

    if SpriteHeight = 16 then
    begin
      PatternBase := UInt16(TileIndex and 1) shl 12;
      TileIndex := TileIndex and $FE;
      if Row > 7 then
      begin
        Inc(TileIndex);
        Dec(Row, 8);
      end;
    end
    else
      PatternBase := UInt16((FRenderCtrl and $08) shr 3) shl 12;

    Addr := PatternBase + UInt16(TileIndex) * 16 + UInt16(Row and 7);
    Lo := PpuReadMemory(Addr);
    Hi := PpuReadMemory(Addr + 8);
    BitPos := 7 - Col;
    Result := (((Hi shr BitPos) and 1) shl 1) or ((Lo shr BitPos) and 1);
    if Result <> 0 then
    begin
      PaletteIndex := 4 + (Attr and 3);
      PriorityBehindBg := (Attr and $20) <> 0;
      IsSpriteZero := I = 0;
      Exit;
    end;
  end;
end;

function TPPU.SampleSpriteZeroPixel(X, Y: Integer): UInt8;
var
  Dummy: UInt8;
  DummyBehind, Zero: Boolean;
begin
  Result := SampleSpritePixel(X, Y, Dummy, DummyBehind, Zero);
  if not Zero then
    Result := 0;
end;

procedure TPPU.UpdateSpriteZeroHit;
var
  X, Y: Integer;
  BgPal: UInt8;
  SpriteY, SpriteX, SpriteTop, Row, Col, BitPos: Integer;
  TileIndex: UInt8;
  PatternBase, Addr: UInt16;
  Lo, Hi: UInt8;
  SpritePixel: UInt8;
begin
  FSprite0HitX := -1;
  FSprite0HitY := -1;
  if (FRenderMask and $18) <> $18 then Exit;

  for Y := 0 to NES_HEIGHT - 1 do
    for X := 0 to NES_WIDTH - 1 do
      if (SampleBackgroundPixel(X, Y, BgPal) <> 0) and (SampleSpriteZeroPixel(X, Y) <> 0) then
      begin
        if X <> 255 then
        begin
          FSprite0HitX := X;
          FSprite0HitY := Y;
          Exit;
        end;
      end;

  SpriteY := FOAM[0];
  TileIndex := FOAM[1];
  SpriteX := FOAM[3];
  SpriteTop := SpriteY + 1;
  PatternBase := UInt16((FRenderCtrl and $08) shr 3) shl 12;
  if (SpriteTop >= 0) and (SpriteTop < 240) and (SpriteX < 255) then
  begin
    for Row := 0 to 7 do
    begin
      Addr := PatternBase + UInt16(TileIndex) * 16 + UInt16(Row);
      Lo := PpuReadMemory(Addr);
      Hi := PpuReadMemory(Addr + 8);
      for Col := 0 to 7 do
      begin
        BitPos := 7 - Col;
        SpritePixel := (((Hi shr BitPos) and 1) shl 1) or ((Lo shr BitPos) and 1);
        if SpritePixel <> 0 then
        begin
          FSprite0HitX := SpriteX + Col;
          FSprite0HitY := SpriteTop + Row;
          Exit;
        end;
      end;
    end;
  end;
end;

procedure TPPU.RenderFullFrame;
var
  X, Y: Integer;
  BgPixel, BgPalette, SprPixel, SprPalette: UInt8;
  PriorityBehindBg, SpriteZero: Boolean;
  FinalPaletteAddr: UInt8;
begin
  for Y := 0 to NES_HEIGHT - 1 do
    for X := 0 to NES_WIDTH - 1 do
    begin
      BgPixel := SampleBackgroundPixel(X, Y, BgPalette);
      SprPixel := SampleSpritePixel(X, Y, SprPalette, PriorityBehindBg, SpriteZero);
      if (BgPixel = 0) and (SprPixel = 0) then
        FinalPaletteAddr := 0
      else if (BgPixel = 0) and (SprPixel <> 0) then
        FinalPaletteAddr := (SprPalette shl 2) or SprPixel
      else if (BgPixel <> 0) and (SprPixel = 0) then
        FinalPaletteAddr := (BgPalette shl 2) or BgPixel
      else if PriorityBehindBg then
        FinalPaletteAddr := (BgPalette shl 2) or BgPixel
      else
        FinalPaletteAddr := (SprPalette shl 2) or SprPixel;
      FFrame[X, Y] := NES_PALETTE[PpuReadMemory($3F00 + FinalPaletteAddr) and $3F];
    end;
end;

procedure TPPU.RebuildFrame;
begin
  RenderFullFrame;
  FSplitActive := False;
  FSplitY := 240;
end;

function TPPU.DebugReadMemory(Address: UInt16): UInt8;
begin
  Result := PpuReadMemory(Address);
end;

function TPPU.DebugMask: UInt8;
begin
  Result := FMask;
end;

function TPPU.DebugCtrl: UInt8;
begin
  Result := FCtrl;
end;

function TPPU.DebugStatus: UInt8;
begin
  Result := FStatus;
end;

function TPPU.DebugV: UInt16;
begin
  Result := FV;
end;

function TPPU.DebugT: UInt16;
begin
  Result := FT;
end;

function TPPU.DebugBackgroundPixel(X, Y: Integer): UInt8;
var
  P: UInt8;
begin
  Result := SampleBackgroundPixel(X, Y, P);
end;


function TPPU.DebugOAM(Index: Integer): UInt8;
begin
  Result := FOAM[Index and $FF];
end;

function TPPU.DebugSprite0HitX: Integer;
begin
  Result := FSprite0HitX;
end;

function TPPU.DebugSprite0HitY: Integer;
begin
  Result := FSprite0HitY;
end;

function TPPU.DebugSplitActive: Boolean;
begin
  Result := FSplitActive;
end;

function TPPU.DebugSplitY: Integer;
begin
  Result := FSplitY;
end;


end.









































































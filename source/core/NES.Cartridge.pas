unit NES.Cartridge;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.Classes,
  System.SysUtils,
  NES.Types,
  NES.Mapper;

type
  TCartridge = class
  private
    FMapper: TMapper;
    FMapperId: Integer;
    FValid: Boolean;
  public
    destructor Destroy; override;
    procedure LoadFromFile(const FileName: string);
    procedure Reset;
    property Mapper: TMapper read FMapper;
    property MapperId: Integer read FMapperId;
    property Valid: Boolean read FValid;
  end;

implementation

uses
  NES.Mapper0,
  NES.Mapper1,
  NES.Mapper2;

type
  TINESHeader = packed record
    Magic: array[0..3] of AnsiChar;
    PrgRomChunks: UInt8;
    ChrRomChunks: UInt8;
    Flags6: UInt8;
    Flags7: UInt8;
    PrgRamSize: UInt8;
    Flags9: UInt8;
    Flags10: UInt8;
    Zero: array[0..4] of UInt8;
  end;

procedure ReadExact(Stream: TFileStream; var Buffer; Count: Integer);
begin
  if Stream.Read(Buffer, Count) <> Count then
    raise ENESException.Create('Unexpected end of file');
end;

destructor TCartridge.Destroy;
begin
  FMapper.Free;
  inherited Destroy;
end;

procedure TCartridge.LoadFromFile(const FileName: string);
var
  Stream: TFileStream;
  Header: TINESHeader;
  PrgRom: TByteArray;
  ChrRom: TByteArray;
  Trainer: TByteArray;
  Mirror: TMirrorMode;
  HasTrainer: Boolean;
  ChrRam: Boolean;
begin
  FreeAndNil(FMapper);
  FValid := False;

  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    ReadExact(Stream, Header, SizeOf(Header));
    if (Header.Magic[0] <> 'N') or (Header.Magic[1] <> 'E') or (Header.Magic[2] <> 'S') or (Ord(Header.Magic[3]) <> $1A) then
      raise ENESException.Create('Invalid iNES file');

    if (Header.Flags6 and $08) <> 0 then
      Mirror := mmFourScreen
    else if (Header.Flags6 and $01) <> 0 then
      Mirror := mmVertical
    else
      Mirror := mmHorizontal;

    HasTrainer := (Header.Flags6 and $04) <> 0;
    if HasTrainer then
    begin
      SetLength(Trainer, 512);
      ReadExact(Stream, Trainer[0], 512);
    end;

    SetLength(PrgRom, Header.PrgRomChunks * $4000);
    if Length(PrgRom) = 0 then
      raise ENESException.Create('ROM has no PRG data');
    ReadExact(Stream, PrgRom[0], Length(PrgRom));

    SetLength(ChrRom, Header.ChrRomChunks * $2000);
    ChrRam := Length(ChrRom) = 0;
    if Length(ChrRom) > 0 then
      ReadExact(Stream, ChrRom[0], Length(ChrRom));

    FMapperId := ((Header.Flags7 and $F0) or (Header.Flags6 shr 4));
    case FMapperId of
      0:
        FMapper := TMapper000.Create(PrgRom, ChrRom, ChrRam, Mirror);
      1:
        FMapper := TMapper001.Create(PrgRom, ChrRom, ChrRam, Mirror);
      2:
        FMapper := TMapper002.Create(PrgRom, ChrRom, ChrRam, Mirror);
    else
      raise ENESException.CreateFmt('Unsupported mapper: %d', [FMapperId]);
    end;

    FValid := True;
  finally
    Stream.Free;
  end;
end;

procedure TCartridge.Reset;
begin
  if FMapper <> nil then
    FMapper.Reset;
end;

end.

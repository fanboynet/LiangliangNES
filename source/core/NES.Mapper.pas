unit NES.Mapper;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  NES.Types;

type
  TMirrorMode = (mmHorizontal, mmVertical, mmSingle0, mmSingle1, mmFourScreen);

  TMapper = class
  public
    function CpuRead(Address: UInt16; out Value: UInt8): Boolean; virtual; abstract;
    function CpuWrite(Address: UInt16; Value: UInt8): Boolean; virtual; abstract;
    function PpuRead(Address: UInt16; out Value: UInt8): Boolean; virtual; abstract;
    function PpuWrite(Address: UInt16; Value: UInt8): Boolean; virtual; abstract;
    function GetMirrorMode: TMirrorMode; virtual; abstract;
    procedure Reset; virtual; abstract;
  end;

implementation

end.

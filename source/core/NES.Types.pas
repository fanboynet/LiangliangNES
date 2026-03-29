unit NES.Types;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
{$IFDEF FPC}
  SysUtils;
{$ELSE}
  System.SysUtils;
{$ENDIF}

type
  UInt8 = Byte;
  UInt16 = Word;
  UInt32 = Cardinal;
  Int8 = ShortInt;
  Int16 = SmallInt;
  Int32 = Integer;

  TByteArray = array of UInt8;
  TPalette32 = array[0..63] of UInt32;
  TFrameBuffer = array[0..255, 0..239] of UInt32;

  ENESException = class(Exception);

implementation

end.


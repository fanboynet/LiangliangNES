unit NES.App;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

procedure RunApp;

implementation

uses
{$IFDEF FPC}
  SysUtils,
  Classes,
  IniFiles,
  Math,
{$ELSE}
  System.SysUtils,
  System.Classes,
  System.IniFiles,
  System.Math,
{$ENDIF}
  SDL2,
  NES.Console,
  NES.Controller,
  NES.Consts,
  NES.Types;

type
  TBitmapFileHeader = packed record
    bfType: Word;
    bfSize: Cardinal;
    bfReserved1: Word;
    bfReserved2: Word;
    bfOffBits: Cardinal;
  end;

  TBitmapInfoHeader = packed record
    biSize: Cardinal;
    biWidth: Integer;
    biHeight: Integer;
    biPlanes: Word;
    biBitCount: Word;
    biCompression: Cardinal;
    biSizeImage: Cardinal;
    biXPelsPerMeter: Integer;
    biYPelsPerMeter: Integer;
    biClrUsed: Cardinal;
    biClrImportant: Cardinal;
  end;

  TTextureBuffer = array[0..NES_HEIGHT - 1, 0..NES_WIDTH - 1] of UInt32;

  TKeyMap = record
    A: UInt32;
    B: UInt32;
    Select: UInt32;
    Start: UInt32;
    Up: UInt32;
    Down: UInt32;
    Left: UInt32;
    Right: UInt32;
  end;

  TAppConfig = record
    Scale: Integer;
    Filter: string;
    Keys: TKeyMap;
  end;

procedure SaveFrameToBMP(const FileName: string; const Frame: TFrameBuffer);
var
  FS: TFileStream;
  FH: TBitmapFileHeader;
  IH: TBitmapInfoHeader;
  X, Y: Integer;
  Pixel: Cardinal;
begin
  FS := TFileStream.Create(FileName, fmCreate);
  try
    FH.bfType := $4D42;
    FH.bfOffBits := SizeOf(FH) + SizeOf(IH);
    FH.bfReserved1 := 0;
    FH.bfReserved2 := 0;
    FH.bfSize := FH.bfOffBits + NES_WIDTH * NES_HEIGHT * 4;

    IH.biSize := SizeOf(IH);
    IH.biWidth := NES_WIDTH;
    IH.biHeight := NES_HEIGHT;
    IH.biPlanes := 1;
    IH.biBitCount := 32;
    IH.biCompression := 0;
    IH.biSizeImage := NES_WIDTH * NES_HEIGHT * 4;
    IH.biXPelsPerMeter := 0;
    IH.biYPelsPerMeter := 0;
    IH.biClrUsed := 0;
    IH.biClrImportant := 0;

    FS.WriteBuffer(FH, SizeOf(FH));
    FS.WriteBuffer(IH, SizeOf(IH));
    for Y := NES_HEIGHT - 1 downto 0 do
      for X := 0 to NES_WIDTH - 1 do
      begin
        Pixel := Frame[X, Y];
        FS.WriteBuffer(Pixel, SizeOf(Pixel));
      end;
  finally
    FS.Free;
  end;
end;

procedure CopyFrameToTextureBuffer(const Frame: TFrameBuffer; var Buffer: TTextureBuffer);
var
  X, Y: Integer;
begin
  for Y := 0 to NES_HEIGHT - 1 do
    for X := 0 to NES_WIDTH - 1 do
      Buffer[Y, X] := Frame[X, Y];
end;

function KeyNameToCode(const Name: string): UInt32;
var
  S: string;
begin
  S := UpperCase(Trim(Name));
  if S = 'Z' then Exit(SDLK_z);
  if S = 'X' then Exit(SDLK_x);
  if S = 'A' then Exit(SDLK_a);
  if S = 'S' then Exit(SDLK_s);
  if S = 'SPACE' then Exit(SDLK_SPACE);
  if (S = 'RETURN') or (S = 'ENTER') then Exit(SDLK_RETURN);
  if S = 'UP' then Exit(SDLK_UP);
  if S = 'DOWN' then Exit(SDLK_DOWN);
  if S = 'LEFT' then Exit(SDLK_LEFT);
  if S = 'RIGHT' then Exit(SDLK_RIGHT);
  if (Length(S) = 1) and (S[1] >= 'A') and (S[1] <= 'Z') then Exit(Ord(LowerCase(S)[1]));
  if (Length(S) = 1) and (S[1] >= '0') and (S[1] <= '9') then Exit(Ord(S[1]));
  Result := 0;
end;

function KeyCodeToName(KeyCode: UInt32): string;
begin
  case KeyCode of
    SDLK_z: Result := 'Z';
    SDLK_x: Result := 'X';
    SDLK_a: Result := 'A';
    SDLK_s: Result := 'S';
    SDLK_SPACE: Result := 'SPACE';
    SDLK_RETURN: Result := 'RETURN';
    SDLK_UP: Result := 'UP';
    SDLK_DOWN: Result := 'DOWN';
    SDLK_LEFT: Result := 'LEFT';
    SDLK_RIGHT: Result := 'RIGHT';
  else
    if (KeyCode >= Ord('a')) and (KeyCode <= Ord('z')) then
      Result := UpperCase(Chr(KeyCode))
    else if (KeyCode >= Ord('0')) and (KeyCode <= Ord('9')) then
      Result := Chr(KeyCode)
    else
      Result := 'UNKNOWN';
  end;
end;

function DefaultConfig: TAppConfig;
begin
  Result.Scale := 1;
  Result.Filter := 'linear';
  Result.Keys.A := SDLK_z;
  Result.Keys.B := SDLK_x;
  Result.Keys.Select := SDLK_SPACE;
  Result.Keys.Start := SDLK_RETURN;
  Result.Keys.Up := SDLK_UP;
  Result.Keys.Down := SDLK_DOWN;
  Result.Keys.Left := SDLK_LEFT;
  Result.Keys.Right := SDLK_RIGHT;
end;

procedure WriteConfig(const FileName: string; const Config: TAppConfig);
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(FileName);
  try
    Ini.WriteInteger('Video', 'Scale', Config.Scale);
    Ini.WriteString('Video', 'Filter', Config.Filter);
    Ini.WriteString('Controls', 'A', KeyCodeToName(Config.Keys.A));
    Ini.WriteString('Controls', 'B', KeyCodeToName(Config.Keys.B));
    Ini.WriteString('Controls', 'Select', KeyCodeToName(Config.Keys.Select));
    Ini.WriteString('Controls', 'Start', KeyCodeToName(Config.Keys.Start));
    Ini.WriteString('Controls', 'Up', KeyCodeToName(Config.Keys.Up));
    Ini.WriteString('Controls', 'Down', KeyCodeToName(Config.Keys.Down));
    Ini.WriteString('Controls', 'Left', KeyCodeToName(Config.Keys.Left));
    Ini.WriteString('Controls', 'Right', KeyCodeToName(Config.Keys.Right));
  finally
    Ini.Free;
  end;
end;

function ReadMappedKey(Ini: TIniFile; const Section, Ident: string; DefaultKey: UInt32): UInt32;
var
  Value: UInt32;
begin
  Value := KeyNameToCode(Ini.ReadString(Section, Ident, KeyCodeToName(DefaultKey)));
  if Value = 0 then
    Result := DefaultKey
  else
    Result := Value;
end;

function LoadOrCreateConfig(const FileName: string): TAppConfig;
var
  Ini: TIniFile;
  Defaults: TAppConfig;
begin
  Defaults := DefaultConfig;
  if not FileExists(FileName) then
    WriteConfig(FileName, Defaults);

  Ini := TIniFile.Create(FileName);
  try
    Result := Defaults;
    Result.Scale := Ini.ReadInteger('Video', 'Scale', Defaults.Scale);
    if Result.Scale < 1 then
      Result.Scale := 1;
    Result.Filter := Trim(Ini.ReadString('Video', 'Filter', Defaults.Filter));
    if Result.Filter = '' then
      Result.Filter := Defaults.Filter;

    Result.Keys.A := ReadMappedKey(Ini, 'Controls', 'A', Defaults.Keys.A);
    Result.Keys.B := ReadMappedKey(Ini, 'Controls', 'B', Defaults.Keys.B);
    Result.Keys.Select := ReadMappedKey(Ini, 'Controls', 'Select', Defaults.Keys.Select);
    Result.Keys.Start := ReadMappedKey(Ini, 'Controls', 'Start', Defaults.Keys.Start);
    Result.Keys.Up := ReadMappedKey(Ini, 'Controls', 'Up', Defaults.Keys.Up);
    Result.Keys.Down := ReadMappedKey(Ini, 'Controls', 'Down', Defaults.Keys.Down);
    Result.Keys.Left := ReadMappedKey(Ini, 'Controls', 'Left', Defaults.Keys.Left);
    Result.Keys.Right := ReadMappedKey(Ini, 'Controls', 'Right', Defaults.Keys.Right);
  finally
    Ini.Free;
  end;
end;

procedure SetButtonState(Console: TNESConsole; KeySym: UInt32; Pressed: Boolean; const Keys: TKeyMap);
begin
  if KeySym = Keys.A then Console.Controller1.SetButton(nbA, Pressed);
  if KeySym = Keys.B then Console.Controller1.SetButton(nbB, Pressed);
  if KeySym = Keys.Select then Console.Controller1.SetButton(nbSelect, Pressed);
  if KeySym = Keys.Start then Console.Controller1.SetButton(nbStart, Pressed);
  if KeySym = Keys.Up then Console.Controller1.SetButton(nbUp, Pressed);
  if KeySym = Keys.Down then Console.Controller1.SetButton(nbDown, Pressed);
  if KeySym = Keys.Left then Console.Controller1.SetButton(nbLeft, Pressed);
  if KeySym = Keys.Right then Console.Controller1.SetButton(nbRight, Pressed);
end;

procedure RunApp;
const
  TARGET_FPS = 60;
var
  Window: PSDL_Window;
  Renderer: PSDL_Renderer;
  Texture: PSDL_Texture;
  Event: TSDL_Event;
  Running: Boolean;
  Console: TNESConsole;
  Pitch: Integer;
  RomPath: string;
  IniPath: string;
  Config: TAppConfig;
  Title: AnsiString;
  LastFpsTicks, CurrentTicks: UInt32;
  FrameStartTicks: UInt32;
  NextFrameTicks: UInt32;
  FrameRemainder: Integer;
  Frames: Integer;
  DesiredSpec, ObtainedSpec: TSDL_AudioSpec;
  AudioDevice: SDL_AudioDeviceID;
  AudioBuffer: array[0..4095] of SmallInt;
  SamplesRead: Integer;
  AudioEnabled: Boolean;
  ShotFile: string;
  TextureBuffer: TTextureBuffer;
  ScaleQuality: AnsiString;
begin
{$IFDEF FPC}
  {$IFDEF UNIX}
  SetExceptionMask(GetExceptionMask + [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  {$ENDIF}
{$ENDIF}
  if ParamCount < 1 then
    raise Exception.Create('Usage: LiangliangNES <rom.nes>');

  RomPath := ParamStr(1);
  IniPath := ExpandFileName('LiangliangNES.ini');
  Config := LoadOrCreateConfig(IniPath);

  Console := TNESConsole.Create;
  try
    Console.LoadROM(RomPath);

    if SDL_Init(SDL_INIT_VIDEO or SDL_INIT_AUDIO or SDL_INIT_EVENTS) <> 0 then
      raise Exception.Create('SDL_Init failed');

    Window := nil;
    Renderer := nil;
    Texture := nil;
    AudioDevice := 0;
    AudioEnabled := False;
    try
      if Config.Scale > 1 then
        ScaleQuality := AnsiString(LowerCase(Config.Filter))
      else
        ScaleQuality := 'nearest';
      SDL_SetHint('SDL_RENDER_SCALE_QUALITY', PAnsiChar(ScaleQuality));

      Window := SDL_CreateWindow('LiangliangNES', SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, NES_WIDTH * Config.Scale, NES_HEIGHT * Config.Scale, SDL_WINDOW_SHOWN);
      if Window = nil then
        raise Exception.Create('SDL_CreateWindow failed');

      Renderer := SDL_CreateRenderer(Window, -1, SDL_RENDERER_ACCELERATED);
      if Renderer = nil then
        raise Exception.Create('SDL_CreateRenderer failed');

      Texture := SDL_CreateTexture(Renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, NES_WIDTH, NES_HEIGHT);
      if Texture = nil then
        raise Exception.Create('SDL_CreateTexture failed');

      FillChar(DesiredSpec, SizeOf(DesiredSpec), 0);
      FillChar(ObtainedSpec, SizeOf(ObtainedSpec), 0);
      DesiredSpec.freq := 44100;
      DesiredSpec.format := AUDIO_S16SYS;
      DesiredSpec.channels := 1;
      DesiredSpec.samples := 1024;
      try
        AudioDevice := SDL_OpenAudioDevice(nil, 0, @DesiredSpec, @ObtainedSpec, 0);
      except
        AudioDevice := 0;
      end;
      if (AudioDevice <> 0) and (ObtainedSpec.freq > 0) then
      begin
        Console.APU.SetSampleRate(ObtainedSpec.freq);
        SDL_PauseAudioDevice(AudioDevice, 0);
        AudioEnabled := True;
      end;

      Running := True;
      Pitch := NES_WIDTH * SizeOf(UInt32);
      LastFpsTicks := SDL_GetTicks;
      NextFrameTicks := LastFpsTicks;
      FrameRemainder := 0;
      Frames := 0;
      while Running do
      begin
        FrameStartTicks := SDL_GetTicks;

        while SDL_PollEvent(@Event) <> 0 do
        begin
          case Event.eventType of
            SDL_EVENT_QUIT:
              Running := False;
            SDL_KEYDOWN:
              begin
                if Event.key.keysym.sym = SDLK_ESCAPE then
                  Running := False
                else if Event.key.keysym.sym = SDLK_r then
                  Console.Reset
                else if Event.key.keysym.sym = SDLK_F5 then
                begin
                  ShotFile := Format('screenshot_%s.bmp', [FormatDateTime('yyyymmdd_hhnnss_zzz', Now)]);
                  SaveFrameToBMP(ShotFile, Console.PPU.Frame);
                end;
                SetButtonState(Console, Event.key.keysym.sym, True, Config.Keys);
              end;
            SDL_KEYUP:
              SetButtonState(Console, Event.key.keysym.sym, False, Config.Keys);
          end;
        end;

        Console.RunFrame;

        if AudioEnabled and (SDL_GetQueuedAudioSize(AudioDevice) < 8192) then
        begin
          repeat
            SamplesRead := Console.APU.PopSamples(@AudioBuffer[0], Length(AudioBuffer));
            if SamplesRead > 0 then
              SDL_QueueAudio(AudioDevice, @AudioBuffer[0], SamplesRead * SizeOf(SmallInt));
          until SamplesRead = 0;
        end;

        CopyFrameToTextureBuffer(Console.PPU.Frame, TextureBuffer);
        SDL_UpdateTexture(Texture, nil, @TextureBuffer[0, 0], Pitch);
        SDL_RenderClear(Renderer);
        SDL_RenderCopy(Renderer, Texture, nil, nil);
        SDL_RenderPresent(Renderer);

        Inc(Frames);
        CurrentTicks := SDL_GetTicks;
        if CurrentTicks - LastFpsTicks >= 1000 then
        begin
          Title := AnsiString(Format('LiangliangNES - %d FPS - %s', [Frames, ExtractFileName(RomPath)]));
          SDL_SetWindowTitle(Window, PAnsiChar(Title));
          Frames := 0;
          LastFpsTicks := CurrentTicks;
        end;

        Inc(NextFrameTicks, 16);
        Inc(FrameRemainder, 40);
        if FrameRemainder >= TARGET_FPS then
        begin
          Inc(NextFrameTicks);
          Dec(FrameRemainder, TARGET_FPS);
        end;
        CurrentTicks := SDL_GetTicks;
        if Integer(NextFrameTicks) > Integer(CurrentTicks) then
          SDL_Delay(NextFrameTicks - CurrentTicks)
        else if CurrentTicks - FrameStartTicks > 250 then
          NextFrameTicks := CurrentTicks;
      end;
    finally
      if AudioEnabled and (AudioDevice <> 0) then
        SDL_CloseAudioDevice(AudioDevice);
      if Texture <> nil then
        SDL_DestroyTexture(Texture);
      if Renderer <> nil then
        SDL_DestroyRenderer(Renderer);
      if Window <> nil then
        SDL_DestroyWindow(Window);
      SDL_Quit;
    end;
  finally
    Console.Free;
  end;
end;

end.






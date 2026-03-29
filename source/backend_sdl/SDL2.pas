unit SDL2;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  NES.Types;

const
{$IFDEF MSWINDOWS}
  SDL_LibName = 'SDL2.dll';
{$ENDIF}
{$IFDEF LINUX}
  SDL_LibName = 'libSDL2-2.0.so.0';
{$ENDIF}
{$IFDEF DARWIN}
  SDL_LibName = 'libSDL2.dylib';
{$ENDIF}
{$IFNDEF MSWINDOWS}
{$IFNDEF LINUX}
{$IFNDEF DARWIN}
  SDL_LibName = 'SDL2';
{$ENDIF}
{$ENDIF}
{$ENDIF}

  SDL_INIT_VIDEO = $00000020;
  SDL_INIT_AUDIO = $00000010;
  SDL_INIT_EVENTS = $00004000;

  SDL_WINDOWPOS_CENTERED = $2FFF0000;
  SDL_WINDOW_SHOWN = $00000004;
  SDL_RENDERER_ACCELERATED = $00000002;
  SDL_RENDERER_PRESENTVSYNC = $00000004;
  SDL_TEXTUREACCESS_STREAMING = 1;
  SDL_PIXELFORMAT_ARGB8888 = $16362004;
  AUDIO_S16SYS = $8010;

  SDL_EVENT_QUIT = $100;
  SDL_KEYDOWN = $300;
  SDL_KEYUP = $301;

  SDLK_ESCAPE = 27;
  SDLK_o = Ord('o');
  SDLK_r = Ord('r');
  SDLK_RETURN = 13;
  SDLK_SPACE = 32;
  SDLK_UP = 1073741906;
  SDLK_DOWN = 1073741905;
  SDLK_LEFT = 1073741904;
  SDLK_RIGHT = 1073741903;
  SDLK_z = Ord('z');
  SDLK_x = Ord('x');
  SDLK_a = Ord('a');
  SDLK_s = Ord('s');
  SDLK_F5 = 1073741886;

type
  PSDL_Window = Pointer;
  PSDL_Renderer = Pointer;
  PSDL_Texture = Pointer;
  SDL_AudioDeviceID = UInt32;

  TSDL_AudioCallback = procedure(userdata: Pointer; stream: Pointer; len: Integer); cdecl;

  TSDL_AudioSpec = packed record
    freq: Integer;
    format: UInt16;
    channels: UInt8;
    silence: UInt8;
    samples: UInt16;
    padding: UInt16;
    size: UInt32;
    callback: TSDL_AudioCallback;
    userdata: Pointer;
  end;

  TSDL_Keysym = packed record
    scancode: UInt32;
    sym: UInt32;
    mod_: UInt16;
    unused: UInt32;
  end;

  TSDL_KeyboardEvent = packed record
    eventType: UInt32;
    timestamp: UInt32;
    windowID: UInt32;
    state: UInt8;
    repeat_: UInt8;
    padding2: UInt8;
    padding3: UInt8;
    keysym: TSDL_Keysym;
  end;

  TSDL_QuitEvent = packed record
    eventType: UInt32;
    timestamp: UInt32;
  end;

  TSDL_Event = packed record
    case Integer of
      0: (eventType: UInt32);
      1: (key: TSDL_KeyboardEvent);
      2: (quitEvent: TSDL_QuitEvent);
      3: (padding: array[0..55] of UInt8);
  end;

function SDL_Init(flags: UInt32): Integer; cdecl; external SDL_LibName;
procedure SDL_Quit; cdecl; external SDL_LibName;
function SDL_CreateWindow(title: PAnsiChar; x, y, w, h, flags: Integer): PSDL_Window; cdecl; external SDL_LibName;
function SDL_CreateRenderer(window: PSDL_Window; index: Integer; flags: UInt32): PSDL_Renderer; cdecl; external SDL_LibName;
function SDL_CreateTexture(renderer: PSDL_Renderer; format, access, w, h: Integer): PSDL_Texture; cdecl; external SDL_LibName;
procedure SDL_DestroyTexture(texture: PSDL_Texture); cdecl; external SDL_LibName;
procedure SDL_DestroyRenderer(renderer: PSDL_Renderer); cdecl; external SDL_LibName;
procedure SDL_DestroyWindow(window: PSDL_Window); cdecl; external SDL_LibName;
function SDL_PollEvent(event: Pointer): Integer; cdecl; external SDL_LibName;
function SDL_UpdateTexture(texture: PSDL_Texture; rect: Pointer; pixels: Pointer; pitch: Integer): Integer; cdecl; external SDL_LibName;
function SDL_RenderClear(renderer: PSDL_Renderer): Integer; cdecl; external SDL_LibName;
function SDL_RenderCopy(renderer: PSDL_Renderer; texture: PSDL_Texture; srcrect, dstrect: Pointer): Integer; cdecl; external SDL_LibName;
procedure SDL_RenderPresent(renderer: PSDL_Renderer); cdecl; external SDL_LibName;
procedure SDL_Delay(ms: UInt32); cdecl; external SDL_LibName;
function SDL_GetTicks: UInt32; cdecl; external SDL_LibName;
function SDL_SetWindowTitle(window: PSDL_Window; title: PAnsiChar): Integer; cdecl; external SDL_LibName;
function SDL_SetHint(name: PAnsiChar; value: PAnsiChar): Integer; cdecl; external SDL_LibName;
function SDL_OpenAudioDevice(device: PAnsiChar; iscapture: Integer; desired, obtained: Pointer; allowed_changes: Integer): SDL_AudioDeviceID; cdecl; external SDL_LibName;
procedure SDL_PauseAudioDevice(dev: SDL_AudioDeviceID; pause_on: Integer); cdecl; external SDL_LibName;
function SDL_QueueAudio(dev: SDL_AudioDeviceID; data: Pointer; len: UInt32): Integer; cdecl; external SDL_LibName;
function SDL_GetQueuedAudioSize(dev: SDL_AudioDeviceID): UInt32; cdecl; external SDL_LibName;
procedure SDL_CloseAudioDevice(dev: SDL_AudioDeviceID); cdecl; external SDL_LibName;

implementation

end.





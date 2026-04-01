# LiangliangNES
A NES emulator written by Delphi(Pascal)

**简介**
- **支持Mappeer0,1,2**
- **键盘输入，屏幕输出，声音输出 都使用SDL2库**
- **跨平台支持Windows/Linux/MacOS**

<img src="./screen/mario.png" height="200" style="margin-right: 15px;"><img src="./screen/contra.png" height="200" style="margin-right: 15px;"><img src="./screen/castle.png" height="200" style="margin-right: 15px;"><img src="./screen/tank.png" height="200" style="margin-right: 15px;"><br><img src="./screen/contra_linux.png" height="200" style="margin-right: 15px;"><img src="./screen/contra_mac.png" height="200" style="margin-right: 15px;">

**编译**
- **Windows(Delphi编译)**:dcc32 -B -U"source\core;source\frontend;source\backend_sdl" LiangliangNES.dpr
- **Linux(编译环境)**:sudo apt-get install -y fp-compiler libsdl2-2.0-0 libsdl2-dev fp-units-fcl build-essential libc6-dev binutils
- **Windows/Linux(FreePascal编译)**:fpc -B -Fu./source/core -Fu./source/frontend  -Fu./source/backend_sdl  LiangliangNES.dpr
- **MacOS(编译环境)**:
- 1. 安装命令行开发工具(需要xcode): xcode-select --install
- 2. 使用 brew 安装剩余包(需要brew): brew install fpc sdl2 binutils
- **MacOS(编译)**:fpc -B -Fu./source/core -Fu./source/frontend -Fu./source/backend_sdl -Fl/opt/homebrew/opt/sdl2/lib -k"-lSDL2" -k"-rpath /opt/homebrew/opt/sdl2/lib" LiangliangNES.dpr

**运行**
- **例如运行Mario**: .\LiangliangNES.exe '.\Super Mario Bros. (World).nes'

**控制**
- 通过修改LiangliangNES.ini自定义
```ini
[Video]
Scale=2 ;屏幕大小
Filter=linear ;SDL的屏幕过滤
[Controls]
A=Z
B=X
Select=SPACE
Start=RETURN
Up=UP
Down=DOWN
Left=LEFT
Right=RIGHT
```
**每个核心文件的职责**
- LiangliangNES.dpr 程序入口，启动 RunApp
- NES.App.pas SDL 窗口、输入、音频队列、配置、主循环、截图
- SDL2.pas SDL2 API 声明
- NES.Console.pas 总调度器，组织 PPU x3 / APU x1 / CPU or DMA
- NES.CPU.pas 6502/N2A03 指令执行、中断、周期控制
- NES.PPU.pas 视频寄存器、扫描线推进、NMI、帧缓冲
- NES.APU.pas 声道、frame counter、混音、样本缓冲
- NES.Bus.pas CPU 地址空间解码，RAM/PPU/APU/手柄/Mapper/DMA 路由
- NES.Cartridge.pas iNES 解析、Mapper 创建
- NES.Mapper.pas Mapper 抽象基类
- NES.Mapper0.pas NROM
- NES.Mapper1.pas MMC1
- NES.Mapper2.pas UxROM
- NES.Controller.pas 手柄锁存与位移读出
- NES.Types.pas 公共类型定义
- NES.Consts.pas 常量定义

**源码关系图**
```mermaid
flowchart TD
    A["LiangliangNES.dpr"] --> B["NES.App.pas"]

    B --> C["NES.Console.pas"]
    B --> D["SDL2.pas"]
    B --> E["NES.Controller.pas"]
    B --> F["NES.Consts.pas"]
    B --> G["NES.Types.pas"]

    C --> H["NES.CPU.pas"]
    C --> I["NES.PPU.pas"]
    C --> J["NES.APU.pas"]
    C --> K["NES.Bus.pas"]
    C --> L["NES.Cartridge.pas"]
    C --> E

    K --> I
    K --> J
    K --> L
    K --> E
    K --> G

    L --> M["NES.Mapper.pas"]
    L --> N["NES.Mapper0.pas"]
    L --> O["NES.Mapper1.pas"]
    L --> P["NES.Mapper2.pas"]

    N --> M
    O --> M
    P --> M

    H --> G
    I --> G
    J --> G
    M --> G
    N --> G
    O --> G
    P --> G

```

**分层**
```mermaid
flowchart TD
    A["前端层"] --> A1["LiangliangNES.dpr"]
    A --> A2["NES.App.pas"]
    A --> A3["SDL2.pas"]

    B["调度层"] --> B1["NES.Console.pas"]

    C["核心仿真层"] --> C1["NES.CPU.pas"]
    C --> C2["NES.PPU.pas"]
    C --> C3["NES.APU.pas"]
    C --> C4["NES.Bus.pas"]
    C --> C5["NES.Controller.pas"]

    D["卡带层"] --> D1["NES.Cartridge.pas"]
    D --> D2["NES.Mapper.pas"]
    D --> D3["NES.Mapper0.pas"]
    D --> D4["NES.Mapper1.pas"]
    D --> D5["NES.Mapper2.pas"]

    E["基础类型层"] --> E1["NES.Types.pas"]
    E --> E2["NES.Consts.pas"]

    A2 --> B1
    B1 --> C1
    B1 --> C2
    B1 --> C3
    B1 --> C4
    C4 --> D1
    D1 --> D2
    D1 --> D3
    D1 --> D4
    D1 --> D5
    C1 --> E1
    C2 --> E1
    C3 --> E1
    C4 --> E1

```

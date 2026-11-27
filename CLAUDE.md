# STM32 开发环境（GCC + CMake + Ninja + pyOCD）

本仓库是 STM32 交叉开发工具链宿主，位于 `D:\ELE\tools\stm32_ide`。
工具链以 portable 方式装在本仓库 `tools/` 下（不入 git），由 `bin/setup.sh` 一键安装，
四个 bin 目录已注册用户 PATH，新开终端可直接使用 `arm-none-eabi-gcc`、`cmake`、`ninja`、`pyocd`。

## 新环境初始化（幂等，可重复运行）

```bash
bash bin/setup.sh            # 全量：下载→解压→pyOCD venv→PATH→验证；支持 --step N / --force
```

## 工具清单（本机实际位置）

| 工具 | 路径 |
| --- | --- |
| ARM GCC 14.2.1（含 arm-none-eabi-gdb） | `D:\ELE\tools\stm32_ide\tools\arm-gcc\bin\` |
| CMake 3.31.8 | `D:\ELE\tools\stm32_ide\tools\cmake\bin\cmake.exe` |
| Ninja 1.13.2 | `D:\ELE\tools\stm32_ide\tools\ninja\ninja.exe` |
| pyOCD（烧录/调试/RTT，独立 venv） | `D:\ELE\tools\stm32_ide\tools\pyocd-venv\Scripts\pyocd.exe` |
| Zadig 2.9（探针 WinUSB 驱动，接探针时用） | `tools\downloads\zadig\zadig-2.9.exe` |
| 会话启用脚本（PATH 未生效时备用） | `tools\env.bat`（cmd）/ `source tools/env.sh`（git-bash） |

## 常用命令

```bash
# 配置 + 编译（在工程目录下；toolchain 文件路径相对本仓库，可整体搬迁）
cmake -G Ninja -B build -DCMAKE_TOOLCHAIN_FILE=D:/ELE/tools/stm32_ide/cmake/toolchain-arm-none-eabi.cmake
cmake --build build

# 列出调试探针 / 支持的芯片
pyocd list
pyocd list --targets

# 首次使用某系列芯片时安装 CMSIS Pack
pyocd pack install stm32g0xx

# 烧录 / GDB Server / RTT（多探针时加 -u <Unique ID>）
pyocd flash -t STM32G031F8 build/firmware.elf
pyocd gdbserver -t STM32G031F8
pyocd rtt -t STM32G031F8
```

交互式断点调试：VS Code 装 Cortex-Debug 扩展后按 F5（配置模板见 `.vscode/launch.json`，
把 `device`/`executable` 改成实际值；工程需自带 `.vscode` 时从本仓库拷贝改路径）。
命令行调试：`arm-none-eabi-gdb build/firmware.elf` 后 `target remote localhost:3333`。

## 探针与目标板

- 首次连接 CMSIS-DAP 探针：Zadig → Options → List All Devices → 给 **CMSIS-DAP 接口**装 WinUSB
  （nanoDAP 等 v1/HID 探针免驱；⚠️ 不要动 CDC 串口）
- 多探针固定用 `-u <Unique ID>`，或在工程根放 `pyocd.yaml`（模板 `pyocd.yaml.example`）绑定
- 目标板独立供电，DAPLink 只接 SWDIO/SWCLK/GND

## 注意

- pyOCD 在 GBK 控制台输出特殊字符会报编码错，前置 `set PYTHONIOENCODING=utf-8`
- 工具与工程路径不含中文和空格；探针直连主板后置 USB 口
- STM32CubeMX 可选（需 ST 账号手动装），生成 CMake 工程后直接用本链编译
- 完整说明（驱动安装、网络镜像、Windows 避坑清单）见 README.md

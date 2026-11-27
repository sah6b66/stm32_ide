# stm32_ide

适用于 Claude Code 等 AI Agent 的 STM32 交叉开发与调试环境（Windows + GCC + CMake + Ninja + pyOCD + CMSIS-DAP）。

工具链全部以**免安装（portable）方式**保存在本仓库 `tools/` 目录下，并已加入用户 PATH，新开终端即可直接使用。AI Agent 可直接通过命令行调用全部工具（无需 MCP）。

## 已安装组件

| 工具 | 版本 | 位置 | 校验 |
| --- | --- | --- | --- |
| ARM GCC (arm-none-eabi) | 14.2.1 (xPack 打包，含 GDB 15.2) | `tools\arm-gcc\bin\` | SHA256 通过 |
| CMake | 3.31.8 | `tools\cmake\bin\` | zip 结构完整 |
| Ninja | 1.13.2 | `tools\ninja\ninja.exe` | 运行验证 |
| pyOCD | 0.46.1 | `E:\Python312\Scripts\pyocd.exe` | pip（清华镜像） |
| Zadig | 2.9 | `tools\downloads\zadig\zadig-2.9.exe` | PE32，5.1MB |
| Python | 3.12.10（系统已有，未新装） | `E:\Python312\` | — |

Git 与 VS Code 使用系统已有安装，未重复安装。

## 目录结构

```text
e:\stm32_ide\
├── tools/                    # 本地工具链（已 .gitignore，不入库）
│   ├── arm-gcc/              # arm-none-eabi-gcc / gdb / objcopy ...
│   ├── cmake/                # cmake.exe
│   ├── ninja/                # ninja.exe
│   ├── env.bat               # 临时启用工具链的会话脚本（未改 PATH 时备用）
│   └── downloads/            # 原始安装包留存
├── cmake/
│   └── toolchain-arm-none-eabi.cmake   # 交叉编译工具链文件
├── .vscode/
│   ├── settings.json         # CMake Tools / IntelliSense 配置
│   ├── launch.json           # Cortex-Debug (pyOCD) 调试配置
│   └── extensions.json       # 推荐扩展
├── pyocd.yaml.example        # pyOCD 配置模板（复制为 pyocd.yaml 后编辑）
├── CLAUDE.md                 # AI Agent 专用速查
└── README.md
```

## 验证安装（新开一个终端）

```bat
arm-none-eabi-gcc --version
cmake --version
ninja --version
pyocd --version
```

## 日常工作流

### 编译

```bat
cd 某个工程目录
cmake -G Ninja -B build -DCMAKE_TOOLCHAIN_FILE=E:/stm32_ide/cmake/toolchain-arm-none-eabi.cmake
cmake --build build
```

在 VS Code 中打开工程后，CMake Tools 扩展会自动使用 `.vscode/settings.json` 中的同款配置（前提：该工程有自己的 `.vscode`，或将本仓库配置拷贝过去）。

### 烧录 / 调试 / RTT

```bat
pyocd list                       :: 查看探针和 Unique ID
pyocd pack install stm32f1xx     :: 首次使用某系列芯片时安装 CMSIS Pack（按实际型号）
pyocd flash -t STM32F103C8 -u <探针ID> build\firmware.elf
pyocd gdbserver -t STM32F103C8 -u <探针ID>     :: 供 GDB / Cortex-Debug 连接
pyocd rtt -t STM32F103C8 -u <探针ID>           :: 实时查看 RTT 日志
```

交互式断点调试：VS Code 安装 Cortex-Debug 扩展后按 F5（配置见 `.vscode/launch.json`，把 `device` 和 `executable` 改成实际值）。命令行调试：`arm-none-eabi-gdb build\firmware.elf` 后 `target remote localhost:3333`。

## 首次连接 CMSIS-DAP 探针（一次性）

1. 插入 DAPLink 探针，设备管理器应出现 CMSIS-DAP 设备
2. 运行 `tools\downloads\zadig\zadig-2.9.exe` → Options → List All Devices
3. 为 **CMSIS-DAP Interface**（v2 探针是 "CMSIS-DAP v2"）安装 **WinUSB** 驱动
   ⚠️ 只处理 CMSIS-DAP 接口，不要动 CDC 串口（Windows 自带驱动）
4. 验证：`pyocd list` 能看到探针 Unique ID 即成功

## STM32CubeMX（可选，需手动安装）

CubeMX 用于图形化配置外设并直接生成 CMake 工程，但官方下载需要 ST 账号登录，且安装器要求管理员权限、默认装入 `C:\Program Files`，无法自动化放入本目录：

1. 从 <https://www.st.com/en/development-tools/stm32cubemx.html> 下载安装（需免费注册 ST 账号）
2. 工程管理器 → Toolchain/IDE 选择 **CMake**
3. 生成的工程自带 CMakeLists.txt，用上面"日常工作流"直接编译烧录

不用 CubeMX 也完全可以：手写 CMakeLists + HAL 库，或使用各类 GitHub 模板。

## 对原始建议方案的修正说明

原方案整体技术路线正确（GCC + CMake + Ninja + pyOCD + CMSIS-DAP 是成熟组合），已按以下修正执行：

1. **MCP 配置片段有误**：pyOCD 不是 MCP 服务器，`{"command": "pyocd"}` 会导致 Claude Code 连接失败/挂起。正确做法是让 AI Agent 直接通过命令行调用 `pyocd`（本仓库 CLAUDE.md 已内置速查命令）；交互式调试用 Cortex-Debug 扩展，两者都不需要 MCP。
2. **Python 版本**：原建议"必须 3.11、不要 3.13"已过时 —— pyOCD 0.46 完全支持当前系统的 Python 3.12，无需另装。
3. **工具版本更新**：ARM GCC 13.2 → 14.2.1、CMake 3.30 → 3.31.8、Ninja 1.12 → 1.13.2、Zadig 2.8 → 2.9、pyOCD 最新 0.46.1。CMake 不用 4.x 是为避免其对老工程 `cmake_minimum_required` 的兼容性限制。
4. **pyocd.yaml 键名纠正**：原模板的 `probe_id:`、`swd_clock:`、`rtx.enable_rtt:`、`rtt_block_size:` 均非有效会话选项（0.46 会静默忽略未知键）。正确键名：`probes:` 映射绑定探针、`frequency` 设置 SWD 时钟，见 `pyocd.yaml.example`。RTT 无需配置项，直接 `pyocd rtt`。
5. **ARM GCC 来源**：官方 developer.arm.com 直链在本网络仅 ~120KB/s，改用 GitHub 上 xPack 项目打包的同源工具链（ARM GNU 14.2.Rel1 重打包），SHA256 校验通过。
6. **OpenOCD / J-Link RTT Viewer**：按原方案不装（pyOCD 已覆盖全部功能）。

## 网络备注

本机直连 GitHub Release 资源会被重置，以下源已验证可用：

- PyPI：清华镜像 `https://pypi.tuna.tsinghua.edu.cn/simple`
- GitHub Release 资源：`https://gh-proxy.com/https://github.com/...` 前缀加速
- cmake.org 直连可用但慢

## Windows 避坑清单

1. 工具与工程路径不含中文和空格
2. 探针直连主板后置 USB 口，不用无源 Hub
3. 设备管理器 → USB 根集线器 → 电源管理 → 取消"允许计算机关闭此设备以节约电源"
4. Zadig 只给 CMSIS-DAP 接口装 WinUSB，不动 CDC 串口
5. 多探针时用 `-u <Unique ID>` 固定探针
6. 目标板独立供电，DAPLink 只接 SWDIO/SWCLK/GND（3V3 参考电压视板子情况）

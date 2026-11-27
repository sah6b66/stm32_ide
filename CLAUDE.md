# STM32 开发环境（GCC + CMake + Ninja + pyOCD）

本仓库是 STM32 交叉开发工作区。工具链已安装在本地，路径固定如下：

| 工具 | 路径 |
| --- | --- |
| ARM GCC 14.2 (arm-none-eabi-*) | `E:\stm32_ide\tools\arm-gcc\bin\` |
| CMake 3.31 | `E:\stm32_ide\tools\cmake\bin\cmake.exe` |
| Ninja 1.13 | `E:\stm32_ide\tools\ninja\ninja.exe` |
| pyOCD 0.46（烧录/调试/RTT） | `E:\Python312\Scripts\pyocd.exe` |
| Zadig 2.9（装 WinUSB 驱动用） | `E:\stm32_ide\tools\downloads\zadig\zadig-2.9.exe` |

以上目录均已加入用户 PATH（新开终端直接可用 `arm-none-eabi-gcc`、`cmake`、`ninja`、`pyocd`）。

## 常用命令

```bash
# 配置 + 编译（在某个工程目录下）
cmake -G Ninja -B build -DCMAKE_TOOLCHAIN_FILE=E:/stm32_ide/cmake/toolchain-arm-none-eabi.cmake
cmake --build build

# 列出调试探针 / 支持的芯片
pyocd list
pyocd list --targets

# 烧录
pyocd flash -t STM32F103C8 build/firmware.elf

# GDB Server（配合 VS Code Cortex-Debug 或 arm-none-eabi-gdb）
pyocd gdbserver -t STM32F103C8

# RTT 日志
pyocd rtt -t STM32F103C8
```

完整说明（含驱动安装、CubeMX、避坑清单）见 README.md。

## 当前连接的硬件（已实测可连可调）

- 单板：IMTU_TO_FEETECH（STM32G031F8 + LSM6DSV16X，见 `IMTU_TO_FEETECH单板调试说明.txt`）
- 探针：nanoDAP（CMSIS-DAP v1/HID，**无需 Zadig 驱动**），Unique ID `07000001003100304300000d56314e36a5a5a5a597969908`
- 串口：nanoDAP 的 CDC 串口为 **COM5**
- 目标已装 pack：Keil.STM32G0xx_DFP 2.1.0（目标名 `stm32g031f8px`）
- 工程目录：`imu_to_feetech/`（含 Makefile 与 keil/ 双工程）
- 根目录 `pyocd.yaml` 已绑定探针与目标，`pyocd` 在本仓库任意目录运行会自动应用，命令可省略 `-t/-u` 参数

注意：pyOCD 在 GBK 控制台输出含特殊字符时会报编码错，前置 `set PYTHONIOENCODING=utf-8` 可避免。

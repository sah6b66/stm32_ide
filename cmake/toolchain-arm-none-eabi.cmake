# ARM Cortex-M 交叉编译工具链文件
# 用法: cmake -G Ninja -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-arm-none-eabi.cmake ..
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)

# 工具链随本仓库携带（由 bin/setup.sh 安装到 <仓库根>/tools/arm-gcc），路径相对本文件，可整体搬迁
get_filename_component(ARM_TOOLCHAIN_DIR "${CMAKE_CURRENT_LIST_DIR}/../tools/arm-gcc/bin" ABSOLUTE)
set(TOOLCHAIN_PREFIX ${ARM_TOOLCHAIN_DIR}/arm-none-eabi)

set(CMAKE_C_COMPILER   ${TOOLCHAIN_PREFIX}-gcc.exe)
set(CMAKE_CXX_COMPILER ${TOOLCHAIN_PREFIX}-g++.exe)
set(CMAKE_ASM_COMPILER ${TOOLCHAIN_PREFIX}-gcc.exe)
set(CMAKE_AR           ${TOOLCHAIN_PREFIX}-ar.exe)
set(CMAKE_OBJCOPY      ${TOOLCHAIN_PREFIX}-objcopy.exe CACHE FILEPATH "")
set(CMAKE_OBJDUMP      ${TOOLCHAIN_PREFIX}-objdump.exe CACHE FILEPATH "")
set(CMAKE_SIZE         ${TOOLCHAIN_PREFIX}-size.exe    CACHE FILEPATH "")
set(CMAKE_GDB          ${TOOLCHAIN_PREFIX}-gdb.exe     CACHE FILEPATH "")

# 交叉环境无法运行编译出的程序，改为静态库探测
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

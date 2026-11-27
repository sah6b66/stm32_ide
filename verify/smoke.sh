#!/usr/bin/env bash
# STM32 工具链端到端冒烟测试：用本仓库工具链文件编译一个最小 ARM 程序
# 用法：bash verify/smoke.sh  （前置：bin/setup.sh 已成功执行）
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "[FAIL] $1"; exit 1; }

echo "== STM32 工具链冒烟测试 =="
echo "临时目录: $TMP"

# 1. 版本检查
"$TOOLS/arm-gcc/bin/arm-none-eabi-gcc.exe" --version >/dev/null 2>&1 || fail "arm-none-eabi-gcc 不可用"
"$TOOLS/cmake/bin/cmake.exe" --version >/dev/null 2>&1 || fail "cmake 不可用"
"$TOOLS/ninja/ninja.exe" --version >/dev/null 2>&1 || fail "ninja 不可用"
"$TOOLS/pyocd-venv/Scripts/pyocd.exe" --version >/dev/null 2>&1 || fail "pyocd 不可用"
echo "[ok] 四件套版本命令均可用"

# 2. 最小工程编译
cat > "$TMP/main.c" <<'EOF'
#include <stdint.h>
volatile uint32_t counter;
int main(void) {
    counter = 0;
    for (;;) { counter++; }
}
EOF
cat > "$TMP/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.20)
project(smoke C)
add_executable(firmware main.c)
set_target_properties(firmware PROPERTIES SUFFIX ".elf")
target_link_options(firmware PRIVATE -nostartfiles)
EOF

"$TOOLS/cmake/bin/cmake.exe" -G Ninja -B "$TMP/build" -S "$TMP" \
  -DCMAKE_TOOLCHAIN_FILE="$ROOT/cmake/toolchain-arm-none-eabi.cmake" \
  -DCMAKE_MAKE_PROGRAM="$TOOLS/ninja/ninja.exe" >/dev/null || fail "cmake 配置失败"
"$TOOLS/cmake/bin/cmake.exe" --build "$TMP/build" >/dev/null || fail "编译失败"
[ -f "$TMP/build/firmware.elf" ] || fail "未生成 firmware.elf"

# 3. 验证产物确为 ARM ELF
"$TOOLS/arm-gcc/bin/arm-none-eabi-readelf.exe" -h "$TMP/build/firmware.elf" | grep -q "Machine:.*ARM" \
  || fail "ELF 不是 ARM 架构"
echo "[ok] 编译出 ARM ELF: $("$TOOLS/arm-gcc/bin/arm-none-eabi-size.exe" "$TMP/build/firmware.elf" | tail -1)"

echo "== PASS =="

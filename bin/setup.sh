#!/usr/bin/env bash
# STM32 工具链一键安装脚本（免安装 portable、幂等、可重复运行）
# 用法：bash bin/setup.sh [--step N|all] [--force]
#   --step N  只运行第 N 步（1-6）
#   --force   忽略已装检查，重新下载/解压/重建 venv
#
# 安装内容（全部落在仓库 tools/ 目录下，不入 git）：
#   1. 前置检查（curl / powershell / Python>=3.11）
#   2. 下载原始包到 tools/downloads/<名>/（每包独立目录）
#      - xPack ARM GCC 14.2.1-1.1（含 arm-none-eabi-gdb，官方 GNU 同源重打包）
#      - CMake 3.31.8（不用 4.x，避免老工程 cmake_minimum_required 限制）
#      - Ninja 1.13.2
#      - Zadig 2.9（CMSIS-DAP 探针 WinUSB 驱动，接探针时才需要）
#   3. 解压就位：tools/arm-gcc、tools/cmake、tools/ninja
#   4. pyOCD venv：tools/pyocd-venv（pip 清华镜像装 pyocd，不污染系统 Python）
#   5. 生成 tools/env.bat、tools/env.sh 并把四个 bin 目录写入用户 PATH
#   6. 逐项版本验证
#
# 网络备注（本机实测）：GitHub Release 直连会被重置，走 gh-proxy 前缀；
# PyPI 走清华镜像。均可用 --force 重试。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools"
DL="$TOOLS/downloads"
GH="https://gh-proxy.com/https://"
# PyPI 镜像按序回退：阿里云 → 清华 → 官方（清华对部分网络会 403，阿里云实测稳）
PYPI_MIRRORS=("https://mirrors.aliyun.com/pypi/simple/" "https://pypi.tuna.tsinghua.edu.cn/simple" "https://pypi.org/simple")

GCC_VER="14.2.1-1.1"
CMAKE_VER="3.31.8"
NINJA_VER="1.13.2"
ZADIG_VER="2.9"

GCC_DIR_NAME="xpack-arm-none-eabi-gcc-${GCC_VER}"
CMAKE_DIR_NAME="cmake-${CMAKE_VER}-windows-x86_64"

STEP="all"; FORCE=0; EXPECT=0
for arg in "$@"; do
  if [ "$EXPECT" = 1 ]; then STEP="$arg"; EXPECT=0
  else
    case "$arg" in
      --step)  EXPECT=1 ;;
      --force) FORCE=1 ;;
      *) echo "[err] 未知参数：$arg（用法：bash bin/setup.sh [--step N|all] [--force]）"; exit 1 ;;
    esac
  fi
done
[ "$EXPECT" = 1 ] && { echo "[err] --step 缺值（N=1..6 或 all）"; exit 1; }
case "$STEP" in all|[1-6]) : ;; *) echo "[err] 非法 --step 值：$STEP"; exit 1 ;; esac

run_step() { [ "$STEP" = "all" ] || [ "$STEP" = "$1" ]; }

HUMAN=()
add_human() { HUMAN+=("$1"); }

winpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"
  else echo "$1" | sed 's|^/\([a-zA-Z]\)/|\1:/|; s|/|\\\\|g'; fi
}

# ---- 下载：fetch <destfile> <url...>（多源依次尝试，断点丢弃重下） ----
fetch() {
  local dest="$1"; shift
  if [ -s "$dest" ] && [ "$FORCE" -eq 0 ]; then
    echo "   [ok] 已存在 $(basename "$dest")，跳过下载"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  local u
  for u in "$@"; do
    echo "   [..] 下载 $u"
    rm -f "$dest.part"
    if curl -fL --retry 3 --connect-timeout 20 --speed-time 30 --speed-limit 1024 -o "$dest.part" "$u"; then
      mv -f "$dest.part" "$dest"
      echo "   [ok] → $dest（sha256: $(sha256sum "$dest" | awk '{print $1}' | cut -c1-16)...）"
      return 0
    fi
    echo "   [warn] 此源失败，尝试下一个"
  done
  rm -f "$dest.part"
  echo "   [err] 所有下载源均失败：$dest"
  return 1
}

# ---- 解压 zip：优先 Windows 自带 bsdtar，回退 PowerShell Expand-Archive ----
extract_zip() {
  local zip="$1" dest="$2"
  mkdir -p "$dest"
  if [ -x /c/Windows/System32/tar.exe ] && /c/Windows/System32/tar.exe -xf "$zip" -C "$dest" 2>/dev/null; then
    return 0
  fi
  local wz wd
  wz=$(cygpath -w "$zip"); wd=$(cygpath -w "$dest")
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
    "Expand-Archive -LiteralPath '$wz' -DestinationPath '$wd' -Force" >/dev/null
}

# ---- 若解压结果只含一个顶层目录，把其内容上提一层 ----
flatten() {
  local dir="$1" entries
  entries=$(ls -A "$dir" 2>/dev/null)
  if [ "$(printf '%s\n' "$entries" | wc -l)" -eq 1 ] && [ -d "$dir/$entries" ]; then
    mv "$dir/$entries" "$dir.__up__" && rmdir "$dir" && mv "$dir.__up__" "$dir"
  fi
}

echo "== STM32 工具链 setup（root: $ROOT） =="

# ---------- 1. 前置检查 ----------
PYEXE=""
if run_step 1; then
  echo "-- [1/6] 前置检查"
  if command -v curl >/dev/null 2>&1; then echo "   [ok] curl"; else echo "   [err] 缺 curl（git-bash 自带，请用 git-bash 运行）"; exit 1; fi
  if command -v powershell.exe >/dev/null 2>&1; then echo "   [ok] powershell"; else echo "   [err] 缺 powershell"; exit 1; fi

  for cand in python python3 "$LOCALAPPDATA/Programs/Python/Python312/python.exe" "$LOCALAPPDATA/Programs/Python/Python313/python.exe"; do
    if [ -n "$cand" ] && "$cand" -c 'import sys;sys.exit(0 if sys.version_info>=(3,11) else 1)' 2>/dev/null; then
      PYEXE="$cand"; break
    fi
  done
  if [ -n "$PYEXE" ]; then
    echo "   [ok] Python: $("$PYEXE" --version 2>&1)（$PYEXE）"
  else
    echo "   [缺] 未找到 Python>=3.11 → 人工执行："
    echo "        winget install -e --id Python.Python.3.12 --scope user"
    add_human "安装 Python>=3.11 后重跑本脚本（pyOCD 依赖）"
  fi
fi

# ---------- 2. 下载原始包 ----------
if run_step 2; then
  echo "-- [2/6] 下载安装包（gh-proxy 镜像优先）"

  # ARM GCC（>300MB，走并行分段下载，断点续传；正确资产名是 -win32-x64.zip）
  GCC_ZIP="$DL/gcc/xpack-arm-none-eabi-gcc-${GCC_VER}-win32-x64.zip"
  if [ -s "$GCC_ZIP" ]; then
    echo "   [ok] 已存在 $(basename "$GCC_ZIP")，跳过下载"
  else
    bash "$ROOT/bin/pfetch.sh" "${GH}github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v${GCC_VER}/xpack-arm-none-eabi-gcc-${GCC_VER}-win32-x64.zip" "$GCC_ZIP" 12 \
      || bash "$ROOT/bin/pfetch.sh" "https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v${GCC_VER}/xpack-arm-none-eabi-gcc-${GCC_VER}-win32-x64.zip" "$GCC_ZIP" 12 \
      || add_human "ARM GCC 下载失败：重跑 bash bin/setup.sh --step 2 可断点续传"
  fi
  # 官方 .sha 校验（拉不到 .sha 则跳过不阻塞）
  if [ -s "$GCC_ZIP" ] && [ ! -s "$GCC_ZIP.sha" ]; then
    curl -fsSL --retry 3 -o "$GCC_ZIP.sha" \
      "${GH}github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v${GCC_VER}/xpack-arm-none-eabi-gcc-${GCC_VER}-win32-x64.zip.sha" 2>/dev/null || true
  fi
  if [ -s "$GCC_ZIP" ] && [ -s "$GCC_ZIP.sha" ]; then
    want=$(awk '{print $1}' "$GCC_ZIP.sha"); got=$(sha256sum "$GCC_ZIP" | awk '{print $1}')
    if [ "$want" = "$got" ]; then
      echo "   [ok] ARM GCC SHA256 校验通过"
    else
      echo "   [err] ARM GCC SHA256 不一致，删除待重下"
      rm -f "$GCC_ZIP"
      add_human "GCC SHA 校验失败，重跑 --step 2"
    fi
  fi

  # CMake（44MB 也走并行）
  CMAKE_ZIP="$DL/cmake/cmake-${CMAKE_VER}-windows-x86_64.zip"
  if [ -s "$CMAKE_ZIP" ]; then
    echo "   [ok] 已存在 $(basename "$CMAKE_ZIP")，跳过下载"
  else
    bash "$ROOT/bin/pfetch.sh" "${GH}github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-windows-x86_64.zip" "$CMAKE_ZIP" 12 \
      || bash "$ROOT/bin/pfetch.sh" "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-windows-x86_64.zip" "$CMAKE_ZIP" 12 \
      || add_human "CMake 下载失败：重跑 bash bin/setup.sh --step 2 可断点续传"
  fi

  fetch "$DL/ninja/ninja-win.zip" \
    "${GH}github.com/ninja-build/ninja/releases/download/v${NINJA_VER}/ninja-win.zip" \
    "${GH}github.com/ninja-build/ninja/releases/download/v${NINJA_VER}/ninja-win-${NINJA_VER}.zip" \
    "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VER}/ninja-win.zip" \
    || add_human "Ninja 下载失败：手动下载 ninja-win.zip 放入 $DL/ninja/ 后重跑"

  fetch "$DL/zadig/zadig-${ZADIG_VER}.exe" \
    "https://zadig.akeo.ie/downloads/zadig-${ZADIG_VER}.exe" \
    "${GH}github.com/pbatard/libwdi/releases/download/v1.5.1/zadig-${ZADIG_VER}.exe" \
    || add_human "Zadig 下载失败（不阻塞：仅在 CMSIS-DAP 探针需要装 WinUSB 驱动时用到）"
fi

# ---------- 3. 解压就位 ----------
if run_step 3; then
  echo "-- [3/6] 解压工具链"

  if [ -x "$TOOLS/arm-gcc/bin/arm-none-eabi-gcc.exe" ] && [ "$FORCE" -eq 0 ]; then
    echo "   [ok] tools/arm-gcc 已就位，跳过"
  elif [ -s "$DL/gcc/xpack-arm-none-eabi-gcc-${GCC_VER}-win32-x64.zip" ]; then
    rm -rf "$TOOLS/arm-gcc"
    extract_zip "$DL/gcc/xpack-arm-none-eabi-gcc-${GCC_VER}-win32-x64.zip" "$TOOLS/arm-gcc" \
      && flatten "$TOOLS/arm-gcc"
    [ -x "$TOOLS/arm-gcc/bin/arm-none-eabi-gcc.exe" ] && echo "   [ok] tools/arm-gcc" || { echo "   [err] arm-gcc 解压后未找到 gcc"; add_human "arm-gcc 解压异常，检查 $TOOLS/arm-gcc"; }
  else
    echo "   [跳过] arm-gcc 安装包缺失"
  fi

  if [ -x "$TOOLS/cmake/bin/cmake.exe" ] && [ "$FORCE" -eq 0 ]; then
    echo "   [ok] tools/cmake 已就位，跳过"
  elif [ -s "$DL/cmake/cmake-${CMAKE_VER}-windows-x86_64.zip" ]; then
    rm -rf "$TOOLS/cmake"
    extract_zip "$DL/cmake/cmake-${CMAKE_VER}-windows-x86_64.zip" "$TOOLS/cmake" \
      && flatten "$TOOLS/cmake"
    [ -x "$TOOLS/cmake/bin/cmake.exe" ] && echo "   [ok] tools/cmake" || { echo "   [err] cmake 解压后未找到 cmake.exe"; add_human "cmake 解压异常，检查 $TOOLS/cmake"; }
  else
    echo "   [跳过] cmake 安装包缺失"
  fi

  if [ -x "$TOOLS/ninja/ninja.exe" ] && [ "$FORCE" -eq 0 ]; then
    echo "   [ok] tools/ninja 已就位，跳过"
  elif [ -s "$DL/ninja/ninja-win.zip" ]; then
    rm -rf "$TOOLS/ninja"
    extract_zip "$DL/ninja/ninja-win.zip" "$TOOLS/ninja"
    [ -x "$TOOLS/ninja/ninja.exe" ] && echo "   [ok] tools/ninja" || { echo "   [err] ninja 解压后未找到 ninja.exe"; add_human "ninja 解压异常，检查 $TOOLS/ninja"; }
  else
    echo "   [跳过] ninja 安装包缺失"
  fi
fi

# ---------- 4. pyOCD venv ----------
if run_step 4; then
  echo "-- [4/6] pyOCD（独立 venv，不污染系统 Python）"
  if [ -z "$PYEXE" ]; then
    echo "   [跳过] 无可用 Python，先完成第 1 步"
    add_human "装好 Python 后重跑：bash bin/setup.sh --step 4"
  elif [ -x "$TOOLS/pyocd-venv/Scripts/pyocd.exe" ] && [ "$FORCE" -eq 0 ]; then
    echo "   [ok] tools/pyocd-venv 已就位（$("$TOOLS/pyocd-venv/Scripts/pyocd.exe" --version 2>/dev/null)）"
  else
    rm -rf "$TOOLS/pyocd-venv"
    if "$PYEXE" -m venv "$TOOLS/pyocd-venv"; then
      PIP_OK=0
      for idx in "${PYPI_MIRRORS[@]}"; do
        echo "   [..] pip 安装 pyocd（index: $idx）"
        if "$TOOLS/pyocd-venv/Scripts/python.exe" -m pip install -i "$idx" --upgrade pyocd; then
          PIP_OK=1; break
        fi
        echo "   [warn] 此镜像失败，尝试下一个"
      done
      if [ "$PIP_OK" = 1 ]; then
        echo "   [ok] pyocd $("$TOOLS/pyocd-venv/Scripts/pyocd.exe" --version 2>/dev/null)"
      else
        echo "   [err] 所有 PyPI 镜像均失败"
        add_human "手动执行：$PYEXE -m venv $TOOLS/pyocd-venv && $TOOLS/pyocd-venv/Scripts/python.exe -m pip install pyocd"
      fi
    else
      echo "   [err] 创建 venv 失败"
    fi
  fi
fi

# ---------- 5. env 脚本 + 用户 PATH ----------
if run_step 5; then
  echo "-- [5/6] 生成 env 脚本并注册用户 PATH"
  WROOT=$(winpath "$ROOT")
  mkdir -p "$TOOLS"
  cat > "$TOOLS/env.bat" <<EOF
@echo off
rem 当前会话启用 STM32 工具链（新开终端未生效 PATH 时备用）
set "PATH=%PATH%;${WROOT}\\tools\\arm-gcc\\bin;${WROOT}\\tools\\cmake\\bin;${WROOT}\\tools\\ninja;${WROOT}\\tools\\pyocd-venv\\Scripts"
echo [stm32_ide] 工具链已加入本会话 PATH
EOF
  cat > "$TOOLS/env.sh" <<EOF
# 当前 git-bash 会话启用 STM32 工具链：source tools/env.sh
export PATH="\$PATH:$TOOLS/arm-gcc/bin:$TOOLS/cmake/bin:$TOOLS/ninja:$TOOLS/pyocd-venv/Scripts"
echo "[stm32_ide] 工具链已加入本会话 PATH"
EOF
  echo "   [ok] 生成 tools/env.bat / tools/env.sh"

  for rel in "arm-gcc/bin" "cmake/bin" "ninja" "pyocd-venv/Scripts"; do
    if [ -d "$TOOLS/$rel" ]; then
      dir="${WROOT}\\tools\\${rel//\//\\}"
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$ROOT/bin/add-user-path.ps1")" -Dir "$dir" || true
    fi
  done
  add_human "重开终端（或 VS Code）使 PATH 生效；临时用 source tools/env.sh / tools\\env.bat"
fi

# ---------- 6. 验证 ----------
FAIL=0
if run_step 6; then
  echo "-- [6/6] 版本验证"
  check() { # check <名称> <exe路径>
    if [ -x "$2" ]; then
      echo "   [ok] $1: $("$2" --version 2>/dev/null | head -n 1)"
    else
      echo "   [缺] $1: 未找到 $2"
      FAIL=1
    fi
  }
  check arm-none-eabi-gcc "$TOOLS/arm-gcc/bin/arm-none-eabi-gcc.exe"
  check arm-none-eabi-gdb  "$TOOLS/arm-gcc/bin/arm-none-eabi-gdb.exe"
  check cmake              "$TOOLS/cmake/bin/cmake.exe"
  check ninja              "$TOOLS/ninja/ninja.exe"
  if [ -x "$TOOLS/pyocd-venv/Scripts/pyocd.exe" ]; then
    echo "   [ok] pyocd: $("$TOOLS/pyocd-venv/Scripts/pyocd.exe" --version 2>/dev/null)"
  else
    echo "   [缺] pyocd（重跑 --step 4）"; FAIL=1
  fi
  if [ -s "$DL/zadig/zadig-${ZADIG_VER}.exe" ]; then
    echo "   [ok] zadig: $DL/zadig/zadig-${ZADIG_VER}.exe"
  else
    echo "   [提示] zadig 未下载（不阻塞）"
  fi
fi

echo
echo "== 完成。需人工完成的步骤 =="
if [ ${#HUMAN[@]} -eq 0 ]; then
  echo "   （无——全部自动步骤已成功）"
else
  for h in "${HUMAN[@]}"; do echo "   - $h"; done
fi
echo "后续一次性操作："
echo "   1. 接入 CMSIS-DAP 探针后，用 tools/downloads/zadig/zadig-${ZADIG_VER}.exe 给"
echo "      CMSIS-DAP 接口装 WinUSB 驱动（Options→List All Devices；勿动 CDC 串口）"
echo "   2. pyOCD 首次连接芯片：pyocd pack install stm32f1xx（按实际型号）"
echo "   3. STM32CubeMX 为可选（需 ST 账号手动安装，生成 CMake 工程可直接用本链编译）"
[ "$FAIL" -eq 0 ] || { echo "[警告] 存在缺失项，按上面提示修复后重跑"; exit 1; }
exit 0

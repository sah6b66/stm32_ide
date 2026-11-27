#!/usr/bin/env bash
# 并行分段下载大文件（服务端需支持 Range；gh-proxy.com 实测支持，单连接慢时提速明显）
# 用法：bash bin/pfetch.sh <url> <dest> [并发数，默认12]
# 特性：分段断点续传（重跑续传未完成分段）、按序合并、最终大小校验
set -u
URL="$1"; DEST="$2"; N="${3:-12}"
mkdir -p "$(dirname "$DEST")"
if [ -s "$DEST" ]; then echo "[pfetch] 已存在，跳过：$DEST"; exit 0; fi

SIZE=$(curl -fsSI --connect-timeout 15 "$URL" | tr -d '\r' | awk 'tolower($1)=="content-length:"{print $2}' | tail -1)
if [ -z "$SIZE" ] || ! [ "$SIZE" -gt 52428800 ] 2>/dev/null; then
  echo "[pfetch] 大小 ${SIZE:-未知}（<50MB 或未知），单线程下载"
  curl -fL --retry 3 --connect-timeout 20 -o "$DEST.part" "$URL" && mv -f "$DEST.part" "$DEST"
  exit $?
fi

CHUNK=$(( (SIZE + N - 1) / N ))
echo "[pfetch] $(( SIZE / 1048576 ))MB 分 ${N} 段（每段 $(( CHUNK / 1048576 ))MB）并行下载..."
PIDS=()
for i in $(seq -w 0 $((N-1))); do
  (
    n=$((10#$i))   # 去前导零
    s=$((n * CHUNK)); e=$(( (n+1) * CHUNK - 1 )); [ "$e" -ge "$SIZE" ] && e=$((SIZE-1))
    want=$((e - s + 1))
    for try in 1 2 3 4 5 6 7 8; do
      have=0
      [ -f "$DEST.part$i" ] && have=$(stat -c %s "$DEST.part$i" 2>/dev/null || echo 0)
      [ "$have" -eq "$want" ] && exit 0
      [ "$have" -gt "$want" ] && rm -f "$DEST.part$i" && have=0
      # 从断点继续：仅取剩余区间并追加
      curl -fsSL --retry 2 --connect-timeout 20 -r "$((s+have))-$e" "$URL" >> "$DEST.part$i" 2>/dev/null
      sleep 2
    done
    exit 1
  ) &
  PIDS+=($!)
done

FAIL=0
for p in "${PIDS[@]}"; do wait "$p" || FAIL=1; done
if [ "$FAIL" -ne 0 ]; then
  echo "[pfetch] 部分段失败，重跑本命令可续传：$URL"
  exit 1
fi

: > "$DEST"
for i in $(seq -w 0 $((N-1))); do cat "$DEST.part$i" >> "$DEST" || exit 1; done
GOT=$(stat -c %s "$DEST")
if [ "$GOT" -eq "$SIZE" ]; then
  rm -f "$DEST".part*
  echo "[pfetch] 完成：$DEST（$GOT 字节，sha256: $(sha256sum "$DEST" | awk '{print $1}' | cut -c1-16)...）"
  exit 0
else
  echo "[pfetch] 合并后大小不符（$GOT != $SIZE），删除重试"
  rm -f "$DEST" "$DEST".part*
  exit 1
fi

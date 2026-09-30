#!/usr/bin/env bash
# 調査用（#88）: 指定秒数でコマンドが終わらなければ、子孫プロセスの状態とスタックを採取して打ち切る。
set -u
limit="$1"; shift
"$@" </dev/null &
root=$!
start=$(date +%s)
descendants() { local p; for p in $(pgrep -P "$1" 2>/dev/null); do echo "$p"; descendants "$p"; done; }
while kill -0 "$root" 2>/dev/null; do
  now=$(date +%s)
  if [ $((now - start)) -ge "$limit" ]; then
    echo "::group::WATCHDOG: timeout after ${limit}s"
    ps -axo pid,ppid,stat,etime,time,command | grep -v "ps -axo" | head -80
    pids="$root $(descendants "$root")"
    echo "descendants: $pids"
    for p in $pids; do
      echo "----- pid $p: $(ps -o command= -p "$p" 2>/dev/null)"
      echo "--- lsof"; sudo lsof -p "$p" 2>&1 | head -40
      echo "--- sample"; sudo sample "$p" 3 -file "/tmp/sample-$p.txt" >/dev/null 2>&1; head -60 "/tmp/sample-$p.txt" 2>&1
    done
    echo "::endgroup::"
    for p in $pids; do kill -9 "$p" 2>/dev/null; done
    exit 124
  fi
  sleep 2
done
wait "$root"

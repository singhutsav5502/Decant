#!/bin/bash
# Runs the memprobe builds in each bottle through `decant run` (same env as the
# installer runs) and collects reports + the macOS ground truth into results/.
# Read-only for the bottles: it only writes C:\decant-logs\memprobe-*.txt.
#
#   ./run-probe.sh                 # bottles: games vol-test
#   ./run-probe.sh games           # one bottle
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DECANT="${DECANT:-$HOME/Desktop/repos/decant/bin/decant}"
DH="${DECANT_HOME:-$HOME/Library/Application Support/Decant}"
OUT="$HERE/results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
[ $# -gt 0 ] || set -- games vol-test

{
  echo "# macOS ground truth $(date)"
  sw_vers; uname -m
  sysctl hw.memsize hw.pagesize hw.ncpu hw.optional.arm64 2>/dev/null
  echo; vm_stat
  echo; memory_pressure 2>/dev/null | tail -n 3
  echo; sysctl vm.swapusage
} > "$OUT/host.txt"

for b in "$@"; do
  logs="$DH/bottles/$b/prefix/drive_c/decant-logs"
  mkdir -p "$logs"
  grep -E '^(RUNTIME|MSYNC|AVX|WINVER|BACKEND)=' "$DH/bottles/$b/bottle.conf" > "$OUT/$b.bottle.txt"
  for exe in memprobe32 memprobe32-nolaa memprobe64; do
    rep="memprobe-$exe.txt"
    rm -f "$logs/$rep"
    echo "==> $b / $exe"
    "$DECANT" run "$b" "$HERE/$exe.exe" "C:\\decant-logs\\$rep" > "$OUT/$b.$exe.launch.txt" 2>&1
    for _ in $(seq 1 120); do                    # up to 2 min (commit tests touch GBs)
      grep -q '^END' "$logs/$rep" 2>/dev/null && break
      sleep 1
    done
    if [ -f "$logs/$rep" ]; then cp "$logs/$rep" "$OUT/$b.$exe.txt"; else echo "no report" > "$OUT/$b.$exe.txt"; fi
    grep -q '^END' "$OUT/$b.$exe.txt" || echo "   !! report incomplete (crash/hang?) — see wine log below"
    # wine's stderr (fixmes, crashes) for this launch
    log=$(sed -n 's/.*log //p' "$OUT/$b.$exe.launch.txt")
    [ -n "$log" ] && [ -f "$log" ] && cp "$log" "$OUT/$b.$exe.wine.log"
  done
done

echo; echo "results: $OUT"
echo "--- key lines"
grep -H -E 'AvailablePages=|CommitLimit|ReturnLength|AvailPhys=|largest|FAILED|!!|caught=|AVX=|status=0x[^0]' "$OUT"/*.txt | sed "s|$OUT/||"

#!/bin/bash
# Live test: runs decant-shim inside real Wine (Rosetta + an installed runtime
# + mingw-w64 for the fixture). Slow (~1-2 min, mostly prefix creation).
# Run: bash tests/live.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/bin/decant"
REAL_HOME="${DECANT_HOME:-$HOME/Library/Application Support/Decant}"
RUNTIME=$(DECANT_HOME="$REAL_HOME" "$D" runtime list | head -n 1 | cut -f1)
[ -n "$RUNTIME" ] || { echo "skip: no runtime installed (decant runtime install)"; exit 0; }
command -v x86_64-w64-mingw32-gcc >/dev/null || { echo "skip: mingw-w64 not installed"; exit 0; }

T="$(mktemp -d "${TMPDIR:-/tmp}/decant-live.XXXXXX")"
trap 'DECANT_HOME="$T/home" "$D" kill live >/dev/null 2>&1; rm -rf "$T"' EXIT
export DECANT_HOME="$T/home"
# Runtimes without a bundled Wine Mono (e.g. self-built CrossOver) would stop at
# the "install Mono?" dialog during prefix creation; the test needs no .NET.
export WINEDLLOVERRIDES="mscoree=d"
mkdir -p "$DECANT_HOME/runtimes" "$DECANT_HOME/fixes"
cp -cR "$REAL_HOME/runtimes/$RUNTIME" "$DECANT_HOME/runtimes/$RUNTIME"   # APFS clone: instant
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

echo "creating throwaway bottle on $RUNTIME (wined3d, no backend needed)…"
"$D" bottle create live --backend wined3d >/dev/null 2>&1 || { echo "bottle create failed"; exit 1; }

APP="$DECANT_HOME/bottles/live/prefix/drive_c/app"
mkdir -p "$APP"
x86_64-w64-mingw32-gcc -O2 -o "$APP/child.exe" "$ROOT/tests/fixtures/echoargs.c"
cat > "$DECANT_HOME/fixes/livetest.fix" <<'EOF'
TITLE=live shim test
MATCH=child.exe
SHIM=child.exe|--injected --second|--type=
EOF
OUT="$T/out.txt"
export ECHOARGS_OUT="Z:$(printf '%s' "$OUT" | tr '/' '\\')"

# Run synchronously with the bottle's env so we get the exit code.
runw() {
  ( DECANT_SOURCE_ONLY=1 . "$D"
    bottle_env live
    cd "$APP" && "$(wine_bin "$RT_DIR")" "$@" 2>/dev/null )
}

# 1) through decant: recipe shims child.exe itself, then the shim runs the real one.
"$D" run live 'C:\app\child.exe' --user-arg >/dev/null 2>&1
for i in $(seq 1 60); do [ -s "$OUT" ] && break; sleep 0.5; done
grep -q -- 'child.decant-real.exe" --injected --second --user-arg' "$OUT" \
  && ok "decant run: shim injected recipe args before user args" || bad "shim inject" "$(cat "$OUT" 2>/dev/null)"

# 2) skip token: Chromium-style child process passes through untouched.
: > "$OUT"; runw 'C:\app\child.exe' --type=renderer
grep -q -- '--injected' "$OUT" && bad "skip token" "$(cat "$OUT")" || ok "skip= token suppresses injection"

# 3) exit code propagates through the shim (fixture exits 7).
: > "$OUT"; runw 'C:\app\child.exe'; rc=$?
[ "$rc" = 7 ] && ok "child exit code propagated" || bad "exit code" "got $rc"

# 4) env= directive and DECANT_SHIM_DISABLE.
printf 'inject=--x\nenv=DECANT_TEST_ENV=from-sidecar\n' > "$APP/child.decant-shim"
: > "$OUT"; runw 'C:\app\child.exe'
grep -q 'env=from-sidecar' "$OUT" && ok "env= sets child environment" || bad "env=" "$(cat "$OUT")"
: > "$OUT"; DECANT_SHIM_DISABLE=1 runw 'C:\app\child.exe'
grep -q -- '--x' "$OUT" && bad "DECANT_SHIM_DISABLE" "$(cat "$OUT")" || ok "DECANT_SHIM_DISABLE=1 passes through"

# 5) run --admin gets Wine's full admin token; a plain launch gets a limited one (ADR-0013).
x86_64-w64-mingw32-gcc -O2 -o "$APP/iselevated.exe" "$ROOT/tests/fixtures/iselevated.c"
: > "$OUT"; runw 'C:\app\iselevated.exe' plain
grep -q '^elevated=0 type=3' "$OUT" && ok "plain launch: limited token (why installers say 'need admin')" || bad "plain token" "$(cat "$OUT")"
: > "$OUT"; "$D" run --admin live 'C:\app\iselevated.exe' viaadmin >/dev/null 2>&1
for i in $(seq 1 60); do grep -q viaadmin "$OUT" 2>/dev/null && break; sleep 0.5; done
grep -q '^elevated=1 type=2 .*viaadmin' "$OUT" && ok "run --admin: full (elevated) admin token" || bad "admin token" "$(cat "$OUT")"

# FreeArc's largest-block search must end (patches/crossover/0002 + DECANT_WOW64_RESERVE_TOP, ADR-0020).
if command -v i686-w64-mingw32-gcc >/dev/null; then
  i686-w64-mingw32-gcc -O1 -Wl,--large-address-aware -o "$APP/largest.exe" "$ROOT/tests/fixtures/largestblock.c"
  LOUT="$T/largest.txt"; export LARGEST_OUT="Z:$(printf '%s' "$LOUT" | tr '/' '\\')"
  runw 'C:\app\largest.exe'
  grep -q '^ends' "$LOUT" 2>/dev/null && ok "32-bit LAA: no 2GB block, FreeArc's search ends ($(cat "$LOUT"))" || bad "FreeArc search" "$(cat "$LOUT" 2>/dev/null)"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]

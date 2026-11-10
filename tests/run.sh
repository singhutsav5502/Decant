#!/bin/bash
# Fast test suite: drives bin/decant against a fake Wine runtime in a throwaway
# DECANT_HOME. Needs no Rosetta, no downloads, no real Wine. Run: bash tests/run.sh
set -u   # no pipefail: `cmd | grep -q` would fail on SIGPIPE

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/bin/decant"
T="$(mktemp -d "${TMPDIR:-/tmp}/decant-test.XXXXXX")"
export DECANT_HOME="$T/home"
unset WINEDLLOVERRIDES DECANT_NO_FIXES
PASS=0; FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name" "command: $*"; fi; }
section() { printf '\n%s\n' "$1"; }
calls() { cat "$DECANT_HOME/bottles/b1/calls.txt" 2>/dev/null; }
last_call() { tail -n 1 "$DECANT_HOME/bottles/b1/calls.txt"; }
wait_calls() { local n="$1" i; for i in 1 2 3 4 5 6 7 8 9 10; do [ "$(calls | wc -l)" -ge "$n" ] && return; sleep 0.2; done; }

cleanup() { [ -n "${KEEP:-}" ] && echo "kept $T" || rm -rf "$T"; }
trap cleanup EXIT

# ---------------------------------------------------------------- fixtures
RT="$DECANT_HOME/runtimes/fake-1.0"
mkdir -p "$RT/bin" "$RT/lib/wine/x86_64-windows" "$RT/lib/wine/i386-windows"
echo builtin-d3d11 > "$RT/lib/wine/x86_64-windows/d3d11.dll"
# The fake wine runs on a *copy* of bash: macOS strips DYLD_* when starting
# SIP-protected binaries such as /bin/bash, which would hide what decant passes.
# A copied platform binary is SIGKILLed under Apple's signature, so re-sign it ad hoc.
cp /bin/bash "$T/bash"; chmod u+w "$T/bash"; codesign --force --sign - "$T/bash" 2>/dev/null
{ printf '#!%s\n' "$T/bash"; cat <<'EOF'
# Fake wine: records its argv and the env decant is responsible for.
mkdir -p "$WINEPREFIX/drive_c/windows/system32" "$WINEPREFIX/drive_c/windows/syswow64" "$WINEPREFIX/dosdevices"
[ -e "$WINEPREFIX/dosdevices/c:" ] || ln -s ../drive_c "$WINEPREFIX/dosdevices/c:"
echo "ARGS[$*] OVR[$WINEDLLOVERRIDES] FIXENV[${FIXTEST_ENV:-}] HUD[${MTL_HUD_ENABLED:-}] ASYNC[${DXVK_ASYNC:-}] CXU[${CX_REPORT_REAL_USERNAME:-}] DYLD[${DYLD_FALLBACK_LIBRARY_PATH:-}] CWD[$(pwd -P)] WINE[$0]" >> "$WINEPREFIX/../calls.txt"
EOF
} > "$RT/bin/wine"
printf '#!/bin/bash\nexit 0\n' > "$RT/bin/wineserver"
# A DXMT-capable runtime exports macdrv_view_create_metal_view from winemac.so (ADR-0011).
mkdir -p "$RT/lib/wine/x86_64-unix"; printf 'junk _macdrv_functions junk' > "$RT/lib/wine/x86_64-unix/winemac.so"
NODX="$DECANT_HOME/runtimes/nodxmt-1.0"
chmod +x "$RT/bin/wine" "$RT/bin/wineserver"
cp -R "$RT" "$NODX"; printf 'junk' > "$NODX/lib/wine/x86_64-unix/winemac.so"   # like prebuilt Gcenx Wine

mkdir -p "$DECANT_HOME/backends/dxmt/v0/x86_64-windows" "$DECANT_HOME/backends/dxmt/v0/x86_64-unix" \
         "$DECANT_HOME/backends/dxvk/d/x64" "$DECANT_HOME/backends/dxvk/d/x32"
echo dxmt-d3d11 > "$DECANT_HOME/backends/dxmt/v0/x86_64-windows/d3d11.dll"
touch "$DECANT_HOME/backends/dxmt/v0/x86_64-unix/winemetal.so"
echo v0 > "$DECANT_HOME/backends/dxmt/.decant-version"
echo dxvk-d3d11 > "$DECANT_HOME/backends/dxvk/d/x64/d3d11.dll"
echo dxvk-d3d11-32 > "$DECANT_HOME/backends/dxvk/d/x32/d3d11.dll"

# "Real" Windows binaries for shim tests: valid PE headers (copied from the
# shims) but different bytes, so decant must treat them as real apps.
fake_pe() { cat "$1" > "$2"; printf '%s' "$3" >> "$2"; }

# ---------------------------------------------------------------- bottles
section "bottles"
check "create bottle (default backend auto)" "$D" bottle create b1
check "bottle listed" sh -c "'$D' bottle list | grep -q '^b1	fake-1.0	auto'"
check "rejects bad backend" sh -c "! '$D' bottle set b1 BACKEND=bogus"
check "rejects bad bool" sh -c "! '$D' bottle set b1 RETINA=maybe"
check "rejects name with space" sh -c "! '$D' bottle create 'a b'"
check "sets METAL_HUD" "$D" bottle set b1 METAL_HUD=1
grep -q 'RetinaMode' <(calls) && ok "retina registry pushed on apply" || bad "retina registry pushed on apply"

section "backend capability (ADR-0011)"
"$D" runtime list | grep -q '^fake-1.0	local	yes' && "$D" runtime list | grep -q '^nodxmt-1.0	local	no' \
  && ok "runtime list reports DXMT capability" || bad "runtime list capability" "$("$D" runtime list)"
# zz- sorts after both: default_runtime must still prefer the DXMT-capable one, not the first name.
mkdir -p "$DECANT_HOME/runtimes/aa-nodxmt"; cp -R "$NODX/" "$DECANT_HOME/runtimes/aa-nodxmt/"
[ "$(DECANT_SOURCE_ONLY=1 bash -c '. "$1"; default_runtime' _ "$D")" = fake-1.0 ] && ok "default runtime prefers DXMT-capable over alphabetical" || bad "default runtime choice"
rm -rf "$DECANT_HOME/runtimes/aa-nodxmt"
check "bottle on non-DXMT runtime" "$D" bottle create b2 --runtime nodxmt-1.0
"$D" bottle list | grep -q '^b2	nodxmt-1.0	auto' && [ -f "$DECANT_HOME/bottles/b2/.dxvk-dlls" ] \
  && ok "auto resolves to dxvk where Metal can't present (DLLs in prefix)" || bad "auto on non-DXMT runtime" "$("$D" bottle list)"
check "refuses DXMT on incapable runtime" sh -c "! '$D' bottle set b2 BACKEND=dxmt"
check "refuses explicit --backend dxmt on incapable runtime" sh -c "! '$D' bottle create b3 --runtime nodxmt-1.0 --backend dxmt"
"$D" bottle delete b2 >/dev/null 2>&1

section "launch environment"
"$D" run b1 cmd >/dev/null 2>&1; wait_calls 1
grep -q '^# DECANT_WOW64_RESERVE_TOP=1$' "$DECANT_HOME/bottles/b1/logs/latest.log" && ok "every launch opts in to the wow64 top reservation (ADR-0020)" || bad "DECANT_WOW64_RESERVE_TOP" "$(head -12 "$DECANT_HOME/bottles/b1/logs/latest.log")"
last_call | grep -q 'CXU\[1\]' && ok "CX_REPORT_REAL_USERNAME=1 (same C:\\users\\<name> on every runtime)" || bad "CX_REPORT_REAL_USERNAME" "$(last_call)"
# Background launches must keep DYLD_* (nohup is SIP-protected and would strip it).
last_call | grep -q "DYLD\[$DECANT_HOME/runtimes/fake-1.0+dxmt/lib:" && ok "background launch keeps DYLD_FALLBACK_LIBRARY_PATH" || bad "DYLD survives background launch" "$(last_call)"
grep -qE '(^|[;&|(])[[:space:]]*nohup[[:space:]]' "$ROOT/bin/decant" && bad "bin/decant must not run nohup" || ok "no nohup command in bin/decant"

section "backends"
C="$DECANT_HOME/runtimes/fake-1.0+dxmt"
[ -f "$C/lib/wine/x86_64-unix/winemetal.so" ] && ok "dxmt overlaid onto APFS clone" || bad "dxmt overlaid onto APFS clone"
[ "$(cat "$RT/lib/wine/x86_64-windows/d3d11.dll")" = builtin-d3d11 ] && ok "base runtime untouched" || bad "base runtime untouched"
check "switch to dxvk" "$D" bottle set b1 BACKEND=dxvk
S32="$DECANT_HOME/bottles/b1/prefix/drive_c/windows/system32"
[ "$(cat "$S32/d3d11.dll")" = dxvk-d3d11 ] && ok "dxvk dll copied into prefix" || bad "dxvk dll copied into prefix"
check "switch to wined3d" "$D" bottle set b1 BACKEND=wined3d
[ "$(cat "$S32/d3d11.dll")" = builtin-d3d11 ] && ok "wine dll restored when leaving dxvk" || bad "wine dll restored when leaving dxvk"
"$D" bottle set b1 BACKEND=dxvk >/dev/null 2>&1
"$D" run b1 cmd >/dev/null 2>&1; wait_calls 1
last_call | grep -q 'OVR\[d3d11=n,b\]' && ok "dxvk overrides derived from shipped dlls" || bad "dxvk overrides" "$(last_call)"
last_call | grep -q 'ASYNC\[1\]' && ok "dxvk async env set" || bad "dxvk async env set"
"$D" bottle set b1 BACKEND=dxmt >/dev/null 2>&1

# ---------------------------------------------------------------- fixes
section "fix recipes"
check "built-in recipes lint clean" "$D" fix check
BADFIX="$T/bad.fix"
printf 'TITLE=x\nMATCH=x.exe\nSHIM=only-one-field\nBOGUS=1\n' > "$BADFIX"
out=$("$D" fix check "$BADFIX" 2>&1); rc=$?
[ $rc != 0 ] && echo "$out" | grep -q "unknown key 'BOGUS'" && echo "$out" | grep -q 'SHIM needs' \
  && ok "linter catches bad keys and SHIM" || bad "linter catches bad keys and SHIM" "$out"

PF="$DECANT_HOME/bottles/b1/prefix/drive_c/Program Files/Game"
mkdir -p "$PF/helper" "$DECANT_HOME/fixes"
fake_pe "$ROOT/share/decant-shim64.exe" "$PF/Game.exe" game
fake_pe "$ROOT/share/decant-shim64.exe" "$PF/helper/child.exe" child-v1
fake_pe "$ROOT/share/decant-shim32.exe" "$PF/helper/child32.exe" child32-v1
cp "$PF/helper/child.exe" "$T/child-v1.exe"
cat > "$DECANT_HOME/fixes/testgame.fix" <<'EOF'
TITLE=Test game
MATCH=game.exe other.exe
ARGS=-nolauncher -dx11
ENV=FIXTEST_ENV=hello world
DLLOVERRIDES=xinput1_3=n,b
SHIM=helper/child*.exe|--safe-mode|--type=
REG=HKCU\Software\TestGame|Mode|REG_SZ|safe
EOF
check "user recipe lints clean" "$D" fix check "$DECANT_HOME/fixes/testgame.fix"
check "user recipe listed as user" sh -c "'$D' fix list | grep -q '^testgame	user	'"

before=$(calls | wc -l)
"$D" run b1 'C:\Program Files\Game\Game.exe' -windowed >/dev/null 2>&1; wait_calls $((before + 2))
L=$(last_call)
echo "$L" | grep -q 'ARGS\[C:\\Program Files\\Game\\Game.exe -nolauncher -dx11 -windowed\]' \
  && ok "recipe ARGS prepended, matched case-insensitively via Windows path" || bad "recipe ARGS" "$L"
echo "$L" | grep -q "CWD\[$(cd "$PF" && pwd -P)\]" && ok "Windows-path target runs with CWD = exe dir" || bad "Windows-path CWD" "$L"
echo "$L" | grep -q 'FIXENV\[hello world\]' && ok "recipe ENV exported (with spaces)" || bad "recipe ENV" "$L"
echo "$L" | grep -q 'OVR\[dxgi,d3d11,d3d10core=b;xinput1_3=n,b\]' && ok "recipe DLLOVERRIDES appended" || bad "recipe DLLOVERRIDES" "$L"
calls | grep -q 'ARGS\[reg add HKCU\\Software\\TestGame /v Mode /t REG_SZ /d safe /f\]' && ok "recipe REG applied" || bad "recipe REG applied"
cmp -s "$PF/helper/child.exe" "$ROOT/share/decant-shim64.exe" && ok "64-bit child got 64-bit shim" || bad "64-bit child got 64-bit shim"
cmp -s "$PF/helper/child32.exe" "$ROOT/share/decant-shim32.exe" && ok "32-bit child got 32-bit shim" || bad "32-bit child got 32-bit shim"
cmp -s "$PF/helper/child.decant-real.exe" "$T/child-v1.exe" && ok "real binary preserved byte-for-byte" || bad "real binary preserved"
grep -qx 'inject=--safe-mode' "$PF/helper/child.decant-shim" && grep -qx 'skip=--type=' "$PF/helper/child.decant-shim" \
  && grep -qx 'fix=testgame' "$PF/helper/child.decant-shim" && ok "sidecar written" || bad "sidecar written" "$(cat "$PF/helper/child.decant-shim")"

before=$(calls | wc -l)
"$D" run b1 'C:\Program Files\Game\Game.exe' -dx11 >/dev/null 2>&1; wait_calls $((before + 1))
cmp -s "$PF/helper/child.decant-real.exe" "$T/child-v1.exe" && ok "second launch is idempotent (real not clobbered)" || bad "idempotent relaunch"
[ "$(calls | grep -c 'TestGame')" = 1 ] && ok "REG not re-applied when recipe unchanged" || bad "REG re-applied"
last_call | grep -q 'Game.exe -nolauncher -dx11\]' && ok "duplicate args not repeated" || bad "duplicate args" "$(last_call)"

fake_pe "$ROOT/share/decant-shim64.exe" "$PF/helper/child.exe" child-v2      # app self-update overwrites our shim
cp "$PF/helper/child.exe" "$T/child-v2.exe"
"$D" run b1 'C:\Program Files\Game\Game.exe' >/dev/null 2>&1; sleep 0.5
cmp -s "$PF/helper/child.decant-real.exe" "$T/child-v2.exe" && cmp -s "$PF/helper/child.exe" "$ROOT/share/decant-shim64.exe" \
  && ok "app update: new binary adopted as real, shim re-applied" || bad "app update handling"

check "disable fix" "$D" fix disable b1 testgame
cmp -s "$PF/helper/child.exe" "$T/child-v2.exe" && [ ! -e "$PF/helper/child.decant-shim" ] \
  && ok "disable reverts shims" || bad "disable reverts shims"
"$D" fix status b1 | grep -q '^testgame	disabled' && ok "status shows disabled" || bad "status shows disabled"
before=$(calls | wc -l)
"$D" run b1 'C:\Program Files\Game\Game.exe' >/dev/null 2>&1; wait_calls $((before + 1))
last_call | grep -q -- '-nolauncher' && bad "disabled fix not applied" || ok "disabled fix not applied"
check "re-enable fix" "$D" fix enable b1 testgame
DECANT_NO_FIXES=1 "$D" run b1 'C:\Program Files\Game\Game.exe' >/dev/null 2>&1; sleep 0.5
[ ! -e "$PF/helper/child.decant-shim" ] && ok "DECANT_NO_FIXES=1 bypasses recipes" || bad "DECANT_NO_FIXES bypass"

printf 'TITLE=User Steam override\nMATCH=steam.exe\n' > "$DECANT_HOME/fixes/steam.fix"
"$D" fix list | grep -q '^steam	user	steam.exe	User Steam override' && ok "user recipe overrides built-in with same id" || bad "user override"

section "install from recipe"
mkdir -p "$DECANT_HOME/downloads"; echo fake > "$DECANT_HOME/downloads/Setup.exe"   # cached: no network
cat > "$DECANT_HOME/fixes/instapp.fix" <<'EOF'
TITLE=Installable app
MATCH=inst.exe
INSTALL_URL=https://example.invalid/dl/Setup.exe?x=1
INSTALL_ARGS=/S /D=C:\Inst
PROGRAM=Inst|C:\Inst\inst.exe
EOF
check "install recipe lints clean" "$D" fix check "$DECANT_HOME/fixes/instapp.fix"
check "decant install runs installer" "$D" install b1 instapp
calls | grep -q 'Setup.exe /S /D=C:\\Inst\]' && ok "installer got INSTALL_ARGS" || bad "installer args" "$(calls | grep Setup)"
"$D" program list b1 | grep -q '^Inst	C:\\Inst\\inst.exe' && ok "PROGRAM registered as launch target" || bad "PROGRAM registered"
check "install without INSTALL_URL fails" sh -c "! '$D' install b1 testgame"

section "library + store integrations (ADR-0010)"
SP="$DECANT_HOME/bottles/b1/prefix/drive_c/Program Files (x86)/Steam"
mkdir -p "$SP/steamapps/common/Fake Game" "$SP/appcache/librarycache/111/abc" "$DECANT_HOME/bottles/b1/prefix/drive_c/Lib2/steamapps/common/Other"
touch "$SP/steam.exe" "$SP/appcache/librarycache/111/abc/library_capsule.jpg"
acf() { printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n\t"StateFlags"\t\t"%s"\n\t"installdir"\t\t"%s"\n}\n' "$2" "$3" "$4" "$5" > "$1"; }
acf "$SP/steamapps/appmanifest_111.acf" 111 "Fake Game" 4 "Fake Game"
acf "$SP/steamapps/appmanifest_228980.acf" 228980 "Steamworks Common Redistributables" 4 "Steamworks Shared"
acf "$SP/steamapps/appmanifest_222.acf" 222 "Half Downloaded" 1026 "Half"
acf "$DECANT_HOME/bottles/b1/prefix/drive_c/Lib2/steamapps/appmanifest_333.acf" 333 "Other Lib Game" 4 "Other"
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"C:\\\\Lib2"\n\t}\n}\n' > "$SP/steamapps/libraryfolders.vdf"
"$D" program add b1 Steam 'C:\Program Files (x86)\Steam\steam.exe' >/dev/null
"$D" integration list | grep -q '^b1	steam	Steam	C:\\Program Files (x86)\\Steam\\steam.exe' && ok "steam integration detected" || bad "integration detect" "$("$D" integration list)"
LIB=$("$D" library --bottle b1)
echo "$LIB" | grep -q '^b1	steam:111	Fake Game	steam	.*Fake Game	.*library_capsule.jpg	0$' && ok "installed steam game listed with cover art" || bad "steam game row" "$LIB"
echo "$LIB" | grep -q 'steam:333	Other Lib Game' && ok "extra library folders from libraryfolders.vdf" || bad "extra library" "$LIB"
echo "$LIB" | grep -qE 'Steamworks|Half Downloaded' && bad "tools/partial installs hidden" "$LIB" || ok "tools and partial installs hidden"
echo "$LIB" | grep -q 'manual:Steam' && bad "launcher hidden from games" || ok "launcher (steam.exe) not listed as a game"
before=$(calls | wc -l)
"$D" play b1 steam:111 >/dev/null 2>&1; wait_calls $((before + 1))
last_call | grep -q 'steam.exe .*-applaunch 111\]' && ok "play steam game -> steam.exe -applaunch" || bad "play steam" "$(last_call)"
check "library add (non-store exe)" "$D" library add b1 "My Game" "$PF/Game.exe"
"$D" library --bottle b1 | grep -q '^b1	manual:My Game	My Game	manual	' && ok "manual game listed" || bad "manual game listed"
check "library add rejects missing file" sh -c "! '$D' library add b1 Nope /no/such.exe"
check "library remove manual" "$D" library remove b1 "manual:My Game"
check "library remove refuses store games" sh -c "! '$D' library remove b1 steam:111"
( exec -a 'C:\Program Files (x86)\Steam\steamapps\common\Fake Game\fake.exe' sleep 30 ) & FAKEPID=$!
sleep 0.3
"$D" library --bottle b1 | grep -q 'steam:111	.*	1$' && ok "running game detected" || bad "running detection" "$("$D" library --bottle b1 | grep 111)"
"$D" stop b1 steam:111 >/dev/null 2>&1; sleep 0.3
# kill -0 would succeed on the unreaped zombie; wait gives the real outcome (143 = SIGTERM).
wait $FAKEPID 2>/dev/null; [ $? = 143 ] && ok "stop kills the game process" || bad "stop kills the game process"

section "default bottle"
[ "$("$D" bottle default)" = b1 ] && ok "only bottle is the default automatically" || bad "auto default" "$("$D" bottle default)"
check "create second bottle with --default" "$D" bottle create b9 --default
[ "$("$D" bottle default)" = b9 ] && ok "--default sets it" || bad "--default"
"$D" bottle list | grep -q '^b9	fake-1.0	auto	default$' && ok "bottle list marks the default" || bad "list marks default" "$("$D" bottle list)"
check "set default explicitly" "$D" bottle default b1
[ "$("$D" bottle default)" = b1 ] && ok "default switched to b1" || bad "switch default"
check "default refuses unknown bottle" sh -c "! '$D' bottle default nope"
"$D" bottle default b9 >/dev/null 2>&1; "$D" bottle delete b9 >/dev/null 2>&1
[ "$("$D" bottle default)" = b1 ] && ok "deleting the default falls back to the only remaining bottle" || bad "delete default fallback" "$("$D" bottle default)"
"$D" doctor 2>/dev/null | grep -q '^Default      b1' && ok "doctor shows the default bottle" || bad "doctor default"

section "controllers"
FH="$T/fakehidutil"; { printf '#!/bin/sh\ncat <<"EOF"\n'; cat <<'EOF'
Services:
VendorID ProductID LocationID UsagePage Usage RegistryID  Transport Class                    Product                    UserClass
0x45e    0xb13     0x0        0x1       0x5   0x1000a1b2  Bluetooth AppleUserHIDEventService Xbox Wireless Controller   AppleUserHIDEventDriver
0x5ac    0x281     0x0        0x1       0x6   0x1000a1b3  USB       AppleUserHIDEventService Apple Keyboard             AppleUserHIDEventDriver
EOF
printf 'EOF\n'; } > "$FH"; chmod +x "$FH"
before=$(calls | wc -l)
OUTC=$(DECANT_HIDUTIL="$FH" "$D" controllers b1 2>&1); wait_calls $((before + 1))
echo "$OUTC" | grep -q '  Xbox Wireless Controller  \[Bluetooth, vendor 0x45e product 0xb13\]' && ok "lists gamepads macOS sees (name, transport, ids)" || bad "controllers list" "$OUTC"
echo "$OUTC" | grep -q 'Apple Keyboard' && bad "keyboards are not controllers" || ok "keyboards are not controllers"
last_call | grep -q 'ARGS\[control joy.cpl\]' && ok "opens Wine's Game Controllers panel" || bad "joy.cpl" "$(last_call)"
printf '#!/bin/sh\necho Services:\n' > "$FH"
DECANT_HIDUTIL="$FH" "$D" controllers b1 2>&1 | grep -q 'macOS sees no game controllers' && ok "says so when none are connected" || bad "no controllers message"

section "programs"
check "program add with default args" "$D" program add b1 Game 'C:\Program Files\Game\Game.exe' -fullscreen
before=$(calls | wc -l)
"$D" run b1 Game >/dev/null 2>&1; wait_calls $((before + 1))
last_call | grep -q 'Game.exe -nolauncher -dx11 -fullscreen\]' && ok "label resolves with saved args + recipe args" || bad "label launch" "$(last_call)"

section "run as administrator (ADR-0013)"
DC="$DECANT_HOME/bottles/b1/prefix/drive_c"
mkdir -p "$T/dl/MyInstaller"; echo exe > "$T/dl/MyInstaller/setup.exe"; echo data > "$T/dl/MyInstaller/data.bin"
xattr -w com.apple.quarantine "0081;00000000;Safari;" "$T/dl/MyInstaller/setup.exe" 2>/dev/null
mkdir -p "$DC/Program Files/RO"; echo x > "$DC/Program Files/RO/locked.dat"; chmod a-w "$DC/Program Files/RO/locked.dat"
before=$(calls | wc -l)
"$D" run --admin b1 "$T/dl/MyInstaller/setup.exe" /S >/dev/null 2>&1; wait_calls $((before + 1))
last_call | grep -q 'decant-elevate64.exe C:\\decant-stage\\MyInstaller-setup\\setup.exe /S\]' \
  && ok "--admin launches through decant-elevate with the staged Windows path" || bad "--admin launch" "$(last_call)"
[ -f "$DC/decant-stage/MyInstaller-setup/data.bin" ] && ok "installer's own folder staged whole (data files kept)" || bad "folder staged"
xattr -p com.apple.quarantine "$DC/decant-stage/MyInstaller-setup/setup.exe" >/dev/null 2>&1 && bad "quarantine cleared on staged copy" || ok "quarantine cleared on staged copy"
[ -w "$DC/Program Files/RO/locked.dat" ] && ok "read-only files in the bottle made writable" || bad "read-only fixed"
mkdir -p "$T/h/Downloads"; for f in setup_game.exe setup_game-1.bin unrelated.zip; do echo "$f" > "$T/h/Downloads/$f"; done
HOME="$T/h" "$D" run --admin b1 "$T/h/Downloads/setup_game.exe" >/dev/null 2>&1; sleep 0.5
SG="$DC/decant-stage/Downloads-setup_game"
[ -f "$SG/setup_game.exe" ] && [ -f "$SG/setup_game-1.bin" ] && [ ! -e "$SG/unrelated.zip" ] \
  && ok "from Downloads: only the installer and its parts are staged" || bad "shared-folder staging" "$(ls "$SG" 2>&1)"
before=$(calls | wc -l)
"$D" run --admin b1 'C:\Program Files\Game\Game.exe' >/dev/null 2>&1; wait_calls $((before + 1))
last_call | grep -q 'decant-elevate64.exe C:\\Program Files\\Game\\Game.exe' && ok "--admin passes Windows paths through unstaged" || bad "--admin windows path" "$(last_call)"
"$D" repair b1 2>&1 | grep -q 'permissions OK' && ok "repair reports OK on a healthy bottle" || bad "repair OK"
[ -z "$("$D" repair b1 --print-sudo)" ] && ok "repair --print-sudo is empty when no sudo is needed" || bad "repair --print-sudo"

section "installer logs, status, diagnostics (ADR-0014)"
mkdir -p "$T/inst"; printf 'MZ junk Inno Setup Setup Data junk' > "$T/inst/inno_setup.exe"
printf 'MZ junk Nullsoft Install System junk' > "$T/inst/nsis_setup.exe"; printf 'msi' > "$T/inst/pkg.msi"
[ "$(DECANT_SOURCE_ONLY=1 bash -c '. "$1"; installer_kind "$2"; installer_kind "$3"; installer_kind "$4"' _ "$D" "$T/inst/inno_setup.exe" "$T/inst/nsis_setup.exe" "$T/inst/pkg.msi" | tr '\n' ' ')" = "inno nsis msi " ] \
  && ok "installer type detection (Inno / NSIS / MSI)" || bad "installer_kind"
before=$(calls | wc -l)
"$D" run b1 "$T/inst/inno_setup.exe" /SILENT >/dev/null 2>&1; wait_calls $((before + 1))
last_call | grep -qE 'inno_setup.exe /SILENT /LOG=C:\\decant-logs\\[0-9-]+-inno_setup.log\]' && ok "Inno Setup gets /LOG=C:\\decant-logs\\…" || bad "inno /LOG" "$(last_call)"
[ -L "$DECANT_HOME/bottles/b1/logs/installer-latest.log" ] && ok "logs/installer-latest.log links the new installer log" || bad "installer-latest symlink"
grep -q '^# installer-log: .*/drive_c/decant-logs/.*inno_setup.log' "$DECANT_HOME/bottles/b1/logs/latest.log" && ok "launch log header names the installer log" || bad "header installer-log"
before=$(calls | wc -l)
"$D" run b1 "$T/inst/inno_setup.exe" '/LOG=C:\mine.log' >/dev/null 2>&1; wait_calls $((before + 1))
[ "$(last_call | grep -o '/LOG=' | wc -l | tr -d ' ')" = 1 ] && ok "user's own /LOG is kept, not doubled" || bad "user /LOG" "$(last_call)"
before=$(calls | wc -l)
"$D" run b1 "$T/inst/pkg.msi" >/dev/null 2>&1; wait_calls $((before + 1))
last_call | grep -qE 'msiexec /i .*pkg.msi /l\*v C:\\decant-logs\\' && ok "MSI gets /l*v log" || bad "msi log" "$(last_call)"
before=$(calls | wc -l)
"$D" run b1 "$T/inst/nsis_setup.exe" >/dev/null 2>&1; wait_calls $((before + 1))
last_call | grep -q 'decant-logs' && bad "NSIS left alone (no log switch)" || ok "NSIS left alone (no log switch)"
before=$(calls | wc -l)
"$D" run --admin b1 "$T/inst/inno_setup.exe" >/dev/null 2>&1; wait_calls $((before + 1))
last_call | grep -qE 'decant-elevate64.exe C:\\decant-stage\\inst-inno_setup\\inno_setup.exe /LOG=C:\\decant-logs\\' && ok "--admin installers get the log switch too" || bad "admin + log" "$(last_call)"
before=$(calls | wc -l)
"$D" run --admin b1 "$T/inst/pkg.msi" >/dev/null 2>&1; wait_calls $((before + 1))
last_call | grep -qE 'decant-elevate64.exe C:\\windows\\system32\\msiexec.exe /i C:\\decant-stage\\inst-pkg\\pkg.msi /l\*v ' && ok "--admin MSI elevates msiexec /i" || bad "admin msi" "$(last_call)"

"$D" status b1 --tsv | grep -q '^state	stopped' && ok "status: stopped when nothing runs" || bad "status stopped" "$("$D" status b1 --tsv)"
OPENF="$DC/held.txt"; echo x > "$OPENF"
( exec -a 'C:\Games\Idle\idle.exe' tail -f "$OPENF" ) > /dev/null 2>&1 & IDLEPID=$!
sleep 1
ST1=$("$D" status b1 --tsv)
echo "$ST1" | grep -q "^proc	$IDLEPID	.*	idle.exe	0$" && ok "status maps a process to its bottle via open files" || bad "status mapping" "$ST1"
echo "$ST1" | grep -q '^state	waiting' && ok "status: idle program => waiting for you" || bad "status waiting" "$ST1"
( exec -a 'C:\Games\Busy\busy.exe' "$T/bash" -c 'exec 3<"$1"; while :; do :; done' _ "$OPENF" ) & BUSYPID=$!
sleep 2
"$D" status b1 --tsv | grep -q '^state	busy' && ok "status: CPU-heavy program => working" || bad "status busy" "$("$D" status b1 --tsv)"
kill $IDLEPID $BUSYPID 2>/dev/null; wait $IDLEPID $BUSYPID 2>/dev/null
"$D" status b1 | grep -q 'Bottle b1:' && ok "status: human-readable summary" || bad "status human"
ZIP="$T/diag.zip"; "$D" diagnostics b1 --out "$ZIP" >/dev/null 2>&1
LIST=$(unzip -l "$ZIP" 2>/dev/null)
echo "$LIST" | grep -q 'decant-b1/summary.txt' && echo "$LIST" | grep -q 'decant-b1/bottle.conf' && echo "$LIST" | grep -q 'decant-b1/logs/2' && echo "$LIST" | grep -q 'decant-b1/installer-logs/' \
  && ok "diagnostics zip has summary, settings, launch + installer logs" || bad "diagnostics zip" "$LIST"

section "BACKEND=auto: one runtime, best layer per API (ADR-0019)"
B1="$DECANT_HOME/bottles/b1"; R1="$DECANT_HOME/runtimes"
"$D" bottle set b1 BACKEND=auto >/dev/null 2>&1
lc() { local before; before=$(calls | wc -l); "$@" >/dev/null 2>&1; wait_calls $((before + 1)); last_call; }
L=$(lc "$D" run b1 cmd)
echo "$L" | grep -q "WINE\[$R1/fake-1.0+dxmt/bin/wine\]" && echo "$L" | grep -q 'OVR\[dxgi,d3d11,d3d10core=b\]' \
  && ok "auto without D3DMetal: DXMT for DX10/11" || bad "auto -> dxmt" "$L"
grep -q '^# backend: dxmt$' "$B1/logs/latest.log" && ok "launch log names the resolved backend" || bad "log backend" "$(head -4 "$B1/logs/latest.log")"
mkdir -p "$DECANT_HOME/backends/d3dmetal/wine/x86_64-windows" "$DECANT_HOME/backends/d3dmetal/external/D3DMetal.framework"
echo d3dm-d3d12 > "$DECANT_HOME/backends/d3dmetal/wine/x86_64-windows/d3d12.dll"
echo gptk:test > "$DECANT_HOME/backends/d3dmetal/.decant-version"
L=$(lc "$D" run b1 cmd)
echo "$L" | grep -q "WINE\[$R1/fake-1.0+d3dmetal/bin/wine\]" && echo "$L" | grep -q 'OVR\[dxgi,d3d11,d3d12,d3d10core=b\]' \
  && [ -d "$R1/fake-1.0+d3dmetal/lib/external/D3DMetal.framework" ] \
  && ok "importing D3DMetal upgrades the next launch, no setting changed" || bad "auto -> d3dmetal" "$L"
grep -q '^BACKEND=auto$' "$B1/bottle.conf" && ok "bottle.conf still says auto" || bad "conf auto"
check "D3DMetal refused on a runtime without the macdrv exports" sh -c "'$D' bottle create b5 --runtime nodxmt-1.0 >/dev/null 2>&1; ! '$D' bottle set b5 BACKEND=d3dmetal"
L=$(DECANT_HOME="$DECANT_HOME" bash -c '"$1" run b5 cmd >/dev/null 2>&1; sleep 0.5; tail -n 1 "$2"' _ "$D" "$DECANT_HOME/bottles/b5/calls.txt")
echo "$L" | grep -q 'OVR\[d3d11=n,b\]' && ok "auto on that runtime: DXVK" || bad "auto -> dxvk" "$L"
"$D" bottle set b5 RUNTIME=fake-1.0 >/dev/null 2>&1
[ ! -f "$DECANT_HOME/bottles/b5/.dxvk-dlls" ] && [ "$(cat "$DECANT_HOME/bottles/b5/prefix/drive_c/windows/system32/d3d11.dll")" = builtin-d3d11 ] \
  && ok "moving to a Metal-capable runtime puts Wine's DLLs back" || bad "dxvk restored on runtime change"
"$D" bottle delete b5 >/dev/null 2>&1
rm -rf "$DECANT_HOME/backends/d3dmetal" "$R1"/fake-1.0+d3dmetal
check "backend list does not list auto" sh -c "! '$D' backend list | grep -q '^auto'"

section "game discovery (program scan)"
DC="$DECANT_HOME/bottles/b1/prefix/drive_c"
console_pe() { # make a copy of a GUI PE with subsystem = 3 (console)
  cp "$1" "$2"; local off; off=$(od -An -tu4 -j60 -N4 "$2" | tr -d ' ')
  printf '\003' | dd of="$2" bs=1 seek=$((off + 24 + 68)) conv=notrunc 2>/dev/null
}
G="$DC/Program Files/Cool Game"; mkdir -p "$G/bin" "$DC/Program Files/Internet Explorer" "$DC/Games/Retro Thing"
fake_pe "$ROOT/share/decant-shim64.exe" "$G/CoolGame.exe" main
fake_pe "$ROOT/share/decant-shim64.exe" "$G/bin/launcher2.exe" other
for x in unins000.exe CrashReporter.exe UnityCrashHandler64.exe vc_redist.x64.exe; do fake_pe "$ROOT/share/decant-shim64.exe" "$G/$x" "$x"; done
console_pe "$G/CoolGame.exe" "$G/servertool.exe"
fake_pe "$ROOT/share/decant-shim64.exe" "$DC/Program Files/Internet Explorer/iexplore.exe" ie
fake_pe "$ROOT/share/decant-shim64.exe" "$DC/Games/Retro Thing/retro.exe" retro
[ "$(pe_sub=$(od -An -tu4 -j60 -N4 "$G/servertool.exe" | tr -d ' '); od -An -tu2 -j$((pe_sub + 92)) -N2 "$G/servertool.exe" | tr -d ' ')" = 3 ] \
  && ok "fixture: console subsystem patched" || bad "fixture: console subsystem patched"
SCAN=$("$D" program scan b1)
[ "$(echo "$SCAN" | grep -c .)" = 2 ] && echo "$SCAN" | grep -q 'Cool Game/CoolGame.exe$' && echo "$SCAN" | grep -q 'Retro Thing/retro.exe$' \
  && ok "one best exe per folder (folder-named exe wins), C:\\Games searched" || bad "best-per-folder scan" "$SCAN"
echo "$SCAN" | grep -qiE 'Steam|Internet Explorer|/Game/' && bad "skips stubs, store-owned and known folders" "$SCAN" || ok "skips stubs, store-owned and known folders"
ALL=$("$D" program scan b1 --all)
echo "$ALL" | grep -q 'launcher2.exe' && ok "--all lists secondary exes" || bad "--all" "$ALL"
echo "$ALL" | grep -qiE 'unins000|CrashReporter|UnityCrash|vc_redist|servertool' && bad "--all still drops helpers and console tools" "$ALL" || ok "--all still drops helpers and console tools"
sleep 1; T0=$(date +%s); sleep 1
mkdir -p "$DC/Program Files/Fresh Install"; fake_pe "$ROOT/share/decant-shim64.exe" "$DC/Program Files/Fresh Install/Fresh.exe" fresh
SINCE=$("$D" program scan b1 --since "$T0")
[ "$(echo "$SINCE" | grep -c .)" = 1 ] && echo "$SINCE" | grep -q 'Fresh.exe$' && ok "--since only shows what an installer just added" || bad "--since" "$SINCE"
# An install that left only an uninstaller + bundled tools (e.g. an installer that didn't finish
# unpacking) must offer nothing, not a GUI tool from _Redist.
H="$DC/Program Files/Half Done"; mkdir -p "$H/_Redist" "$H/_CommonRedist/DirectX"
for x in "$H/unins000.exe" "$H/_Redist/QuickSFV.EXE" "$H/_CommonRedist/DirectX/tool.exe"; do fake_pe "$ROOT/share/decant-shim64.exe" "$x" x; done
HALF=$("$D" program scan b1 --all)
echo "$HALF" | grep -q 'Half Done' && bad "bundled-prerequisite folders are skipped" "$HALF" || ok "bundled-prerequisite folders are skipped"
# Roman numerals: "Hades II" must pick Hades2.exe over a bigger crash-reporter exe (F10.exe).
R="$DC/Program Files/Hades II/Release"; mkdir -p "$R"
fake_pe "$ROOT/share/decant-shim64.exe" "$R/Hades2.exe" game
{ cat "$ROOT/share/decant-shim64.exe"; head -c 2097152 /dev/zero; } > "$R/F10.exe"
ROMAN=$("$D" program scan b1 --since "$T0")
echo "$ROMAN" | grep -q 'Hades II/Release/Hades2.exe$' && ok "roman numeral folder name matches digit exe name" || bad "roman numeral match" "$ROMAN"

section "setup (ADR-0023)"
# Separate throwaway home, with the fake runtimes and backends already "installed" so nothing downloads.
SH="$T/setup-home"; mkdir -p "$SH/runtimes" "$SH/backends"
cp -R "$RT" "$SH/runtimes/"; cp -R "$DECANT_HOME/backends/dxmt" "$DECANT_HOME/backends/dxvk" "$SH/backends/"
SOUT=$(DECANT_HOME="$SH" "$D" setup 2>&1) && ok "setup succeeds with everything but the bottle present" || bad "setup run" "$SOUT"
DECANT_HOME="$SH" "$D" bottle list | grep -q '^games	fake-1.0	auto	default$' \
  && ok "setup creates games on the Metal-capable runtime, BACKEND=auto, as default" || bad "setup bottle" "$(DECANT_HOME="$SH" "$D" bottle list)"
grep -q '^MSYNC=1$' "$SH/bottles/games/bottle.conf" && grep -q '^WINVER=win10$' "$SH/bottles/games/bottle.conf" \
  && ok "games bottle has the recommended settings" || bad "games settings" "$(cat "$SH/bottles/games/bottle.conf")"
DECANT_HOME="$SH" "$D" bottle set games RETINA=1 >/dev/null 2>&1
SOUT=$(DECANT_HOME="$SH" "$D" setup 2>&1) && echo "$SOUT" | grep -q 'games (exists, settings unchanged)' \
  && grep -q '^RETINA=1$' "$SH/bottles/games/bottle.conf" && ok "re-running setup changes nothing" || bad "setup re-run" "$SOUT"
DECANT_HOME="$SH" "$D" bottle create other --default >/dev/null 2>&1
DECANT_HOME="$SH" "$D" setup >/dev/null 2>&1
[ "$(DECANT_HOME="$SH" "$D" bottle default)" = other ] && ok "setup keeps a default the user picked" || bad "setup overrode default"
# No Metal-capable Wine: setup still makes a working games bottle and says how to get one.
SH2="$T/setup-home2"; mkdir -p "$SH2/runtimes" "$SH2/backends"
cp -R "$NODX" "$SH2/runtimes/"; cp -R "$DECANT_HOME/backends/dxmt" "$DECANT_HOME/backends/dxvk" "$SH2/backends/"
SOUT=$(DECANT_HOME="$SH2" "$D" setup 2>&1)
echo "$SOUT" | grep -q 'decant setup --build-wine' && DECANT_HOME="$SH2" "$D" bottle list | grep -q '^games	nodxmt-1.0	auto	default$' \
  && ok "without Metal Wine: games still created, build hint shown" || bad "setup without Metal Wine" "$SOUT"
check "setup rejects unknown options" sh -c "! DECANT_HOME='$SH' '$D' setup --bogus"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]

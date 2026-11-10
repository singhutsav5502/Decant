#!/bin/bash
# Build Wine from source for macOS and register it as a decant runtime.
#
#   scripts/build-wine.sh crossover 26.1.0     # CodeWeavers' FOSS CrossOver Wine: DXMT-capable, msync
#   scripts/build-wine.sh upstream 11.21       # plain WineHQ Wine (no DXMT: winemac exports nothing)
#
# Why and how: docs/adr/0012-build-crossover-wine-with-prebuilt-x86-libs.md
#
# Wine runs x86 Windows code in-process, so on Apple Silicon the build is
# x86_64 and runs under Rosetta. We don't need an x86_64 Homebrew: tools come
# from the normal arm64 Homebrew (bison, mingw-w64), headers too (they're
# arch-independent), and the x86_64 libraries we link against (freetype,
# gnutls, SDL2, MoltenVK, ...) are copied from an installed prebuilt runtime.
# Those libraries are bundled into the result, so it's self-contained.

set -euo pipefail

MODE="${1:-}"; VERSION="${2:-}"
[ -n "$MODE" ] && [ -n "$VERSION" ] || { sed -n '2,6p' "$0"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
DECANT="$HERE/../bin/decant"
DECANT_HOME="${DECANT_HOME:-$HOME/Library/Application Support/Decant}"
WORK="${WORK:-$HOME/Library/Caches/Decant/build}"      # no spaces: autotools can't cope
SRC="$WORK/src-$MODE-$VERSION"
BUILD="$WORK/build-$MODE-$VERSION"
DEST="$WORK/install-$MODE-$VERSION"
LIBS="$WORK/x86libs"
BREW=/opt/homebrew/bin/brew
JOBS="$(sysctl -n hw.ncpu)"
NAME="$MODE-$VERSION"

say() { printf '==> %s\n' "$*"; }
die() { printf 'build-wine: %s\n' "$*" >&2; exit 1; }

# ---- preflight
arch -x86_64 /bin/bash -c true 2>/dev/null || die "Rosetta 2 missing: softwareupdate --install-rosetta --agree-to-license"
xcode-select -p >/dev/null 2>&1 || die "install Xcode or its command line tools"
[ -x "$BREW" ] || die "Homebrew not found at $BREW"
case "$WORK" in *' '*) die "WORK must not contain spaces ($WORK)";; esac

# x86_64 libraries come from a prebuilt runtime (install one if needed).
first_runtime_lib() { local d; for d in "$DECANT_HOME"/runtimes/*/lib; do case "$d" in *+*) ;; *) [ -d "$d" ] && { echo "$d"; return; };; esac; done; }
LIBSRC=$(first_runtime_lib)
if [ -z "$LIBSRC" ]; then
  say "no prebuilt runtime to borrow x86_64 libraries from; installing one"
  "$DECANT" runtime install staging >/dev/null
  LIBSRC=$(first_runtime_lib)
fi
say "x86_64 libraries from $LIBSRC"
rm -rf "$LIBS"; mkdir -p "$LIBS"; cp -c "$LIBSRC"/*.dylib "$LIBS/"

say "build tools and headers (arm64 Homebrew)"
"$BREW" install --quiet bison mingw-w64 freetype gnutls sdl2 >/dev/null
B=/opt/homebrew/opt

# ---- fetch source
mkdir -p "$WORK"
if [ ! -d "$SRC" ]; then
  case "$MODE" in
    upstream)
      git clone --depth 1 --branch "wine-$VERSION" https://gitlab.winehq.org/wine/wine.git "$SRC";;
    crossover)
      tarball="$WORK/crossover-sources-$VERSION.tar.gz"
      [ -s "$tarball" ] || curl -fL -o "$tarball" "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$VERSION.tar.gz"
      rm -rf "$SRC.tmp"; mkdir -p "$SRC.tmp"; tar -xzf "$tarball" -C "$SRC.tmp" sources/wine
      mv "$SRC.tmp/sources/wine" "$SRC"; rm -rf "$SRC.tmp";;
    *) die "mode must be crossover or upstream";;
  esac
fi

# ---- Decant's patches (patches/<mode>/*.patch, applied once; see docs/adr/0015)
for p in "$HERE/../patches/$MODE"/*.patch; do
  [ -f "$p" ] || continue
  if patch -d "$SRC" -p1 -N --dry-run --silent < "$p" >/dev/null 2>&1; then
    patch -d "$SRC" -p1 -N --silent < "$p"; say "applied $(basename "$p")"
  elif patch -d "$SRC" -p1 -R --dry-run --silent < "$p" >/dev/null 2>&1; then
    say "already applied: $(basename "$p")"
  else
    die "patch $(basename "$p") doesn't apply to $MODE $VERSION; update it (docs/adr/0015)"
  fi
done

# ---- configure
export PATH="$B/bison/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export MACOSX_DEPLOYMENT_TARGET=11.0
export CC="clang -arch x86_64" CXX="clang++ -arch x86_64" OBJC="clang -arch x86_64"
export CFLAGS="-O2 -g0 -Wno-deprecated-declarations -Wno-incompatible-function-pointer-types -Wno-int-conversion"
export CROSSCFLAGS="-O2 -g0"
export LDFLAGS="-L$LIBS -Wl,-headerpad_max_install_names"
export FREETYPE_CFLAGS="-I/opt/homebrew/include/freetype2" FREETYPE_LIBS="-L$LIBS -lfreetype"
export GNUTLS_CFLAGS="-I$B/gnutls/include -I$B/nettle/include -I$B/p11-kit/include/p11-kit-1 -I$B/libtasn1/include -I$B/libidn2/include"
export GNUTLS_LIBS="-L$LIBS -lgnutls"
export SDL2_CFLAGS="-I/opt/homebrew/include/SDL2 -D_THREAD_SAFE" SDL2_LIBS="-L$LIBS -lSDL2"
export PKG_CONFIG=/usr/bin/false     # never pick up arm64 .pc files

rm -rf "$BUILD"; mkdir -p "$BUILD"; cd "$BUILD"
say "configuring $NAME"
# - OpenGL: Wine 11's macOS GL path needs EGL, which we don't have. DXMT/DXVK don't use GL.
# - GStreamer: skipped for now (video playback in some games).
# - SDL2: its soname must be pinned (see below for why).
arch -x86_64 "$SRC/configure" --prefix="$DEST" \
  --enable-archs=i386,x86_64 --disable-tests \
  --without-x --without-wayland --with-mingw --with-coreaudio --with-freetype --with-gnutls \
  --without-opengl --with-opencl --with-sdl --with-vulkan --with-unwind --without-gstreamer \
  --without-alsa --without-capi --without-dbus --without-fontconfig --without-gphoto --without-gssapi \
  --without-krb5 --without-netapi --without-oss --without-pcap --without-pulse --without-sane \
  --without-udev --without-usb --without-v4l2 --without-cups \
  ac_cv_lib_soname_SDL2=libSDL2-2.0.0.dylib > "$WORK/configure-$NAME.log"

# configure derives sonames by parsing `otool -L`. The prebuilt libraries have
# bare install names, so it records "\tlibfreetype.dylib (compatibility …)",
# and Wine would dlopen() that literal string and silently lose fonts/TLS/Vulkan.
# (Passing ac_cv_lib_soname_* for these on the command line broke configure.)
python3 - "$BUILD/include/config.h" "$LIBS" <<'PY'
import os, re, sys
path, libs = sys.argv[1], sys.argv[2]
want = {"SONAME_LIBFREETYPE": ["libfreetype.6.dylib", "libfreetype.dylib"],
        "SONAME_LIBGNUTLS":   ["libgnutls.30.dylib", "libgnutls.dylib"],
        # MoltenVK itself, not the Khronos loader: the loader hides MoltenVK (a portability driver)
        # unless the instance asks for VK_KHR_portability_enumeration, which CrossOver's winevulkan
        # never does. Through the loader every DXVK game failed with "VK_KHR_surface not supported".
        "SONAME_LIBVULKAN":   ["libMoltenVK.dylib", "libvulkan.1.dylib", "libvulkan.dylib"]}
s = open(path).read()
assert re.search(r'^#define PACKAGE_VERSION ', s, re.M), "config.h incomplete (no PACKAGE_VERSION)"
for key, names in want.items():
    name = next((n for n in names if os.path.exists(os.path.join(libs, n))), None)
    assert name, f"{key}: none of {names} in {libs}"
    s, n = re.subn(rf'^#define {key} .*$', f'#define {key} "{name}"', s, flags=re.M)
    assert n == 1, f"{key} not defined by configure (library not detected?)"
    print(f"   {key} = {name}")
# pipe2 is declared in the macOS SDK but missing from libSystem at runtime (macOS 26,
# x86_64 and arm64). Configure links it as a weak import, and ntdll then calls address 0
# during startup (server_init_process -> init_thread_pipe). Wine falls back to pipe+fcntl.
s, n = re.subn(r'^#define HAVE_PIPE2 1$', '/* #undef HAVE_PIPE2 */  /* decant: SDK-only, absent at runtime */', s, flags=re.M)
print(f"   HAVE_PIPE2 disabled ({n})")
open(path, "w").write(s)
PY

# ---- build + install
say "building with $JOBS jobs (expect 15-40 min)"
# Build-time tools (sfnt2fon renders the fonts) link the bare-named dylibs and
# must find them while make runs. DYLD_* variables don't survive: make runs
# recipes through the SIP-protected /bin/sh, which strips them. dyld does try
# the current directory for bare names, so clone the libraries into $BUILD.
cp -c "$LIBS"/*.dylib "$BUILD/"
arch -x86_64 make -j"$JOBS" > "$WORK/make-$NAME.log" 2>&1 || { grep -E ': error:' "$WORK/make-$NAME.log" | head; die "make failed (log: $WORK/make-$NAME.log)"; }
rm -rf "$DEST"; arch -x86_64 make install > "$WORK/install-$NAME.log" 2>&1
cp -c "$LIBS"/*.dylib "$DEST/lib/"          # self-contained: decant puts $rt/lib on the dyld path

# Binaries that link a bundled dylib directly must find it without DYLD_* help.
for f in "$DEST/bin/wineserver" "$DEST/lib/wine/x86_64-unix/"*.so; do
  otool -L "$f" 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -vE '^(/|@)' | while IFS= read -r dep; do
    [ -f "$DEST/lib/$dep" ] || continue
    case "$f" in */bin/*) to="@executable_path/../lib/$dep";; *) to="@loader_path/../../$dep";; esac
    install_name_tool -change "$dep" "$to" "$f" 2>/dev/null
    codesign --force --sign - "$f" 2>/dev/null
    say "   $(basename "$f"): $dep -> $to"
  done || true
done

# Wine Gecko (built-in browser engine): reuse the prebuilt runtime's copy when the
# version matches. Wine Mono must match exactly too; if it doesn't, Wine offers to
# download it on first use (or run with WINEDLLOVERRIDES=mscoree=d for no .NET).
want_gecko=$(sed -n 's/^#define GECKO_VERSION "\(.*\)"/\1/p' "$SRC"/dlls/appwiz.cpl/*.c | awk 'NR == 1')
want_mono=$(sed -n 's/^#define WINE_MONO_VERSION "\(.*\)"/\1/p' "$SRC"/dlls/appwiz.cpl/*.c | awk 'NR == 1')
mkdir -p "$DEST/share/wine"
if [ -d "$LIBSRC/../share/wine/gecko/wine-gecko-$want_gecko-x86_64" ]; then
  cp -cR "$LIBSRC/../share/wine/gecko" "$DEST/share/wine/"; say "Gecko $want_gecko: bundled"
else say "Gecko $want_gecko: not available locally (Wine will offer to download it)"; fi
if [ -d "$LIBSRC/../share/wine/mono/wine-mono-$want_mono" ]; then
  cp -cR "$LIBSRC/../share/wine/mono" "$DEST/share/wine/"; say "Mono $want_mono: bundled"
else
  # Wine Mono must match this Wine exactly; fetch it from WineHQ (~38 MB).
  mono_tar="$DECANT_HOME/downloads/wine-mono-$want_mono-x86.tar.xz"
  mkdir -p "$DECANT_HOME/downloads"
  [ -s "$mono_tar" ] || curl -fL --retry 5 -C - -o "$mono_tar" "https://dl.winehq.org/wine/wine-mono/$want_mono/wine-mono-$want_mono-x86.tar.xz" \
    || say "Mono $want_mono: download failed (Wine will offer to download it on first use)"
  if [ -s "$mono_tar" ] && tar -tJf "$mono_tar" >/dev/null 2>&1; then
    mkdir -p "$DEST/share/wine/mono"; tar -xJf "$mono_tar" -C "$DEST/share/wine/mono"; say "Mono $want_mono: bundled (downloaded)"
  fi
fi

if LC_ALL=C grep -qa _macdrv_functions "$DEST/lib/wine/x86_64-unix/winemac.so"; then
  say "DXMT: supported (winemac.so exports macdrv_functions)"
else
  say "DXMT: NOT supported by this build"
fi
"$DECANT" runtime import "$DEST" "$NAME"
say "done. Use it: decant bottle create mygame --runtime $NAME"

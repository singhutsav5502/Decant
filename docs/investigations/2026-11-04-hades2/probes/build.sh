#!/bin/bash
# Builds memprobe32.exe (large-address-aware, like most extractors), memprobe32-nolaa.exe and memprobe64.exe.
set -euo pipefail
cd "$(dirname "$0")"
F="-O1 -Wall -Wno-unused-parameter -static"
i686-w64-mingw32-gcc   $F -Wl,--large-address-aware -o memprobe32.exe       memprobe.c
i686-w64-mingw32-gcc   $F                           -o memprobe32-nolaa.exe memprobe.c
x86_64-w64-mingw32-gcc $F                           -o memprobe64.exe       memprobe.c
ls -l memprobe*.exe

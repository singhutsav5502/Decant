# Track B live playbook — make the installer finish
# (everything here needs a human click on "Install"; commands are verbatim)
# NOTE: usernames are scrubbed to "user" per bundle convention; substitute
# your real home directory (/Users/<you>) in all paths below.

## 0. Prep (no clicks needed)
Create a disposable copy of the freeze bottle (do NOT touch `games`):
  cp -R "$HOME/Library/Application Support/Decant/bottles/games" \
        "$HOME/Library/Application Support/Decant/bottles/games-exp"
  sed -i '' 's/^NAME=games/NAME=games-exp/' \
      "$HOME/Library/Application Support/Decant/bottles/games-exp/bottle.conf"
  # set a normal debug level for the experiment run:
  cd /Users/user/Desktop/repos/decant
  bin/decant bottle set games-exp WINEDEBUG=-all

Installer launch path (Windows side, inside the bottle):
  C:\decant-stage\GameTitle [VendorStyle bundle]-setup\setup.exe

## 1. Find the loop's code (needs one Install click)
Goal: identify module + address of the loop in setup.tmp.

Option A — winedbg (preferred):
  # launch
  bin/decant run games-exp 'C:\decant-stage\GameTitle [VendorStyle bundle]-setup\setup.exe'
  # user clicks Install; wait until the freeze (dir stops growing, setup.tmp ~100% CPU)
  # then attach:
  WINEPREFIX="$HOME/Library/Application Support/Decant/bottles/games-exp/prefix" \
    "$HOME/Library/Application Support/Decant/runtimes/crossover-26.1.0/bin/winedbg" \
    --gdb <pid of setup.tmp>
  # in winedbg:
  #   info threads
  #   thread <spinning worker tid>
  #   bt
  #   disas $pc-64,$pc+64   (or around the VirtualAlloc caller)
  # note the module (ISDone.dll is the candidate; see offline findings below)
  # and the exact address.

Option B — if winedbg cannot attach under Rosetta (filtered relay):
  # set RelayInclude via registry before launching:
  (in the bottle) reg add 'HKCU\Software\Wine\Debug' /v RelayInclude /t REG_SZ \
      /d 'kernel32.VirtualAlloc;kernel32.VirtualFree;kernel32.GlobalMemoryStatusEx;ntdll.NtQuerySystemInformation' /f
  # and WINEDEBUG=+relay (via bottle set). Launch, click Install, let it freeze,
  # then inspect the log: each VirtualAlloc line prints the caller return
  # address (the address inside the looping module).

Offline findings so far (no live run needed):
  - Candidate module: ISDone.dll (Delphi-compiled; imports VirtualAlloc,
    VirtualFree, NtQuerySystemInformation). Temp copies exist under
    bottles/games/prefix/.../Temp/is-*/ISDone.dll.
  - Innocallback.dll also imports VirtualAlloc/VirtualFree but not
    NtQuerySystemInformation, so the probe (which reads SYSTEM_PERFORMANCE
    just before the loop) is more likely in ISDone.dll.
  - The loop body in the trace: VirtualAlloc(NULL,size,MEM_RESERVE,PAGE_READWRITE)
    then VirtualFree(prev); size >>= 1; ... down to 0, then infinite
    size-0 pair. It ignores VirtualAlloc's result, so the exit test is a
    value computed from GlobalMemoryStatusEx / NtQuerySystemInformation
    read immediately before.

## 2. Decode the exit condition
From the disassembly, name the exact inputs compared and the values Wine
gives them. Decide whether 32-bit overflow/wrap explains the hang.

## 3. Cheap experiments (one change at a time, each in its own bottle copy)
Record the result of each (freeze vs. completes, and final output size).

  E1 — installer's own options:
       On the installer's options page, enable any RAM-limit or
       thread-limit checkbox if present. Re-run, click Install.
  E2 — CPU topology:
       bin/decant bottle set games-exp WINE_CPU_TOPOLOGY='4:0,1,2,3'
       re-run; then repeat with '2:0,1'.
  E3 — host free RAM below 4 GB (tests the 11.5 GB * 4096 wrap hypothesis):
       Free host RAM to <4 GB (close apps / use a memory-pressure tool),
       re-run in a fresh bottle copy. If the wrap hypothesis is right, the
       result should change (completes instead of freezing).

## 4. If a value is the trigger
Extend probe/memprobe.c to print that exact computed value under Wine, then:
  - If Wine reports something Windows would report differently -> Wine bug
    (draft Report 2).
  - Otherwise -> app bug; document the workaround (E1/E2/E3 whichever works).

## 5. Deliverable
  - module + address of the loop
  - decoded exit condition
  - result of E1/E2/E3
  - either a working workaround or a ready-to-file Report 2.
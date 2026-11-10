# Brief for the next investigation pass

Folder: `~/Desktop/decant-investigation-logs/`. Read these first, in order:
1. `upstream-bug-report.md`
2. `summary.txt`
3. `analysis/wow64cpu-attribution.txt` (start with the CORRECTIONS block)

The `*.orig.*` files are the pre-review versions. Several of their conclusions were wrong, so don't build on them.

## Where things stand

There are **two separate problems**, on different builds and different threads:

- **A — staging 11.21 crash.** The GUI thread (0148) of `setup.tmp` faults at `wow64cpu+0x1135` (`movl cs32_sel(%rip),%edx` in `syscall_32to64`), reading address `0x2EC5`. That address equals the instruction's displacement, so the 64-bit gate code was decoded in 32-bit mode. The mode switch on the 32→64 gate didn't take effect under Rosetta. This is a real Wine/Rosetta bug.
- **B — CrossOver 26.1 freeze.** Extraction worker 0178 loops forever: `VirtualFree(prev); VirtualAlloc(NULL, size, MEM_RESERVE, PAGE_READWRITE); size >>= 1`, down to 0, then repeats the failing size‑0 pair forever.
  - Every non-zero reservation succeeds. That's correct: setup.tmp is large-address-aware, and `probe/results` shows Wine's layout matches 64-bit Windows.
  - The loop ignores VirtualAlloc's result, so its exit test is something else. It's probably a value computed from `GlobalMemoryStatusEx` / `NtQuerySystemInformation(SYSTEM_PERFORMANCE_INFORMATION)`, which are read just before the loop.
  - Leading hypothesis: free RAM is about 11.5 GB, and `AvailablePages*4096` wraps in 32-bit math.

Do **not** treat A and B as one mechanism. Nothing links them.

## Track B — make the installer finish (priority)

1. **Find the loop's code.** Reproduce the freeze in the `games` bottle (crossover-26.1.0). While it's spinning, attach `winedbg` to the setup.tmp process, select the spinning worker thread, then `bt` and `disas` around the caller of VirtualAlloc. Record which module and address the loop is in. It may be `ISDone.dll` or an unpacker loaded from memory, so check `+loaddll` and the address ranges.
   - If winedbg can't attach under Rosetta, use `+relay` limited to `kernel32.VirtualAlloc`, `kernel32.VirtualFree`, `kernel32.GlobalMemoryStatusEx` and `ntdll.NtQuerySystemInformation`, via `HKCU\Software\Wine\Debug` `RelayInclude`. That gives caller return addresses.
2. **Decode the exit condition** from the disassembly. Name the exact inputs it compares against, and work out the values Wine gives it. State whether 32-bit overflow or wrap explains the hang.
3. **Test the hypothesis cheaply, one change at a time**, in a copy of the bottle. Record the result of each:
   - Use the installer's own options, if it has any: a RAM-limit or thread-limit checkbox on its options page.
   - Limit CPUs with `WINE_CPU_TOPOLOGY` (for example `4:0,1,2,3`, then `2:0,1`).
   - Retry with host free RAM below 4 GB. If the wrap hypothesis is right, the result should change.
4. **If a value is the trigger,** extend `probe/memprobe.c` to print that exact computed value under Wine. Then decide:
   - If Wine reports something that Windows would report differently, that's a Wine bug. Draft it.
   - Otherwise it's an app bug, and we document the workaround.
5. **Deliverable:** module and address of the loop, the decoded exit condition, the result of each experiment, and either a working workaround or a ready-to-file Report 2.

## Track A — make Report 1 self-contained

1. **Diff the gate code** between builds. Compare the disassembly of `syscall_32to64` and the 32→64 far-transfer sequence in staging's `wow64cpu.dll` (base `0x7BF40000`) and CrossOver's (base `0x7BF10000`). CrossOver may carry a Rosetta workaround that explains why it doesn't crash.
2. **Build a minimal reproducer.** Write a 32-bit test program (mingw, like `probe/build.sh`) that hammers what thread 0148 was doing: window-message callbacks into its own wndproc plus plain syscalls, in a loop. Run it on staging 11.21 and check whether it faults at `wow64cpu+0x1135` reading `0x2EC5`. A reproducer that doesn't involve the installer makes Report 1 fileable.
3. Record the macOS and Rosetta versions, and how staging 11.21 was built (configure flags, new-wow64 settings).

## Rules

- **Don't file or post anything upstream.** Update `upstream-bug-report.md` and hand it back for review.
- **Keep everything sanitized** the same way the existing bundle is: no real username, game title or vendor names in files meant for upload.
- **Separate facts from inferences.** Mark inferences explicitly. Don't state rates without `+timestamp`. Cite log file and line for each claim.
- **Work in a copy of each bottle.** Don't change the `games` or `vol-test` bottle configs in place.

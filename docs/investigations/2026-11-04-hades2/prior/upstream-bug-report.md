# Draft: two issues from one 32-bit Inno Setup installer under new-wow64 Wine on Apple Silicon (Rosetta)

> **STATUS (2026-11-04): do not file Report 1.** It is already known upstream as
> [Wine bug 60034](https://bugs.winehq.org/show_bug.cgi?id=60034) (same read of
> `0x2ec5` in `syscall_32to64`), resolved NOTOURBUG as a Rosetta bug. The trigger
> is self-modifying code. A standalone reproducer (`probe/repro-smc.exe`) crashes
> stock staging 11.21 in 4/4 runs and passes 4/4 with CrossOver's `wow64cpu.dll`.
> See `analysis/repro-smc-results.txt`. Report it to Apple instead; optionally
> comment on 60034 that it still reproduces on macOS 26.6.

Target: WineHQ Bugzilla — draft, please review wording before filing.
(Previous version kept as `upstream-bug-report.orig.md`.)

This investigation produced **two separate findings**. They should be filed (or not) separately:

- **Report 1 — file it:** a hard fault inside Wine's own `wow64cpu!syscall_32to64` on wine-staging 11.21. The evidence points to the 64-bit gate code running while the CPU is still in 32-bit mode under Rosetta.
- **Report 2 — triage first, do not file yet:** an infinite memory-probe loop in the installer's extractor on a CrossOver 26.1 build. The trace shows exactly what the loop does, but not why it never exits. It is not yet shown to be a Wine bug.

Common environment:

- Apple Silicon Mac, macOS 26.6 (arm64), Wine x86_64 builds translated by Rosetta.
- New wow64 mode (32-bit PE code on 64-bit Unix Wine; builtin `wow64.dll` / `wow64cpu.dll`).
- Application: a 32-bit Inno Setup installer (`setup.exe` → `setup.tmp`, temp dir `is-*.tmp`). It uses the native plugins `idp.dll` (InnoDownloadPlugin), `innocallback.dll` and `ISDone.dll` (the volume extractor that unpacks the game content).
- The archive volumes were verified byte-perfect against their checksum manifest (all 7 parts), so archive corruption is ruled out.

---

## Report 1 — wow64cpu `syscall_32to64` faults reading `cs32_sel`; the RIP-relative operand is decoded as an absolute address

**Suggested title:** wow64 on macOS/Rosetta: access violation at `wow64cpu!syscall_32to64+…` reading address `0x2ec5` (RIP-relative `cs32_sel` load executed as 32-bit absolute)

**Component:** ntdll / wow64 (wow64cpu), macOS

**Build:** wine-staging 11.21, x86_64 with new wow64. Run with `WINEDEBUG=+seh,+loaddll,+thread,+process`.

### What happens

Clicking Install produces one real access violation in the main (GUI) thread of `setup.tmp` (tid 0148, pid 0144). The process then dies in a cascade of follow-on exceptions. The crash is deterministic: it happens on every attempt.

```
0148:trace:seh:dispatch_exception code=c0000005 (EXCEPTION_ACCESS_VIOLATION) flags=0 addr=000000007BF41135
0148:trace:seh:dispatch_exception  info[0]=0000000000000000
0148:trace:seh:dispatch_exception  info[1]=0000000000002EC5
0148:trace:seh:dispatch_exception rip=000000007bf4110c rsp=00000001000ff520 rbp=000000000026fdb4 eflags=00000206
0148:trace:seh:dispatch_exception rax=00000000000000de rbx=0000000000000001 rcx=0000000000efc665 rdx=000000007bf9e0a0
0148:trace:seh:dispatch_exception r13=00000001000ffd24 r14=00000001000ff520 r15=00000001000ff6a0 cs=002b ss=0000
```

### Where the fault is

- `+loaddll` places `wow64cpu.dll` (builtin) at `0x7BF40000`, so the fault address `0x7BF41135` is `wow64cpu+0x1135`. None of the installer's native DLLs are near that address. They load at `0x400000`, `0x1960000`, `0x19C0000` and `0x1AE0000`.
- Disassembly of this build's `lib/wine/x86_64-windows/wow64cpu.dll`:

  ```
  0x110c: xchgq %r14,%rsp              ; syscall_32to64 entry
  0x110f: movl  %edi,0x9c(%r13)        ; save 32-bit regs into the wow64 context
  ...
  0x112b: movl  (%r14),%edx            ; 32-bit return address
  ...
  0x1135: movl  0x2ec5(%rip),%edx      ; <-- fault: "movl cs32_sel(%rip),%edx"
  0x113b: movl  %edx,0xbc(%r13)        ; context->SegCs
  ```

  This matches `syscall_32to64` in `dlls/wow64cpu/cpu.c`.
- In 64-bit mode the operand resolves to `0x7BF4113B + 0x2EC5 = wow64cpu+0x4000`. That address lies inside the mapped `.data` section (VA `0x3000`, VirtualSize `0x300C`), so the read should not fault.

### Why this looks like a CPU-mode problem

- **The faulting read address is exactly `0x2EC5`** (`info[0]=0` means a read, `info[1]=0x2EC5`). That is the instruction's own disp32 used as an absolute address. With ModRM `mod=00, rm=101`, x86-64 means `[rip+disp32]` but 32-bit/compatibility mode means `[disp32]` (absolute). In other words, the instruction was decoded as if the CPU were still in 32-bit mode.
- It follows that the switch into 64-bit mode on the 32→64 gate (the far transfer to the 64-bit code selector) did not take effect before 64-bit code started executing.
- **The rest of the fault context is also inconsistent:**
  - `ss=0000` at the fault. Ordinary 64-bit contexts in the same log show `ss=0023`.
  - The exception record's address (`0x7BF41135`) does not match the context's `rip` (`0x7BF4110C`, the function entry).
  - `cs=002b` is the same value seen in ordinary 64-bit contexts in this log (rip inside 64-bit ntdll). So the *reported* CS says 64-bit, while the decoding of the faulting instruction says 32-bit.
  - `rax=0xde` should not be trusted given the inconsistent state.
- Just before the fault, the thread was in a long run of these cycles:

  ```
  RtlUnwindEx code=80000026 (STATUS_LONGJUMP) target_ip=<wow64.dll>
  NtQueryInformationThread / NtSetInformationThread(ThreadWow64Context, size 0x2cc)
  ```

  These appear to be Wine's normal wow64 callback-return path (user callbacks returning into wow64.dll). The same pattern shows up harmlessly in `setup.exe`'s main thread (tid 00f4). It is listed here only as the immediate context of the fault, not as its cause.

### Cascade (secondary)

After the single real fault, exception dispatch runs a NULL 32-bit SEH handler (`eip=0`) over and over. The log shows 1594 `c0000005` dispatches and 2 `c00000fd` (stack overflow) before the process exits. All of this follows from the one fault above.

### Things that did not change the outcome

- msync/esync off
- AVX advertised on/off
- Reported Windows version win7 vs win10
- Silent vs interactive install
- Elevated vs non-elevated
- dxvk vs wined3d

### Questions

1. Is a 32→64 transition that fails to switch mode under Rosetta known? It shows up as 64-bit gate code decoded in compatibility mode: the RIP-relative load becomes an absolute read of the disp32.
2. Is there a way to make the fault context more trustworthy (CS/SS at the fault) on macOS, to confirm the CPU mode at the faulting instruction?

### Attachments

- `analysis/wow64cpu-attribution.txt` — module map, disassembly and section-table check
- the `+seh` log excerpt around the first fault (`vol-test/20261104-174945-48551.log`, lines ~6740–6800)

---

## Report 2 (triage notes, not ready to file) — the extractor's memory-probe loop never terminates

**Build:** CrossOver 26.1 build, same wow64 layout. Run with `WINEDEBUG=+virtual,+sync,+thread,+file,+seh`. The log reached 9.27M lines / 764 MB before the process was killed.

On this build nothing crashes. Instead the install freezes at about 34 MB / 11 output files, and one core stays at 100%. No exceptions are logged. (Two earlier runs without `+virtual` reported about 32 MB at the same point.)

### What the trace shows

1. **Extraction is running normally up to the freeze.** Worker thread 0178:
   - creates the next output file (`CreateFileW` → handle `0x1c4`);
   - completes an event handshake with paired worker 0170;
   - calls `NtQuerySystemInformation(SYSTEM_PERFORMANCE_INFORMATION)` (the usual fixme);
   - then calls `GlobalMemoryStatusEx`, which reports `TotalVirtual 4294836224` and `AvailVirtual 4155547648` (about 4 GB; setup.tmp is large-address-aware).
2. **It then runs a reserve/free loop with a halving size.**
   - Each iteration frees the previous block and reserves the next one: `NtFreeVirtualMemory(prev)`, then `NtAllocateVirtualMemory(NULL, size, MEM_RESERVE, PAGE_READWRITE)`, then `size >>= 1`.
   - The size goes `0x7fffffff` → `0x3fffffff` → … → `0x1` → `0`.
   - Every non-zero size succeeds. The first view is `0x7fff0000-0xffff0000`; sizes ≤ 1 page are rounded up to one page.
3. **At size 0 the reservation fails, and the loop repeats that failing pair forever.** The last ~9.1M lines (~4.5M iterations) are only:

   ```
   0178:trace:virtual:NtAllocateVirtualMemory 0xffffffffffffffff 0x0 00000000 2000 00000004
   0178:trace:virtual:NtFreeVirtualMemory     0xffffffffffffffff 0x0 00000000 8000
   ```

   (format: `process, *addr, *size, type, protect` — checked against `dlls/ntdll/unix/virtual.c`)

   The last 301,958 allocations include zero successes. Meanwhile the GUI thread (0118) polls with a 10 ms timeout and keeps timing out.
4. **The earlier "worker thread wedged" readings were wrong.** Without `+virtual`, this loop produces no `+thread`/`+process`/`+seh` lines at all, so the worker only *looked* dead or stuck.

### Why this is not yet a Wine bug report

- **Wine's address-space answers match Windows.** A test program (`probe/memprobe.c`), run in the same bottles, shows:
  - non-large-address-aware 32-bit: largest `MEM_RESERVE` = 1970 MB, so 2 GB‑1 fails;
  - large-address-aware 32-bit: 4 GB address space, largest free region 2048 MB at `0x7FFE1000`.

  This is the layout real 64-bit Windows gives, so the successful 2 GB‑1 reservation is expected.
- **The loop's exit test doesn't depend on VirtualAlloc's result.** It keeps going after a 2 GB *success*, and it keeps going after the size‑0 *failure*. Making large reservations fail sooner would therefore not obviously end it. The exit condition is something the trace doesn't show, for example a bound computed from the memory-status values read just before the loop.
- **Open question:** what does the loop compare against? Candidate inputs are the `SYSTEM_PERFORMANCE_INFORMATION` fields and the `GlobalMemoryStatusEx` fields. The probe shows Wine fills `AvailablePages`, `CommittedPages` and `CommitLimit` with sane values. However, `AvailablePages * 4096` exceeds 4 GB (11.5 GB free on this host), so a 32-bit calculation of it would wrap. That is a plausible trigger to check.

### Next steps before filing

- Disassemble or `+relay` the `ISDone.dll` code around the `GlobalMemoryStatusEx` / `NtQuerySystemInformation` calls to find the loop's exit test.
- Run the same installer on real Windows 64-bit and/or native Linux Wine (new wow64 and old wow64) to see whether the loop ends there.
- Re-run with `+timestamp` if a gate-crossing rate is needed. The current logs have no timestamps, so no rate can be stated.
- Test whether capping reported free memory (if the extractor or the bottle allows it) stops the hang.

### Evidence

- `games/excerpts/excerpt-halving.log` — the halving descent with successes
- `games/excerpts/excerpt-loop-start.log` — the same window, including the paired workers' sync traffic
- `games/excerpts/excerpt-loop-tail.log` — the last 300 lines of the endless failing pair
- `probe/results/` — memprobe output for both bottles (32-bit with and without large-address-aware, and 64-bit)

## Update (Track A.1, 2026-11-04): CrossOver carries a Rosetta 2 workaround that staging lacks

Disassembly of the two runtime wow64cpu.dll files (see analysis/wow64cpu-gate-diff.txt)
shows a single meaningful difference on the 64->32 return path:

- CrossOver's binary contains a symbol named `syscall_32to64_rosetta2_workaround`
  and a global flag at 0x7a406000 (presumably set at init when Rosetta is
  detected). When that flag is nonzero, the return path uses `retfq` with a
  manually built far-return frame instead of the `jmp [r14]` / `iretq` path.
- Staging 11.21 has NO such symbol or branch; its return path uses `iretq`
  unconditionally.

This is direct evidence that Wine's wow64cpu code is known to need a
Rosetta-specific transition path, and explains why the staging build faults in
`syscall_32to64` (at the `mov edx, [rip+0x2ec5]` cs32_sel load, reading 0x2EC5)
while the CrossOver build does not. Upstreaming or reconciling this workaround
is the substance of Report 1.

## Additional question for maintainers

3. Can the `syscall_32to64_rosetta2_workaround` (retfq path gated on a
   Rosetta-detection flag) be upstreamed or reconciled with the staging build,
   so the `iretq` path is not used under Rosetta?

## Update (2026-11-04, final live check): swapped-runtime installer completed

Installed the target installer in the fx bottle (staging-11.21 + CrossOver's
wow64cpu.dll swapped in, WINEDEBUG=+seh,+loaddll,+thread,+process). Extraction
progressed normally (no spin; setup.tmp ~2% CPU), then the install completed
cleanly: process exited, unpacker modules (unarc.dll, ISDone.dll, innocallback.dll,
idp.dll) unloaded normally, no crash.

Corroborating synthetic runs on the same fx runtime also completed (memprobe END,
repro-gate, repro-gate2 all PASS).

This is the first real-world evidence that the CrossOver wow64cpu build (with its
`retfq` Rosetta workaround) survives the installer's unarchiving path, while stock
staging's `iretq`-based transition faults under Rosetta (c0000005 in syscall_32to64,
cs32_sel load reading 0x2EC5, STATUS_LONGJUMP + ThreadWow64Context relay before it).
The far-jump/retfq difference is therefore strongly implicated in the root cause of
the staging crash and/or the CrossOver freeze; see analysis/fx-gate-findings.txt and
analysis/wow64cpu-gate-diff.txt for the evidence chain.

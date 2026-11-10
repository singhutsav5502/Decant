Excerpts from the third instrumented run (crossover 26.1.0 build, -
WINEDEBUG=+virtual,+sync,+thread,+file,+seh, 2026-11-04 18:25).

Full log was 9.27M lines / 764MB; key facts extracted from it are in
analysis/wow64cpu-attribution.txt (final revision). These three excerpts
are the primary evidence:

excerpt-halving.log     - source lines 132050-132280: end of normal
                          extraction (thread 0178 creates the next output
                          file, GlobalMemoryStatusEx probe), then the
                          installer's memory probe: VirtualAlloc(NULL, size,
                          MEM_RESERVE, PAGE_READWRITE) with size halving
                          0x7fffffff -> 0, every attempt SUCCEEDING (see the
                          "map_view got mem" lines, i.e. real host mmap),
                          being freed again, and the descent reaching
                          size=0 at line 132225.
excerpt-loop-start.log  - lines 132062-132262: same window, unclipped
                          (includes sync traffic of the paired worker
                          threads 0164/0170 around the probe).
excerpt-loop-tail.log   - last 300 lines (out of ~9.1M): the identical
                          failing pair repeated forever:
                            NtAllocateVirtualMemory (NULL, 0, MEM_RESERVE, PAGE_READWRITE)
                            NtFreeVirtualMemory   (NULL, 0, MEM_RELEASE)
                          0 successes among the last 301,958 allocations.

/*
 * memprobe: what a Windows program "sees" about memory, address space and CPU
 * inside a Wine bottle. Built to test the extractor-failure hypotheses:
 *
 *   H1  SystemPerformanceInformation / GlobalMemoryStatusEx report odd values
 *       on macOS (tiny AvailablePages, zero CommitLimit, size mismatch ...)
 *   H2  the 32-bit address space is too fragmented for one big allocation
 *   H4  CPUID / fault delivery differs under Rosetta
 *
 * Output goes to stdout and, if given, to the file named by argv[1].
 * Build: i686-w64-mingw32-gcc / x86_64-w64-mingw32-gcc (see build.sh).
 */
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <cpuid.h>

static FILE *out2;

static void p(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt); vprintf(fmt, ap); va_end(ap);
    if (out2) { va_start(ap, fmt); vfprintf(out2, fmt, ap); va_end(ap); fflush(out2); }
    fflush(stdout);
}

typedef LONG (WINAPI *NtQSI_t)(ULONG, PVOID, ULONG, PULONG);
static NtQSI_t NtQSI;

/* Windows layout, identical on x86 and x64 (no pointers). */
typedef struct {
    LARGE_INTEGER IdleTime, ReadTransferCount, WriteTransferCount, OtherTransferCount;
    ULONG ReadOperationCount, WriteOperationCount, OtherOperationCount;
    ULONG AvailablePages;      /* 0x2c */
    ULONG CommittedPages;      /* 0x30 */
    ULONG CommitLimit;         /* 0x34 */
    ULONG PeakCommitment;      /* 0x38 */
    ULONG PageFaultCount, CopyOnWriteCount, TransitionCount, CacheTransitionCount;
    ULONG DemandZeroCount, PageReadCount, PageReadIoCount, CacheReadCount, CacheIoCount;
    ULONG DirtyPagesWriteCount, DirtyWriteIoCount, MappedPagesWriteCount, MappedWriteIoCount;
    ULONG PagedPoolPages, NonPagedPoolPages, PagedPoolAllocs, PagedPoolFrees;
    ULONG NonPagedPoolAllocs, NonPagedPoolFrees, FreeSystemPtes, ResidentSystemCodePage;
    ULONG TotalSystemDriverPages, TotalSystemCodePages, NonPagedPoolLookasideHits;
    ULONG PagedPoolLookasideHits, AvailablePagedPoolPages, ResidentSystemCachePage;
    ULONG ResidentPagedPoolPage, ResidentSystemDriverPage, CcFastReadNoWait;
    /* ... more counters follow on newer Windows; we only read the head */
} PERF_HEAD;

typedef struct {
    ULONG Reserved, TimerResolution, PageSize, NumberOfPhysicalPages;
    ULONG LowestPhysicalPageNumber, HighestPhysicalPageNumber, AllocationGranularity;
    ULONG_PTR MinimumUserModeAddress, MaximumUserModeAddress, ActiveProcessorsAffinityMask;
    CCHAR NumberOfProcessors;
} BASIC_INFO;

#define MB(x) ((double)(x) / (1024.0 * 1024.0))

static void section(const char *t) { p("\n== %s\n", t); }

static void probe_env(void)
{
    section("environment");
    p("pointer size          : %u-bit build\n", (unsigned)(sizeof(void *) * 8));
    BOOL wow = FALSE;
    IsWow64Process(GetCurrentProcess(), &wow);
    p("IsWow64Process        : %d\n", wow);
    OSVERSIONINFOW v = { sizeof(v) };
    LONG (WINAPI *RtlGetVersion)(OSVERSIONINFOW *) =
        (void *)GetProcAddress(GetModuleHandleA("ntdll.dll"), "RtlGetVersion");
    if (RtlGetVersion) RtlGetVersion(&v);
    p("Windows version       : %lu.%lu.%lu\n", v.dwMajorVersion, v.dwMinorVersion, v.dwBuildNumber);
    const char *(CDECL *wine_get_version)(void) =
        (void *)GetProcAddress(GetModuleHandleA("ntdll.dll"), "wine_get_version");
    p("wine_get_version      : %s\n", wine_get_version ? wine_get_version() : "(not wine)");
    void (CDECL *wine_get_host_version)(const char **, const char **) =
        (void *)GetProcAddress(GetModuleHandleA("ntdll.dll"), "wine_get_host_version");
    if (wine_get_host_version) {
        const char *sys = 0, *rel = 0;
        wine_get_host_version(&sys, &rel);
        p("host                  : %s %s\n", sys ? sys : "?", rel ? rel : "?");
    }
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)((BYTE *)GetModuleHandleA(0) +
                           ((IMAGE_DOS_HEADER *)GetModuleHandleA(0))->e_lfanew);
    p("large-address-aware   : %s\n",
      (nt->FileHeader.Characteristics & IMAGE_FILE_LARGE_ADDRESS_AWARE) ? "yes" : "no");
}

static void probe_basic(void)
{
    section("NtQuerySystemInformation(SystemBasicInformation)");
    BASIC_INFO bi; ULONG len = 0;
    memset(&bi, 0, sizeof(bi));
    LONG st = NtQSI(0, &bi, sizeof(bi), &len);
    p("status=0x%08lx len=%lu\n", st, len);
    p("PageSize=%lu PhysicalPages=%lu (%.0f MB) Granularity=0x%lx CPUs=%d\n",
      bi.PageSize, bi.NumberOfPhysicalPages, MB((double)bi.NumberOfPhysicalPages * bi.PageSize),
      bi.AllocationGranularity, bi.NumberOfProcessors);
    p("UserMode range        : %p - %p\n", (void *)bi.MinimumUserModeAddress,
      (void *)bi.MaximumUserModeAddress);
}

static void probe_perf(void)
{
    section("NtQuerySystemInformation(SystemPerformanceInformation)  [H1]");
    static BYTE buf[4096];
    ULONG len = 0;
    memset(buf, 0, sizeof(buf));
    LONG st = NtQSI(2, buf, sizeof(buf), &len);
    p("big buffer: status=0x%08lx ReturnLength=%lu (Win10/11 returns 0x158=344; Win7 0x138=312)\n", st, len);
    PERF_HEAD *pi = (PERF_HEAD *)buf;
    p("AvailablePages=%lu (%.0f MB)\n", pi->AvailablePages, MB((double)pi->AvailablePages * 4096));
    p("CommittedPages=%lu (%.0f MB)\n", pi->CommittedPages, MB((double)pi->CommittedPages * 4096));
    p("CommitLimit   =%lu (%.0f MB)\n", pi->CommitLimit, MB((double)pi->CommitLimit * 4096));
    p("PeakCommitment=%lu (%.0f MB)\n", pi->PeakCommitment, MB((double)pi->PeakCommitment * 4096));
    p("FreeSystemPtes=%lu PagedPoolPages=%lu NonPagedPoolPages=%lu ResidentSystemCachePage=%lu\n",
      pi->FreeSystemPtes, pi->PagedPoolPages, pi->NonPagedPoolPages, pi->ResidentSystemCachePage);
    /* 32-bit page->byte math an app might do: */
    p("AvailablePages*4096 as 32-bit ULONG = %lu  <- if an app does this, >4GB wraps\n",
      (ULONG)(pi->AvailablePages * 4096u));
    if (pi->AvailablePages == 0) p("!! AvailablePages is ZERO\n");
    if (pi->CommitLimit == 0) p("!! CommitLimit is ZERO\n");
    if (pi->CommittedPages > pi->CommitLimit) p("!! CommittedPages > CommitLimit\n");

    /* Exact-size queries: apps usually pass sizeof(their struct). */
    static const ULONG sizes[] = { 0x138, 0x150, 0x158, 0x160, 0x2c, 0x40 };
    for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        len = 0; memset(buf, 0, sizeof(buf));
        st = NtQSI(2, buf, sizes[i], &len);
        p("size 0x%03lx: status=0x%08lx ReturnLength=%lu AvailablePages=%lu\n",
          sizes[i], st, len, ((PERF_HEAD *)buf)->AvailablePages);
    }
}

static void probe_other_classes(void)
{
    section("other memory info classes the helper process touches");
    static BYTE buf[1024]; ULONG len;
    struct { ULONG cls; const char *name; } c[] = {
        { 0x15, "SystemFileCacheInformation" },
        { 0x50, "SystemMemoryListInformation" },
        { 0x51, "SystemFileCacheInformationEx" },
    };
    for (unsigned i = 0; i < 3; i++) {
        len = 0; memset(buf, 0, sizeof(buf));
        LONG st = NtQSI(c[i].cls, buf, sizeof(buf), &len);
        p("class 0x%02lx %-30s status=0x%08lx len=%lu\n", c[i].cls, c[i].name, st, len);
    }
}

static void probe_gms(void)
{
    section("GlobalMemoryStatusEx / GlobalMemoryStatus  [H1]");
    MEMORYSTATUSEX m = { sizeof(m) };
    BOOL ok = GlobalMemoryStatusEx(&m);
    p("Ex ok=%d load=%lu%%\n", ok, m.dwMemoryLoad);
    p("TotalPhys=%.0f MB AvailPhys=%.0f MB\n", MB(m.ullTotalPhys), MB(m.ullAvailPhys));
    p("TotalPageFile=%.0f MB AvailPageFile=%.0f MB\n", MB(m.ullTotalPageFile), MB(m.ullAvailPageFile));
    p("TotalVirtual=%.0f MB AvailVirtual=%.0f MB\n", MB(m.ullTotalVirtual), MB(m.ullAvailVirtual));
    MEMORYSTATUS o = { sizeof(o) };
    GlobalMemoryStatus(&o);
    p("legacy: AvailPhys=%.0f MB TotalVirtual=%.0f MB AvailVirtual=%.0f MB\n",
      MB(o.dwAvailPhys), MB(o.dwTotalVirtual), MB(o.dwAvailVirtual));
    if (m.ullAvailPhys < 512ull * 1024 * 1024) p("!! AvailPhys < 512 MB\n");
}

static void probe_vas(void)
{
    section("address space layout  [H2]");
    SYSTEM_INFO si; GetSystemInfo(&si);
    BYTE *a = (BYTE *)si.lpMinimumApplicationAddress, *end = (BYTE *)si.lpMaximumApplicationAddress;
    SIZE_T freeTotal = 0, resTotal = 0, comTotal = 0, largest = 0; void *largestAt = 0;
    unsigned nfree = 0;
    MEMORY_BASIC_INFORMATION mbi;
    p("free regions >= 64 MB:\n");
    while (a < end && VirtualQuery(a, &mbi, sizeof(mbi))) {
        if (mbi.State == MEM_FREE) {
            freeTotal += mbi.RegionSize; nfree++;
            if (mbi.RegionSize > largest) { largest = mbi.RegionSize; largestAt = mbi.BaseAddress; }
            if (mbi.RegionSize >= 64u << 20)
                p("  %p  %8.0f MB\n", mbi.BaseAddress, MB(mbi.RegionSize));
        } else if (mbi.State == MEM_RESERVE) resTotal += mbi.RegionSize;
        else comTotal += mbi.RegionSize;
        BYTE *next = (BYTE *)mbi.BaseAddress + mbi.RegionSize;
        if (next <= a) break;
        a = next;
        if (sizeof(void *) == 8 && (ULONG_PTR)a > 0x800000000ull) { p("  (64-bit: stopped scan at 32 GB)\n"); break; }
    }
    p("free total=%.0f MB in %u regions; largest=%.0f MB at %p\n",
      MB(freeTotal), nfree, MB(largest), largestAt);
    p("reserved=%.0f MB committed=%.0f MB\n", MB(resTotal), MB(comTotal));

    /* Largest single reservation (binary search, 1 MB resolution). */
    SIZE_T lo = 0, hi = (sizeof(void *) == 4) ? (SIZE_T)0xFFF00000u : ((SIZE_T)64 << 30);
    while (hi - lo > (1u << 20)) {
        SIZE_T mid = lo + ((hi - lo) / 2 & ~(SIZE_T)0xFFFFF);
        void *r = VirtualAlloc(0, mid, MEM_RESERVE, PAGE_NOACCESS);
        if (r) { VirtualFree(r, 0, MEM_RELEASE); lo = mid; } else hi = mid;
    }
    p("largest single VirtualAlloc(MEM_RESERVE) = %.0f MB\n", MB(lo));

    /* Commit + touch growing blocks, like a decompressor dictionary. */
    static const unsigned sz[] = { 64, 256, 512, 768, 1024, 1536, 2048, 3072 };
    for (unsigned i = 0; i < sizeof(sz) / sizeof(sz[0]); i++) {
        SIZE_T n = (SIZE_T)sz[i] << 20;
        if (sizeof(void *) == 4 && sz[i] > 3072) break;
        DWORD t0 = GetTickCount();
        BYTE *m = VirtualAlloc(0, n, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
        if (!m) { p("commit %4u MB: FAILED err=%lu\n", sz[i], GetLastError()); continue; }
        for (SIZE_T o = 0; o < n; o += 4096) m[o] = (BYTE)o;
        p("commit+touch %4u MB: ok at %p (%lu ms)\n", sz[i], m, GetTickCount() - t0);
        VirtualFree(m, 0, MEM_RELEASE);
    }
    /* Heap path (malloc/HeapAlloc) is what C/Delphi code usually hits. */
    for (unsigned mbs = 128; mbs <= 2048; mbs *= 2) {
        void *h = HeapAlloc(GetProcessHeap(), 0, (SIZE_T)mbs << 20);
        p("HeapAlloc %4u MB: %s\n", mbs, h ? "ok" : "FAILED");
        if (h) HeapFree(GetProcessHeap(), 0, h);
    }
}

static void probe_cpu(void)
{
    section("CPU as seen by x86 code  [H4]");
    unsigned a, b, c, d;
    char vendor[13] = {0}, brand[49] = {0};
    __cpuid_count(0, 0, a, b, c, d);
    unsigned maxleaf = a;
    memcpy(vendor, &b, 4); memcpy(vendor + 4, &d, 4); memcpy(vendor + 8, &c, 4);
    __cpuid_count(0x80000000, 0, a, b, c, d);
    if (a >= 0x80000004) {
        unsigned *bp = (unsigned *)brand;
        for (unsigned l = 0; l < 3; l++) __cpuid_count(0x80000002 + l, 0, bp[l*4], bp[l*4+1], bp[l*4+2], bp[l*4+3]);
    }
    p("vendor=%s maxleaf=0x%x brand=%s\n", vendor, maxleaf, brand);
    __cpuid_count(1, 0, a, b, c, d);
    p("leaf1 ecx=%08x edx=%08x : SSE3=%d SSSE3=%d SSE4.1=%d SSE4.2=%d POPCNT=%d AES=%d XSAVE=%d OSXSAVE=%d AVX=%d F16C=%d\n",
      c, d, !!(c & 1), !!(c & (1 << 9)), !!(c & (1 << 19)), !!(c & (1 << 20)), !!(c & (1 << 23)),
      !!(c & (1 << 25)), !!(c & (1 << 26)), !!(c & (1 << 27)), !!(c & (1 << 28)), !!(c & (1 << 29)));
    if (maxleaf >= 7) {
        __cpuid_count(7, 0, a, b, c, d);
        p("leaf7 ebx=%08x : BMI1=%d AVX2=%d BMI2=%d ERMS=%d AVX512F=%d SHA=%d\n", b,
          !!(b & (1 << 3)), !!(b & (1 << 5)), !!(b & (1 << 8)), !!(b & (1 << 9)), !!(b & (1 << 16)),
          !!(b & (1 << 29)));
    }
    p("active processors     : %lu\n", GetActiveProcessorCount(ALL_PROCESSOR_GROUPS));
    DWORD_PTR pm = 0, sm = 0;
    GetProcessAffinityMask(GetCurrentProcess(), &pm, &sm);
    p("process affinity mask : 0x%llx\n", (unsigned long long)pm);
}

/* ---- fault delivery: catch AVs like the extractor's first fault (read NULL+0x2EC5) */
static volatile LONG g_hits;
static volatile ULONG_PTR g_addr;
static LONG CALLBACK veh(EXCEPTION_POINTERS *ep)
{
    if (ep->ExceptionRecord->ExceptionCode == EXCEPTION_ACCESS_VIOLATION ||
        ep->ExceptionRecord->ExceptionCode == EXCEPTION_INT_DIVIDE_BY_ZERO) {
        g_hits++;
        g_addr = ep->ExceptionRecord->NumberParameters > 1 ? ep->ExceptionRecord->ExceptionInformation[1] : 0;
#ifdef _WIN64
        ep->ContextRecord->Rip = (DWORD64)ep->ContextRecord->Rax; /* resume at label passed in rax */
#else
        ep->ContextRecord->Eip = ep->ContextRecord->Eax;
#endif
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

static void probe_faults(void)
{
    section("fault delivery (VEH)  [H4]");
    void *h = AddVectoredExceptionHandler(1, veh);
    /* read [0x2EC5]; handler resumes at label 1 (address loaded in eax/rax) */
#ifdef _WIN64
    __asm__ volatile("lea 1f(%%rip), %%rax\n\tmovb 0x2ec5, %%cl\n1:" ::: "rax", "rcx", "memory");
#else
    __asm__ volatile("lea 1f, %%eax\n\tmovb 0x2ec5, %%cl\n1:" ::: "eax", "ecx", "memory");
#endif
    p("read NULL+0x2EC5      : caught=%ld fault addr=0x%lx (expect 1, 0x2ec5)\n", g_hits, (unsigned long)g_addr);
    LONG before = g_hits;
    for (int i = 0; i < 1000; i++) {
#ifdef _WIN64
        __asm__ volatile("lea 1f(%%rip), %%rax\n\tmovb 0x2ec5, %%cl\n1:" ::: "rax", "rcx", "memory");
#else
        __asm__ volatile("lea 1f, %%eax\n\tmovb 0x2ec5, %%cl\n1:" ::: "eax", "ecx", "memory");
#endif
    }
    p("1000 repeated faults  : caught=%ld\n", g_hits - before);
    RemoveVectoredExceptionHandler(h);
}

int main(int argc, char **argv)
{
    if (argc > 1) out2 = fopen(argv[1], "w");
    NtQSI = (NtQSI_t)GetProcAddress(GetModuleHandleA("ntdll.dll"), "NtQuerySystemInformation");
    p("memprobe 1\n");
    probe_env();
    probe_basic();
    probe_perf();
    probe_other_classes();
    probe_gms();
    probe_cpu();
    probe_faults();
    probe_vas();
    p("\nEND\n");
    if (out2) fclose(out2);
    return 0;
}

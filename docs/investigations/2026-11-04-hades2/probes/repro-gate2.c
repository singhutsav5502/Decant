/* repro-gate2: standalone 32-bit stress test for the wow64 32<->64 gate
 * (wow64cpu syscall_32to64 / unix_call_32to64) under Rosetta.
 *
 * Unlike repro-gate.c, every phase here is chosen to actually cross the gate
 * on the paths under suspicion:
 *   syscall  - plain syscalls (fast return path: ljmp, or lretq with the
 *              CrossOver Rosetta workaround)
 *   raise    - RaiseException + continue (NtRaiseException, 32-bit exception
 *              dispatch, NtContinue: context rewrites -> slow iretq path)
 *   av       - hardware access violations caught by a VEH (host signal ->
 *              wow64 exception dispatch -> NtContinue)
 *   callback - SetWindowPos / child CreateWindow+DestroyWindow, which make
 *              win32u call back into the 32-bit wndproc (user callbacks,
 *              STATUS_LONGJUMP returns inside wow64)
 *   setctx   - a second thread does Suspend/Get/SetThreadContext/Resume on a
 *              thread that is busy making syscalls (ThreadWow64Context sets)
 *   mixed    - all of the above at once, on separate threads
 *
 * Any exception that is not one we raised on purpose is reported with its
 * code and addresses, and the process exits with code 3.
 * Usage: repro-gate2.exe [seconds-per-phase]   (default 10; mixed runs 3x)
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

#define MY_CODE 0xE0000123u
#define AV_ADDR 0x10            /* deliberate fault: read [0x10] */

static volatile LONG stop_flag;
static volatile LONG n_sys, n_raise, n_av, n_cb, n_ctx, n_wnd;
static HWND main_wnd;

static void out(const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt); vprintf(fmt, ap); va_end(ap); fflush(stdout);
}

static LONG CALLBACK veh(EXCEPTION_POINTERS *ep)
{
    EXCEPTION_RECORD *r = ep->ExceptionRecord;
    if (r->ExceptionCode == MY_CODE) { InterlockedIncrement(&n_raise); return EXCEPTION_CONTINUE_EXECUTION; }
    if (r->ExceptionCode == EXCEPTION_ACCESS_VIOLATION && r->NumberParameters >= 2 &&
        r->ExceptionInformation[1] == AV_ADDR)
    {
        InterlockedIncrement(&n_av);
        ep->ContextRecord->Eip = ep->ContextRecord->Eax;   /* resume at the label in eax */
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    if (r->ExceptionCode == 0x406D1388 /* thread naming */ || r->ExceptionCode == DBG_PRINTEXCEPTION_C ||
        r->ExceptionCode == 0x4001000A /* DBG_PRINTEXCEPTION_WIDE_C */ || r->ExceptionCode == 0x000006BA)
        return EXCEPTION_CONTINUE_SEARCH;
    out("UNEXPECTED EXCEPTION code=%08lx addr=%p info0=%08lx info1=%08lx eip=%08lx esp=%08lx cs=%04lx ss=%04lx tid=%04lx\n",
        r->ExceptionCode, r->ExceptionAddress,
        r->NumberParameters > 0 ? (unsigned long)r->ExceptionInformation[0] : 0,
        r->NumberParameters > 1 ? (unsigned long)r->ExceptionInformation[1] : 0,
        ep->ContextRecord->Eip, ep->ContextRecord->Esp, ep->ContextRecord->SegCs,
        ep->ContextRecord->SegSs, GetCurrentThreadId());
    out("counts: sys=%ld raise=%ld av=%ld cb=%ld ctx=%ld wnd=%ld\n", n_sys, n_raise, n_av, n_cb, n_ctx, n_wnd);
    out("RESULT: CRASH\n");
    ExitProcess(3);
    return EXCEPTION_CONTINUE_SEARCH;
}

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    InterlockedIncrement(&n_cb);
    return DefWindowProcA(h, m, w, l);
}

/* ---- single operations ---- */
static void op_syscall(void) { SwitchToThread(); InterlockedIncrement(&n_sys); }
static void op_raise(void)   { RaiseException(MY_CODE, 0, 0, NULL); }
static void op_av(void)
{
    __asm__ volatile("lea 1f, %%eax\n\tmovb 0x10, %%cl\n1:" ::: "eax", "ecx", "memory");
}
static void op_callback(HWND wnd, int i)
{
    SetWindowPos(wnd, NULL, 10 + (i & 7), 10, 200 + (i & 15), 150, SWP_NOZORDER | SWP_NOACTIVATE);
    if ((i & 63) == 0)
    {
        HWND c = CreateWindowExA(0, "ReproGate2", "child", WS_CHILD, 0, 0, 20, 20, wnd, NULL, NULL, NULL);
        if (c) { DestroyWindow(c); InterlockedIncrement(&n_wnd); }
    }
    if ((i & 15) == 0)
    {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
    }
}

/* ---- threads ---- */
static DWORD WINAPI th_syscall(void *p) { while (!stop_flag) op_syscall(); return 0; }
static DWORD WINAPI th_raise(void *p)   { while (!stop_flag) { op_raise(); op_syscall(); } return 0; }
static DWORD WINAPI th_av(void *p)      { while (!stop_flag) { op_av(); op_syscall(); } return 0; }

static DWORD WINAPI th_setctx(void *p)
{
    HANDLE target = (HANDLE)p;
    while (!stop_flag)
    {
        CONTEXT ctx;
        if (SuspendThread(target) == (DWORD)-1) break;
        ctx.ContextFlags = CONTEXT_FULL;
        if (GetThreadContext(target, &ctx)) SetThreadContext(target, &ctx);
        ResumeThread(target);
        InterlockedIncrement(&n_ctx);
    }
    return 0;
}

static HANDLE start(LPTHREAD_START_ROUTINE fn, void *arg)
{
    return CreateThread(NULL, 0, fn, arg, 0, NULL);
}

static void join(HANDLE *h, int n)
{
    WaitForMultipleObjects(n, h, TRUE, INFINITE);
    for (int i = 0; i < n; i++) CloseHandle(h[i]);
}

static void report(const char *phase, ULONGLONG t0)
{
    out("%-8s done in %5.1fs  sys=%ld raise=%ld av=%ld cb=%ld ctx=%ld wnd=%ld\n", phase,
        (GetTickCount64() - t0) / 1000.0, n_sys, n_raise, n_av, n_cb, n_ctx, n_wnd);
}

int main(int argc, char **argv)
{
    DWORD secs = argc > 1 ? (DWORD)atoi(argv[1]) : 10;
    ULONGLONG t0, end;
    WNDCLASSA wc = {0};
    int i;

    out("repro-gate2: %lus per phase\n", secs);
    AddVectoredExceptionHandler(1, veh);

    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "ReproGate2";
    RegisterClassA(&wc);
    main_wnd = CreateWindowExA(0, "ReproGate2", "repro-gate2", WS_OVERLAPPEDWINDOW,
                               10, 10, 200, 150, NULL, NULL, wc.hInstance, NULL);
    if (!main_wnd) { out("CreateWindow failed %lu\n", GetLastError()); return 2; }

    t0 = GetTickCount64(); end = t0 + secs * 1000ull;
    while (GetTickCount64() < end) op_syscall();
    report("syscall", t0);

    t0 = GetTickCount64(); end = t0 + secs * 1000ull;
    while (GetTickCount64() < end) op_raise();
    report("raise", t0);

    t0 = GetTickCount64(); end = t0 + secs * 1000ull;
    while (GetTickCount64() < end) op_av();
    report("av", t0);

    t0 = GetTickCount64(); end = t0 + secs * 1000ull;
    for (i = 0; GetTickCount64() < end; i++) op_callback(main_wnd, i);
    report("callback", t0);

    {
        HANDLE h[2];
        stop_flag = 0;
        t0 = GetTickCount64();
        h[0] = start(th_syscall, NULL);
        h[1] = start(th_setctx, h[0]);
        Sleep(secs * 1000);
        stop_flag = 1;
        join(h, 2);
        report("setctx", t0);
    }

    {
        HANDLE h[5];
        stop_flag = 0;
        t0 = GetTickCount64(); end = t0 + secs * 3000ull;
        h[0] = start(th_syscall, NULL);
        h[1] = start(th_setctx, h[0]);
        h[2] = start(th_raise, NULL);
        h[3] = start(th_av, NULL);
        h[4] = start(th_raise, NULL);
        for (i = 0; GetTickCount64() < end; i++) op_callback(main_wnd, i);
        stop_flag = 1;
        join(h, 5);
        report("mixed", t0);
    }

    DestroyWindow(main_wnd);
    out("RESULT: PASS\n");
    return 0;
}

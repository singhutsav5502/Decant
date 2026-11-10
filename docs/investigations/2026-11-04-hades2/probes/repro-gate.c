/* 32-bit (i686) reproducer for the wow64cpu syscall_32to64 fault.
   Stresses the 32->64 gate the way the installer's GUI thread does:
   window messages dispatched into our own wndproc, syscalls, and
   setjmp/longjmp (which Wine implements via RtlUnwindEx/STATUS_LONGJUMP
   through the wow64 ThreadWow64Context relay). Runs ~20s then exits. */
#include <windows.h>
#include <setjmp.h>
#include <stdio.h>

static jmp_buf jb;
static volatile int g_stop = 0;
static HWND g_hwnd = NULL;

LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_TIMER) { g_stop = 0; return 0; }
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}

static void hammer(void) {
    int i;
    for (i = 0; i < 2000000 && !g_stop; i++) {
        void *p;
        /* message callback into our own wndproc */
        SendMessageA(g_hwnd, WM_NULL, 0, 0);
        if (setjmp(jb) == 0) {
            p = VirtualAlloc(NULL, 0x1000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
            if (p) { memset(p, 0x55, 0x1000); VirtualFree(p, 0, MEM_RELEASE); }
            /* a second syscall to vary the gate input */
            Sleep(0);
            longjmp(jb, 1);
        }
        /* exercised after the longjmp unwind */
        (void)i;
    }
}

int main(void) {
    WNDCLASSA wc = {0};
    MSG msg;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "ReproGate";
    RegisterClassA(&wc);
    g_hwnd = CreateWindowA("ReproGate", "repro", 0, 0, 0, 0, 0, NULL, NULL, wc.hInstance, NULL);
    SetTimer(g_hwnd, 1, 1000, NULL);
    printf("repro-gate: starting hammer loop\n"); fflush(stdout);
    hammer();
    printf("repro-gate: done\n"); fflush(stdout);
    while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
    DestroyWindow(g_hwnd);
    return 0;
}

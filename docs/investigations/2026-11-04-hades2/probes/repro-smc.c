/* repro-smc: minimal 32-bit trigger for the wow64cpu syscall_32to64 fault
 * under Rosetta 2 (same signature as Wine bug 60034: read of 0x00002ec5 at
 * wow64cpu+0x1135, 64-bit gate code executed in 32-bit mode).
 *
 * Trigger: code that has already executed is rewritten, then a syscall is
 * made. Each round writes "mov eax, i; ret" into a slot of one RWX page,
 * flushes the instruction cache, calls it, then does Sleep(0).
 * Usage: repro-smc.exe [rounds]   (default 50)
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static LONG CALLBACK veh(EXCEPTION_POINTERS *ep)
{
    EXCEPTION_RECORD *r = ep->ExceptionRecord;
    if (r->ExceptionCode == DBG_PRINTEXCEPTION_C || r->ExceptionCode == 0x4001000A ||
        r->ExceptionCode == 0x406D1388 || r->ExceptionCode == 0x000006BA)
        return EXCEPTION_CONTINUE_SEARCH;
    printf("UNEXPECTED EXCEPTION code=%08lx addr=%p info1=%08lx eip=%08lx\n", r->ExceptionCode,
           r->ExceptionAddress, r->NumberParameters > 1 ? (unsigned long)r->ExceptionInformation[1] : 0,
           ep->ContextRecord->Eip);
    printf("RESULT: CRASH\n");
    ExitProcess(3);
    return EXCEPTION_CONTINUE_SEARCH;
}

int main(int argc, char **argv)
{
    int rounds = argc > 1 ? atoi(argv[1]) : 50;
    unsigned char *page;
    int i;

    setvbuf(stdout, NULL, _IONBF, 0);
    AddVectoredExceptionHandler(1, veh);
    page = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!page) { printf("VirtualAlloc failed %lu\n", GetLastError()); return 2; }

    for (i = 0; i < rounds; i++)
    {
        unsigned char *p = page + (i % 6) * 16;   /* slots get reused after round 6 */
        int (*fn)(void) = (int (*)(void))p;
        p[0] = 0xb8; *(DWORD *)(p + 1) = (DWORD)i; p[5] = 0xc3;   /* mov eax, i; ret */
        FlushInstructionCache(GetCurrentProcess(), p, 6);
        if (fn() != i) printf("round %d: wrong result\n", i);
        Sleep(0);                                                 /* syscall through the gate */
        printf("round %d ok\n", i);
    }
    printf("RESULT: PASS\n");
    return 0;
}

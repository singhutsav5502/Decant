/* Test fixture (32-bit, large-address-aware): the largest-reservation binary search FreeArc's
 * unarc.dll uses. Its (lo + hi) >> 1 overflows 32 bits, so it never ends when a 2GB reservation
 * succeeds; it must end on Windows-like layouts (patches/crossover/0002, docs/adr/0020).
 * Writes "ends N" or "hangs" to the file named by LARGEST_OUT. Capped at 200 steps. */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    char out[MAX_PATH];
    unsigned lo = 0, hi = 0xffffffff, mid;
    void *p = NULL;
    int n = 0;
    FILE *f;
    if (!GetEnvironmentVariableA("LARGEST_OUT", out, MAX_PATH)) return 2;
    do {
        if (p) VirtualFree(p, 0, MEM_RELEASE);
        mid = (lo + hi) >> 1;
        p = VirtualAlloc(NULL, mid, MEM_RESERVE, PAGE_READWRITE);
        if (p) lo = mid; else hi = mid;
    } while (hi - lo > 1 && ++n < 200);
    if (!(f = fopen(out, "w"))) return 3;
    if (n >= 200) fprintf(f, "hangs\n"); else fprintf(f, "ends %d 0x%08x\n", n, lo);
    fclose(f);
    return 0;
}

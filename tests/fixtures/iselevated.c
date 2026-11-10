/* Test fixture: appends "elevated=<0|1> type=<1|2|3>" for its own token to the
 * file named by ECHOARGS_OUT. TOKEN_ELEVATION_TYPE: 1 default, 2 full, 3 limited. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

int main(void)
{
    char out[MAX_PATH];
    HANDLE tok;
    TOKEN_ELEVATION elev = { 0 };
    TOKEN_ELEVATION_TYPE type = 0;
    DWORD len;
    if (!GetEnvironmentVariableA("ECHOARGS_OUT", out, MAX_PATH)) return 2;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
        GetTokenInformation(tok, TokenElevation, &elev, sizeof(elev), &len);
        GetTokenInformation(tok, TokenElevationType, &type, sizeof(type), &len);
        CloseHandle(tok);
    }
    FILE *f = fopen(out, "a");
    if (!f) return 3;
    fprintf(f, "elevated=%lu type=%d cmd=%s\n", (unsigned long)elev.TokenIsElevated, (int)type, GetCommandLineA());
    fclose(f);
    return 0;
}

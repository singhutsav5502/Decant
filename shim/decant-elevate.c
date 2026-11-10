/*
 * decant-elevate — "Run as administrator" for Wine.
 *
 * Wine gives processes a *limited* token unless their manifest asks for
 * requireAdministrator/highestAvailable. Installers that check for admin rights
 * without declaring them then fail with "access denied" / "needs administrator".
 * The Windows way to elevate is ShellExecuteEx with the "runas" verb, which Wine's
 * shell32 honours by handing out the full admin token (get_admin_token).
 *
 *   decant-elevate.exe <program> [args...]
 *
 * Waits for the program and returns its exit code. Used by `decant run --admin`.
 * See docs/adr/0013-run-as-administrator-without-sudo.md.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <wchar.h>

/* Skip one argument of a command line, honouring quotes. */
static const wchar_t *skip_arg(const wchar_t *p)
{
    while (*p == L' ' || *p == L'\t') p++;
    if (*p == L'"') {
        p++;
        while (*p && *p != L'"') p++;
        if (*p) p++;
    } else {
        while (*p && *p != L' ' && *p != L'\t') p++;
    }
    while (*p == L' ' || *p == L'\t') p++;
    return p;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR unused, int show)
{
    int argc;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv || argc < 2) {
        MessageBoxW(NULL, L"usage: decant-elevate.exe <program> [args...]", L"decant-elevate", MB_OK);
        return 2;
    }

    /* Pass the caller's remaining arguments through verbatim (no re-quoting). */
    const wchar_t *params = skip_arg(skip_arg(GetCommandLineW()));

    /* Run from the program's own folder: installers look for files next to themselves. */
    wchar_t dir[MAX_PATH];
    wcsncpy(dir, argv[1], MAX_PATH - 1);
    dir[MAX_PATH - 1] = 0;
    wchar_t *slash = wcsrchr(dir, L'\\');
    if (slash) *slash = 0; else dir[0] = 0;

    SHELLEXECUTEINFOW sei;
    ZeroMemory(&sei, sizeof(sei));
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
    sei.lpVerb = L"runas";
    sei.lpFile = argv[1];
    sei.lpParameters = *params ? params : NULL;
    sei.lpDirectory = dir[0] ? dir : NULL;
    sei.nShow = SW_SHOWNORMAL;

    if (!ShellExecuteExW(&sei)) return (int)GetLastError();
    if (!sei.hProcess) return 0;

    WaitForSingleObject(sei.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(sei.hProcess, &code);
    CloseHandle(sei.hProcess);
    return (int)code;
}

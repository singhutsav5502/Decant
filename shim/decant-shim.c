/*
 * decant-shim — a generic, config-driven launch shim for Windows executables.
 *
 * Some apps start a child process we can't pass flags to (Steam's
 * steamwebhelper.exe is the motivating case, see docs/fixes/steam.md).
 * Decant moves the real binary aside to "<name>.decant-real.exe", puts this
 * shim in its place as "<name>.exe", and writes a sidecar "<name>.decant-shim"
 * describing what to change. The shim relaunches the real binary with the
 * extra arguments and waits for it, so the parent still sees "its" process.
 *
 * Sidecar format (UTF-8, one directive per line, '#' comments):
 *   inject=<args>      appended before the original arguments
 *   skip=<substring>   if the original command line contains this, inject nothing
 *                      (repeatable; e.g. "--type=" so Chromium child processes pass through)
 *   env=<KEY>=<VALUE>  set in the child's environment (repeatable)
 *
 * DECANT_SHIM_DISABLE=1 in the environment makes the shim a pure pass-through.
 * This file has no app-specific logic; recipes (fixes/<id>.fix) drive it.
 * See docs/adr/0006-launch-shim-over-wine-patch.md.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>

#define MAX_SKIPS 16
#define LINE_MAX_W 2048

static wchar_t inject[LINE_MAX_W];
static wchar_t skips[MAX_SKIPS][256];
static int nskips;

static const wchar_t *skip_argv0(const wchar_t *cmd)
{
    if (*cmd == L'"') {
        cmd++;
        while (*cmd && *cmd != L'"') cmd++;
        if (*cmd) cmd++;
    } else {
        while (*cmd && *cmd != L' ' && *cmd != L'\t') cmd++;
    }
    while (*cmd == L' ' || *cmd == L'\t') cmd++;
    return cmd;
}

static void trim(wchar_t *s)
{
    size_t n = wcslen(s);
    while (n && (s[n - 1] == L'\r' || s[n - 1] == L'\n' || s[n - 1] == L' ' || s[n - 1] == L'\t')) s[--n] = 0;
}

static void handle_line(wchar_t *line)
{
    trim(line);
    if (!*line || *line == L'#') return;
    if (!wcsncmp(line, L"inject=", 7)) {
        if (*inject) wcsncat(inject, L" ", LINE_MAX_W - wcslen(inject) - 1);
        wcsncat(inject, line + 7, LINE_MAX_W - wcslen(inject) - 1);
    } else if (!wcsncmp(line, L"skip=", 5) && nskips < MAX_SKIPS) {
        wcsncpy(skips[nskips], line + 5, 255);
        skips[nskips++][255] = 0;
    } else if (!wcsncmp(line, L"env=", 4)) {
        wchar_t *eq = wcschr(line + 4, L'=');
        if (eq) { *eq = 0; SetEnvironmentVariableW(line + 4, eq + 1); }
    }
}

/* Read the sidecar; a missing sidecar means pass-through. */
static void load_sidecar(const wchar_t *path)
{
    HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return;
    DWORD size = GetFileSize(f, NULL), got = 0;
    if (size == INVALID_FILE_SIZE || size > 64 * 1024) { CloseHandle(f); return; }
    char *buf = HeapAlloc(GetProcessHeap(), 0, size + 1);
    if (!buf || !ReadFile(f, buf, size, &got, NULL)) { CloseHandle(f); return; }
    CloseHandle(f);
    buf[got] = 0;

    int wlen = MultiByteToWideChar(CP_UTF8, 0, buf, -1, NULL, 0);
    wchar_t *w = HeapAlloc(GetProcessHeap(), 0, wlen * sizeof(wchar_t));
    if (!w) return;
    MultiByteToWideChar(CP_UTF8, 0, buf, -1, w, wlen);

    wchar_t *line = w;
    while (line && *line) {
        wchar_t *nl = wcschr(line, L'\n');
        if (nl) *nl = 0;
        if (wcslen(line) < LINE_MAX_W) handle_line(line);
        line = nl ? nl + 1 : NULL;
    }
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR unused, int show)
{
    wchar_t self[MAX_PATH], real[MAX_PATH], sidecar[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, self, MAX_PATH);
    if (!n || n >= MAX_PATH - 32) return 1;

    /* "...\name.exe" -> "...\name.decant-real.exe" and "...\name.decant-shim" */
    wchar_t *dot = wcsrchr(self, L'.');
    wchar_t *slash = wcsrchr(self, L'\\');
    if (!dot || (slash && dot < slash)) dot = self + wcslen(self);
    size_t stem = (size_t)(dot - self);
    wcsncpy(real, self, stem); real[stem] = 0; wcscat(real, L".decant-real.exe");
    wcsncpy(sidecar, self, stem); sidecar[stem] = 0; wcscat(sidecar, L".decant-shim");

    wchar_t flag[8];
    int disabled = GetEnvironmentVariableW(L"DECANT_SHIM_DISABLE", flag, 8) && flag[0] == L'1';
    if (!disabled) load_sidecar(sidecar);

    const wchar_t *args = skip_argv0(GetCommandLineW());
    for (int i = 0; i < nskips; i++)
        if (*skips[i] && wcsstr(args, skips[i])) { inject[0] = 0; break; }

    size_t len = wcslen(real) + wcslen(args) + wcslen(inject) + 8;
    wchar_t *cmd = HeapAlloc(GetProcessHeap(), 0, len * sizeof(wchar_t));
    if (!cmd) return 1;
    wcscpy(cmd, L"\""); wcscat(cmd, real); wcscat(cmd, L"\"");
    if (*inject) { wcscat(cmd, L" "); wcscat(cmd, inject); }
    if (*args)   { wcscat(cmd, L" "); wcscat(cmd, args); }

    STARTUPINFOW si;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi;
    GetStartupInfoW(&si);
    if (!CreateProcessW(real, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi))
        return (int)GetLastError();

    /* Stay alive: parents often track the PID they launched. */
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (int)code;
}

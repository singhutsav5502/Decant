/* Test fixture: writes its full command line and DECANT_TEST_ENV to the file
 * named by ECHOARGS_OUT, so tests can see exactly what decant-shim passed on. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

int main(void)
{
    char out[MAX_PATH], env[256] = "";
    if (!GetEnvironmentVariableA("ECHOARGS_OUT", out, MAX_PATH)) return 2;
    GetEnvironmentVariableA("DECANT_TEST_ENV", env, sizeof(env));
    FILE *f = fopen(out, "a");
    if (!f) return 3;
    fprintf(f, "cmd=%s\nenv=%s\n", GetCommandLineA(), env);
    fclose(f);
    return 7;   /* distinctive exit code: the shim must propagate it */
}

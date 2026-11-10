#include <windows.h>
#include <stdio.h>
int wmain(int argc, wchar_t **argv){
  wchar_t mod[MAX_PATH], cwd[MAX_PATH]; GetModuleFileNameW(NULL,mod,MAX_PATH); GetCurrentDirectoryW(MAX_PATH,cwd);
  FILE *f=_wfopen(L"C:\\decant-logs\\argprobe.txt",L"w");
  fwprintf(f,L"cmdline=[%ls]\nargv0=[%ls]\nargc=%d\nmodule=[%ls]\ncwd=[%ls]\n",GetCommandLineW(),argv[0],argc,mod,cwd); fclose(f); return 0;}

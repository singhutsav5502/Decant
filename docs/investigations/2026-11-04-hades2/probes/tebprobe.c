#include <windows.h>
#include <winternl.h>
#include <stdio.h>
static DWORD WINAPI th(void *p){ *(void**)p = NtCurrentTeb(); return 0; }
int main(void){ FILE *f=fopen("C:\\decant-logs\\tebprobe.txt","w"); void *t2=0; HANDLE h=CreateThread(0,0,th,&t2,0,0); WaitForSingleObject(h,INFINITE);
  TEB *t=NtCurrentTeb(); void *peb=t->ProcessEnvironmentBlock; MEMORY_BASIC_INFORMATION m;
  VirtualQuery((void*)0xfffd0000,&m,sizeof m);
  fprintf(f,"TEB32 main=%p thread2=%p PEB32=%p | 0xfffd0000: base=%p alloc=%p size=%lu state=%lx\n",t,t2,peb,m.BaseAddress,m.AllocationBase,(unsigned long)m.RegionSize,m.State);
  fclose(f); return 0; }

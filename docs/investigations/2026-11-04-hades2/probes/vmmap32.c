#include <windows.h>
#include <stdio.h>
int main(void){ FILE *f=fopen("C:\\decant-logs\\vmmap32.txt","w"); MEMORY_BASIC_INFORMATION m; unsigned long a=0x70000000;
  while(VirtualQuery((void*)a,&m,sizeof m)){ const char *s=m.State==MEM_FREE?"free":m.State==MEM_RESERVE?"reserve":"commit";
    const char *t=m.Type==MEM_IMAGE?"image":m.Type==MEM_MAPPED?"mapped":m.Type==MEM_PRIVATE?"private":"";
    fprintf(f,"%08lx-%08lx %6lu KB %-7s %s\n",(unsigned long)m.BaseAddress,(unsigned long)m.BaseAddress+m.RegionSize-1,(unsigned long)(m.RegionSize>>10),s,t);
    a=(unsigned long)m.BaseAddress+m.RegionSize; if(a<0x70000000) break; }
  fclose(f); return 0; }

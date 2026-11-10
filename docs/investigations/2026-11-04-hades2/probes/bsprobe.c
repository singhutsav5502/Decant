/* Mimics FreeArc unarc.dll's largest-reservable-block search (0x6108a904), capped at 200 steps. */
#include <windows.h>
#include <stdio.h>
int main(void){
  FILE *f=fopen("C:\\decant-logs\\bsprobe.txt","w");
  void *p=VirtualAlloc(NULL,0x7fffffff,MEM_RESERVE,PAGE_READWRITE);
  fprintf(f,"reserve(0x7fffffff) -> %p (err %lu)\n",p,p?0:GetLastError()); if(p) VirtualFree(p,0,MEM_RELEASE);
  unsigned lo=0,hi=0xffffffff,mid; int n=0; void *q=NULL;
  do { if(q) VirtualFree(q,0,MEM_RELEASE); mid=(lo+hi)>>1; q=VirtualAlloc(NULL,mid,MEM_RESERVE,PAGE_READWRITE);
       if(q) lo=mid; else hi=mid; n++; } while(hi-lo>1 && n<200);
  fprintf(f,"search: %s after %d steps, lo=0x%08x hi=0x%08x\n", n>=200?"HANGS (cap hit)":"ends", n, lo, hi);
  MEMORY_BASIC_INFORMATION m; unsigned char *a=0; size_t best=0; void *bb=0;
  while(VirtualQuery(a,&m,sizeof m)){ if(m.State==MEM_FREE && m.RegionSize>best){best=m.RegionSize;bb=m.BaseAddress;} a=(unsigned char*)m.BaseAddress+m.RegionSize; if(!a) break; }
  fprintf(f,"largest free region: %lu MB at %p\n",(unsigned long)(best>>20),bb); fclose(f); return 0; }

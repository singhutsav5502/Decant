import struct, sys
def exports(path):
    d=open(path,'rb').read()
    pe=struct.unpack_from('<I',d,0x3c)[0]; magic=struct.unpack_from('<H',d,pe+24)[0]
    nsec=struct.unpack_from('<H',d,pe+6)[0]; opt=struct.unpack_from('<H',d,pe+20)[0]
    dd=pe+24+(96 if magic==0x10b else 112)
    erva=struct.unpack_from('<I',d,dd)[0]
    secs=[struct.unpack_from('<8sIIII',d,pe+24+opt+i*40) for i in range(nsec)]
    def off(rva):
        for n,vs,va,rs,ro in secs:
            if va<=rva<va+max(vs,rs): return rva-va+ro
    e=off(erva); nf,nn,af,anames,aord=struct.unpack_from('<IIIII',d,e+20)
    funcs=[struct.unpack_from('<I',d,off(af)+4*i)[0] for i in range(nf)]
    out={}
    for i in range(nn):
        nr=struct.unpack_from('<I',d,off(anames)+4*i)[0]; o=struct.unpack_from('<H',d,off(aord)+2*i)[0]
        n=d[off(nr):d.index(b'\0',off(nr))].decode(); out[funcs[o]]=n
    return out
ex=exports(sys.argv[1])
for t in sys.argv[2:]:
    t=int(t,16); best=max((r for r in ex if r<=t), default=None)
    print(hex(t), '->', ex.get(best), '+', hex(t-best) if best is not None else '')

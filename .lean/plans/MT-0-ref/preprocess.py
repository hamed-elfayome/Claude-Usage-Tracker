import re,sys,os
out=sys.argv[1]; files=sys.argv[2:]
for i,f in enumerate(files):
    lines=open(f,encoding='utf-8').read().split('\n'); res=[]; depth=None
    for ln in lines:
        if depth is None and re.match(r'\s*#Preview\b',ln): depth=0; started=False
        if depth is not None:
            depth+=ln.count('{')-ln.count('}'); started=started or '{' in ln
            res.append('')
            if started and depth<=0: depth=None
            continue
        res.append(re.sub(r'@State\b(?!Object)',r'@CLTState',ln))
    open(os.path.join(out,f"{i:03d}_"+os.path.basename(f)),'w').write('\n'.join(res))

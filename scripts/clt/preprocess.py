"""Copy app sources to OUT/NNN_<basename>, adapted for Command Line Tools (no Xcode).

Usage: python3 -I preprocess.py OUT FILE...
- first line: #sourceLocation so diagnostics name the original file and line
- top-level #Preview blocks are blanked line by line (line count is kept)
- @State -> @CLTState (the SwiftUI macro plugin is missing in CLT)
- adds CLTSupport.swift with the typealias
"""
import re, sys, os

out = sys.argv[1]
files = sys.argv[2:]
for i, f in enumerate(files):
    lines = open(f, encoding='utf-8').read().split('\n')
    res = []
    depth = None
    started = False
    for ln in lines:
        if depth is None and re.match(r'\s*#Preview\b', ln):
            depth = 0
            started = False
        if depth is not None:
            depth += ln.count('{') - ln.count('}')
            started = started or '{' in ln
            res.append('')
            if started and depth <= 0:
                depth = None
            continue
        res.append(re.sub(r'@State\b', '@CLTState', ln))
    esc = os.path.abspath(f).replace('\\', '\\\\').replace('"', '\\"')
    # directive sits on line 1; original line 1 follows it as line 1
    text = '#sourceLocation(file: "%s", line: 1)\n' % esc + '\n'.join(res)
    with open(os.path.join(out, "%03d_%s" % (i, os.path.basename(f))), 'w') as fh:
        fh.write(text)
with open(os.path.join(out, "CLTSupport.swift"), 'w') as fh:
    fh.write("import SwiftUI\ntypealias CLTState = SwiftUI.State\n")

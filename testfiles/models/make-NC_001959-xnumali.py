#!/usr/bin/env python3
# Usage (from testfiles/models/): python3 make-NC_001959-xnumali.py
# Reads NC_001959.fa and NC_001959.vadr.protein.fa from the current directory
# and writes blastx-NC_001959-xnumali/NC_001959.vadr.protein.fa
# (then run makeblastdb, see update-blastdbs.sh).
#
# Builds the 28-protein blastx library for the --xnumali regression test
# (../noro.xnumali.testin, ../do-xnumali-tests.sh):
#  - the NC_001959 ORF1 and VP2 reference proteins, unchanged;
#  - XNUMALIDIV.1: the VP1 (5358..6950:+) reference protein with 40% of
#    residues 38..520 randomly substituted (64% identical, full length);
#  - the reference protein for 'VP1 short form' (5454..6950:+, from the
#    in-frame Met at VP1 aa 33) plus 24 variants with 2 substitutions each
#    (XNUMALI01..24).
# The 25 short form proteins outscore the single VP1 protein, so with
# blastx -num_alignments 20 the VP1 protein is not reported.
# The other fixture files are not generated: NC_001959.xnumali.minfo is
# NC_001959.minfo plus the 'VP1 short form' CDS feature line, and
# ../noro.xnumali.fa is a copy of NC_001959.fa.
# Output is deterministic (fixed random seed).
import os
import random
import sys
random.seed(9)
seq = "".join(l.strip() for l in open("NC_001959.fa") if not l.startswith(">")).upper()
sys.stderr.write("codon at 5454: %s\n" % (seq[5453:5456]))
prot = {}; name = None
for l in open("NC_001959.vadr.protein.fa"):
    l = l.strip()
    if l.startswith(">"): name = l[1:]; prot[name] = ""
    else: prot[name] += l
vp1 = prot["NC_001959.2/5358..6950:+"]
m = 32  # 0-based aa index of in-frame Met at nt 5454
assert vp1[m] == "M"
aas = "ACDEFGHIKLMNPQRSTVWY"
p = list(vp1); idx = list(range(m+5, len(p)-10)); random.shuffle(idx)
for i in idx[:int(0.40*len(idx))]: p[i] = random.choice([a for a in aas if a != p[i]])
outer = "".join(p)
inner_ref = vp1[m:]
inner = [("NC_001959.2/5454..6950:+", inner_ref)]; seen = {inner_ref}; k = 1
while len(inner) < 25:
    q = list(inner_ref)
    for i in random.sample(range(10, len(q)-10), 2): q[i] = random.choice([a for a in aas if a != q[i]])
    q = "".join(q)
    if q in seen: continue
    seen.add(q); inner.append(("XNUMALI%02d.1/5454..6950:+" % k, q)); k += 1
def w(f, n, s):
    f.write(">" + n + "\n")
    for i in range(0, len(s), 60): f.write(s[i:i+60] + "\n")
if not os.path.isdir("blastx-NC_001959-xnumali"): os.mkdir("blastx-NC_001959-xnumali")
with open("blastx-NC_001959-xnumali/NC_001959.vadr.protein.fa", "w") as f:
    w(f, "NC_001959.2/5..5374:+", prot["NC_001959.2/5..5374:+"])
    w(f, "XNUMALIDIV.1/5358..6950:+", outer)
    for n, s in inner: w(f, n, s)
    w(f, "NC_001959.2/6950..7588:+", prot["NC_001959.2/6950..7588:+"])
sys.stderr.write("VP1 protein identity %d/%d\n" % (sum(a == b for a, b in zip(outer, vp1)), len(vp1)))

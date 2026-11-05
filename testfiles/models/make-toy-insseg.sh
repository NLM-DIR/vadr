#!/bin/bash
# Builds toy-insseg.cm, a 150 position toy model used by insseg.testin to test
# a CDS whose aligned nucleotides are all inserts (no model position in the
# CDS aligns to a nucleotide). Such alignments are rare with a normally
# built model (they have been seen for long runs of Ns), so after building,
# the transitions of a few states are edited so that model positions 61..90
# (CDS one in toy-insseg.minfo) can only be deleted, and the insert state
# after position 75 can be entered from and left to a delete state.
# Usage (from testfiles/models/): sh make-toy-insseg.sh
# Requires Infernal 1.1.x cmbuild and cmpress in $VADRINFERNALDIR.
# (brief 26_0602-061)
set -e
rm -f toy-insseg.cm toy-insseg.cm.i1*
$VADRINFERNALDIR/cmbuild -F --hand --noss -n toy-insseg toy-insseg.cm toy-insseg.stk > /dev/null
python3 - <<'PYEOF'
import re
# fields 11-13 of a MATL state line are its transition scores (bits):
# to the IL state of the same node, to the ML of the next node, to the D of the next node
new = {(60, 'ML'): (-20.0, -20.0,  0.0)}   # position 60 match always goes to delete 61
for k in range(61, 90):
    new[(k, 'D')] = (-20.0, -20.0, 0.0)    # deletes 61..89 always go to the next delete
new[(75, 'D')]  = (-1.0, -20.0, -1.0)      # delete 75 can go to insert after 75
new[(75, 'IL')] = (-1.0, -20.0, -1.0)      # insert after 75 can go to delete 76
lines = open('toy-insseg.cm').readlines()
node = None
for i, l in enumerate(lines):
    m = re.search(r'\[ MATL\s+(\d+) \]', l)
    if m:
        node = int(m.group(1))
        continue
    if l.startswith('HMMER3'):
        break # don't touch the filter HMMs
    t = l.split()
    if node is not None and len(t) >= 13 and (node, t[0]) in new:
        f = re.split(r'(\s+)', l.rstrip('\n'))
        tok = [j for j, x in enumerate(f) if x and not x.isspace()]
        for j, v in zip(tok[10:13], new[(node, t[0])]):
            f[j] = '%.3f' % v
        lines[i] = ''.join(f) + '\n'
open('toy-insseg.cm', 'w').write(''.join(lines))
PYEOF
# record the command without the install path, like the other toy models
sed -i.bak -E 's#^(COM +\[[0-9]+\] ).*/cmbuild#\1cmbuild#' toy-insseg.cm && rm toy-insseg.cm.bak
$VADRINFERNALDIR/cmpress toy-insseg.cm > /dev/null

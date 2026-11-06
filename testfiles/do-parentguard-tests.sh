#!/bin/sh
#
# Tests that v-annotate.pl refuses a model info file in which a
# mat_peptide's parent is not a CDS: entoy100a.mpgeneparent.minfo is
# entoy100a.minfo with the parent of the first mat_peptide changed from
# the CDS (feature 1) to the gene (feature 0). v-annotate.pl must exit
# non-zero with an error that names the mat_peptide's parent type.
#
RETVAL=0
OUT=va-parentguard.$$
$VADRSCRIPTSDIR/v-annotate.pl -f --pv_skip -m $VADRSCRIPTSDIR/testfiles/models/entoy100a.cm -i $VADRSCRIPTSDIR/testfiles/models/entoy100a.mpgeneparent.minfo $VADRSCRIPTSDIR/testfiles/entoy100a-af1.fa $OUT > $OUT.out 2>&1
if [ "$?" -eq 0 ]; then
    echo "FAIL: v-annotate.pl accepted a mat_peptide whose parent is a gene [do-parentguard-tests.sh]"
    RETVAL=1
elif ! grep -q 'is a mat_peptide whose parent (ftr_idx: 0) is a gene, not a CDS' $OUT.out; then
    echo "FAIL: v-annotate.pl failed, but not with the expected error message [do-parentguard-tests.sh]"
    RETVAL=1
fi
rm -rf $OUT $OUT.out

if [ "$RETVAL" -eq 0 ]; then
   echo "Success: all tests passed [do-parentguard-tests.sh]"
   exit 0
else
   echo "FAIL: at least one test failed [do-parentguard-tests.sh]"
   exit 1
fi

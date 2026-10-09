#!/bin/bash

RETVAL=0;

# noro.xnumali
$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/noro.xnumali.testin noro.xnumali
if [ "$?" -ne 0 ]; then
   RETVAL=1;
fi   

# noro.xnumali again, with $VADRBLASTDIR pointed at a temporary directory
# that holds only blastn, blastp, blastx and makeblastdb (as in some BLAST+
# installations), to check that no other BLAST+ executable is required
TMPBLASTDIR=$PWD/va-xnumali-blast.$$
mkdir $TMPBLASTDIR
for f in blastn blastp blastx makeblastdb; do
    ln -s $VADRBLASTDIR/$f $TMPBLASTDIR/
done
VADRBLASTDIR=$TMPBLASTDIR $VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/noro.xnumali.testin noro.xnumali.minblast
if [ "$?" -ne 0 ]; then
   RETVAL=1;
fi   
rm -rf $TMPBLASTDIR

if [ "$RETVAL" -eq 0 ]; then
   echo "Success: all tests passed [do-xnumali-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-xnumali-tests.sh]"
   exit 1
fi

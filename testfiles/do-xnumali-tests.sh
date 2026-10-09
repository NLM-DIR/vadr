#!/bin/bash

RETVAL=0;

# noro.xnumali
$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/noro.xnumali.testin noro.xnumali
if [ "$?" -ne 0 ]; then
   RETVAL=1;
fi   

if [ "$RETVAL" -eq 0 ]; then
   echo "Success: all tests passed [do-xnumali-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-xnumali-tests.sh]"
   exit 1
fi

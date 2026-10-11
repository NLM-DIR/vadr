#!/bin/bash

RETVAL=0;

$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/vscan.testin vt-vscan
if [ "$?" -eq 0 ]; then
   echo "Success: all tests passed [do-vscan-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-vscan-tests.sh]"
   exit 1
fi

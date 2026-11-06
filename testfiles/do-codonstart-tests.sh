#!/bin/bash

RETVAL=0;

$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/codonstart.testin vt-codonstart
if [ "$?" -eq 0 ]; then
   echo "Success: all tests passed [do-codonstart-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-codonstart-tests.sh]"
   exit 1
fi

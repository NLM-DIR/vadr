#!/bin/bash

RETVAL=0;

$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/noannotn.testin vt-noannotn
if [ "$?" -eq 0 ]; then
   echo "Success: all tests passed [do-noannotn-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-noannotn-tests.sh]"
   exit 1
fi

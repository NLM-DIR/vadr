#!/bin/bash

RETVAL=0;

$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/insseg.testin vt-insseg
if [ "$?" -eq 0 ]; then
   echo "Success: all tests passed [do-insseg-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-insseg-tests.sh]"
   exit 1
fi

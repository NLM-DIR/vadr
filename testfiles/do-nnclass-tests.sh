#!/bin/bash

RETVAL=0;

$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/nnclass.testin vt-nnclass
if [ "$?" -eq 0 ]; then
   echo "Success: all tests passed [do-nnclass-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-nnclass-tests.sh]"
   exit 1
fi

#!/bin/bash

RETVAL=0;

$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/nnmask.testin vt-nnmask
if [ "$?" -eq 0 ]; then
   echo "Success: all tests passed [do-nnmask-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-nnmask-tests.sh]"
   exit 1
fi

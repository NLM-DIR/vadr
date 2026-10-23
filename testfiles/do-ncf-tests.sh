#!/bin/bash

RETVAL=0;

$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/entoy100a-ncf.testin vt-entoy100a-ncf
if [ "$?" -ne 0 ]; then
   RETVAL=1;
fi   

if [ "$RETVAL" -eq 0 ]; then
   echo "Success: all tests passed [do-ncf-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-ncf-tests.sh]"
   exit 1
fi

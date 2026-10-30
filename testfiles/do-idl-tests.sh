#!/bin/bash

RETVAL=0;

# noro.vp2rev.idl: --out_idl and miniscripts/vadr-propose-indel-exc.pl
$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/noro.vp2rev.idl.testin noro.vp2rev.idl
if [ "$?" -ne 0 ]; then
   RETVAL=1;
fi   

if [ "$RETVAL" -eq 0 ]; then
   echo "Success: all tests passed [do-idl-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-idl-tests.sh]"
   exit 1
fi

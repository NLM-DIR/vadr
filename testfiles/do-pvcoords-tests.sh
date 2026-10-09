#!/bin/bash

RETVAL=0;

# noro.vp2rev.pvcoords
$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/noro.vp2rev.pvcoords.testin noro.vp2rev.pvcoords
if [ "$?" -ne 0 ]; then
   RETVAL=1;
fi   

if [ "$RETVAL" -eq 0 ]; then
   echo "Success: all tests passed [do-pvcoords-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed do-pvcoords-tests.sh]"
   exit 1
fi

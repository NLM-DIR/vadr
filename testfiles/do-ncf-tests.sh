#!/bin/bash

RETVAL=0;

$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/entoy100a-ncf.testin vt-entoy100a-ncf
if [ "$?" -ne 0 ]; then
   RETVAL=1;
fi   

# --ncf misc and --mnf_legacy cannot be used together, v-annotate.pl should exit with an error at startup
perl $VADRSCRIPTSDIR/v-annotate.pl --ncf misc --mnf_legacy -f --pv_skip --mdir $VADRSCRIPTSDIR/testfiles/models --mkey entoy100a $VADRSCRIPTSDIR/testfiles/entoy100a-lowsim.fa va-entoy100a-ncfmisc-legacy > va-entoy100a-ncfmisc-legacy.out 2>&1
if [ "$?" -eq 0 ]; then
   echo "FAIL: --ncf misc --mnf_legacy did not cause an error"
   RETVAL=1;
elif ! grep -q "ERROR, --mnf_legacy cannot be used with --ncf misc" va-entoy100a-ncfmisc-legacy.out; then 
   echo "FAIL: --ncf misc --mnf_legacy did not cause the expected error"
   RETVAL=1;
else
   echo "Success: --ncf misc --mnf_legacy caused the expected error"
fi
rm -rf va-entoy100a-ncfmisc-legacy va-entoy100a-ncfmisc-legacy.out

if [ "$RETVAL" -eq 0 ]; then
   echo "Success: all tests passed [do-ncf-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-ncf-tests.sh]"
   exit 1
fi

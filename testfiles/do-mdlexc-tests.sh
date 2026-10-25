#!/bin/bash
# tests for insertn_mdl_exc/deletin_mdl_exc/indfstr_mdl_exc, the recommended, exact-model-position
# alternatives to the legacy insertn_exc/deletin_exc/indfstr_exc keys (brief 26_0602-046).
#
# the success-path tests (insertn_mdl_exc/deletin_mdl_exc reproduce the legacy-key results of
# commands 5-6 in noro.vp2rev.pvcoords.testin) are commands 7-8 of that testin, run via
# do-pvcoords-tests.sh. this script covers the one thing v-test.pl can't: a model info file
# that is expected to be REJECTED.

RETVAL=0;

# a feature that defines both the legacy (insertn_exc) and recommended (insertn_mdl_exc) key for
# the same alert family must be rejected as a validation error, since the two keys use different
# coordinate systems (approximate vs exact) for insertnp
ERR_FILE=va-noro-vp2rev-mixedexc.err
rm -f $ERR_FILE
perl $VADRSCRIPTSDIR/v-annotate.pl -f --glsearch -s -n $VADRSCRIPTSDIR/testfiles/models/NC_001959-vp2rev.fa -i $VADRSCRIPTSDIR/testfiles/models/NC_001959-vp2rev.mixedexc.minfo -x $VADRSCRIPTSDIR/testfiles/models $VADRSCRIPTSDIR/testfiles/noro.vp2rev.pvcoords.1.fa va-noro-vp2rev-mixedexc > $ERR_FILE 2>&1
MIXEDEXC_EXIT=$?
rm -rf va-noro-vp2rev-mixedexc
if [ "$MIXEDEXC_EXIT" -eq 0 ]; then
   echo "FAIL: v-annotate.pl exited 0 on a model info file with both insertn_exc and insertn_mdl_exc defined on the same feature (expected a validation error) [do-mdlexc-tests.sh]"
   RETVAL=1;
else
   grep -q "feature defines both exception keys insertn_exc and insertn_mdl_exc" $ERR_FILE
   if [ "$?" -ne 0 ]; then
      echo "FAIL: v-annotate.pl did not report the expected 'feature defines both exception keys' error [do-mdlexc-tests.sh]"
      RETVAL=1;
   fi
fi
rm -f $ERR_FILE

if [ "$RETVAL" -eq 0 ]; then
   echo "Success: all tests passed [do-mdlexc-tests.sh]"
   exit 0
else
   echo "FAIL: at least one test failed [do-mdlexc-tests.sh]"
   exit 1
fi

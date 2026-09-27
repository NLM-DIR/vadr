#!/bin/bash
#
# Checks that 'vadr-install.sh <platform> --dry-run' lists exactly the
# downloads in testfiles/vadr-install.<platform>.dry-run.txt, and that
# 'download' mode lists the same downloads and 'build' mode lists none.
# Needs no network: a dry run downloads nothing.
#
# If a change to vadr-install.sh is meant to change what it downloads (a
# version bump, say), regenerate the expected files with:
#   sh ./vadr-install.sh <platform> --dry-run | grep '^FETCH ' > testfiles/vadr-install.<platform>.dry-run.txt
# and check that the diff is exactly the intended change.
#
# usage: do-install-dry-run-tests.sh [path to vadr-install.sh]
# (default: the vadr-install.sh next to this script's directory, so that the
#  script under test and the expected files always come from the same copy of
#  the repository; $VADRSCRIPTSDIR may point somewhere else entirely)

TESTDIR=`dirname $0`
INSTALLSCRIPT=${1:-$TESTDIR/../vadr-install.sh}
RETVAL=0;

for platform in linux macosx-silicon macosx-intel; do
    expected=$TESTDIR/vadr-install.$platform.dry-run.txt
    for mode in "" download; do
        sh $INSTALLSCRIPT $platform $mode --dry-run | grep '^FETCH ' | diff $expected -
        if [ "$?" -ne 0 ]; then
            echo "FAIL: vadr-install.sh $platform $mode --dry-run differs from $expected"
            RETVAL=1;
        fi
    done
    nfetch=`sh $INSTALLSCRIPT $platform build --dry-run | grep -c '^FETCH '`
    if [ "$nfetch" -ne 0 ]; then
        echo "FAIL: vadr-install.sh $platform build --dry-run lists $nfetch downloads, expected 0"
        RETVAL=1;
    fi
done

if [ "$RETVAL" -eq 0 ]; then
   echo "Success: all tests passed [do-install-dry-run-tests.sh]"
   exit 0
else
   echo "FAIL: at least one test failed [do-install-dry-run-tests.sh]"
   exit 1
fi

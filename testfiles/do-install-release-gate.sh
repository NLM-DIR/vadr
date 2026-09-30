#!/bin/bash
#
# RELEASE GATE for vadr-install.sh. Runs the installer's test scripts and
# reports which ones passed and which failed:
#
#   do-install-dry-run-tests.sh      expected download lists, all 3 platforms   (no network)
#   do-install-models-tests.sh       --models selection and error cases        (no network)
#   do-check-model-sizes-network.sh  every model URL: resolves, and size matches (NEEDS NETWORK)
#
# The first two always run. The network check runs only with --network. Run
# the gate WITH --network before every release, and whenever a model version
# pin changes.
#
# With --network it cannot run under qsub: SGE execution nodes have no
# internet. Run it on a login node.
#
# Not part of do-all-tests.sh, on purpose: that suite must stay offline.
#
# usage: do-install-release-gate.sh [--network] [path to vadr-install.sh]
# (the path, if given, is passed to each test script; default: the
#  vadr-install.sh next to this script's directory)
# exit status: 0 if every test that ran passed, 1 otherwise

usage () {
    echo "Usage: do-install-release-gate.sh [--network] [path to vadr-install.sh]"
    echo "  --network: also run do-check-model-sizes-network.sh (needs internet,"
    echo "             so not under qsub); required before a release"
}

TESTDIR=`dirname $0`
NETWORK=0
INSTALLARG=""
for arg in "$@"; do
    case "$arg" in
        --network) NETWORK=1 ;;
        -h|--help) usage; exit 0 ;;
        -*)        echo "ERROR: unknown option $arg"; usage; exit 1 ;;
        *)         if [ "$INSTALLARG" != "" ]; then echo "ERROR: more than one path given"; usage; exit 1; fi
                   INSTALLARG=$arg ;;
    esac
done

TESTS="do-install-dry-run-tests.sh do-install-models-tests.sh"
if [ "$NETWORK" -eq 1 ]; then TESTS="$TESTS do-check-model-sizes-network.sh"; fi

RETVAL=0
REPORT=""
for t in $TESTS; do
    echo "=== $t"
    sh $TESTDIR/$t $INSTALLARG
    if [ "$?" -ne 0 ]; then
        RETVAL=1
        REPORT="$REPORT  FAIL     $t\n"
    else
        REPORT="$REPORT  pass     $t\n"
    fi
done
if [ "$NETWORK" -eq 0 ]; then
    REPORT="$REPORT  SKIPPED  do-check-model-sizes-network.sh (needs network; rerun with --network)\n"
fi

echo ""
echo "Summary [do-install-release-gate.sh]:"
printf "$REPORT"
if [ "$NETWORK" -eq 0 ]; then
    echo "NOTE: the network check was skipped; a release needs 'do-install-release-gate.sh --network'"
fi

if [ "$RETVAL" -eq 0 ]; then
   echo "Success: all tests that ran passed [do-install-release-gate.sh]"
   exit 0
else
   echo "FAIL: at least one test failed [do-install-release-gate.sh]"
   exit 1
fi

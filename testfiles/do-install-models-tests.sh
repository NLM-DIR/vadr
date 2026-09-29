#!/bin/bash
#
# Checks the --models and --list-models options of vadr-install.sh, using
# --dry-run so that nothing is downloaded and no network is needed. The models
# a dry run lists are compared to the lines for those models in
# testfiles/vadr-install.linux.dry-run.txt, so the URLs come from the same
# expected file that do-install-dry-run-tests.sh checks.
#
# usage: do-install-models-tests.sh [path to vadr-install.sh]

TESTDIR=`dirname $0`
INSTALLSCRIPT=${1:-$TESTDIR/../vadr-install.sh}
EXPECTED=$TESTDIR/vadr-install.linux.dry-run.txt
RETVAL=0

fail () { echo "FAIL: $1"; RETVAL=1; }

# models_fetched <args>: the vadr-models FETCH lines a dry run with those arguments lists
models_fetched () { sh $INSTALLSCRIPT "$@" --dry-run 2>/dev/null | grep '^FETCH .*vadr-models-'; }
# models_expected <names>: the lines for those models from the expected file, in file order
models_expected () { for m in "$@"; do grep "/vadr-models-$m-[0-9.-]*\.tar\.gz " $EXPECTED; done; }

# check_selection <description> <space-separated expected libraries, in download order> <args>
check_selection () {
    desc=$1; libs=$2; shift 2
    got=`models_fetched "$@"`
    exp=`models_expected $libs`
    if [ "$got" != "$exp" ]; then fail "$desc: 'vadr-install.sh $*' listed the wrong models"; fi
}

# check_error <description> <args>: exit status 1, an ERROR message, and no downloads at all
check_error () {
    desc=$1; shift
    out=`sh $INSTALLSCRIPT "$@" --dry-run 2>&1`; rc=$?
    if [ "$rc" -ne 1 ]; then fail "$desc: exit status $rc, expected 1"; fi
    echo "$out" | grep -q '^ERROR: ' || fail "$desc: no ERROR message"
    echo "$out" | grep -q '^FETCH ' && fail "$desc: something would have been downloaded"
}

ALL="calici flavi zika corona sarscov2 flu rsv mpxv"

check_selection "no flag" "$ALL" linux
check_selection "all" "$ALL" linux --models all
check_selection "two" "flu rsv" linux --models flu,rsv
check_selection "one from each URL family" "calici zika" linux --models calici,zika
check_selection "each library alone" "corona" linux --models corona
check_selection "none" "" linux --models none
check_selection "= form" "flu" linux --models=flu
check_selection "before mode" "flu" linux --models flu download
check_selection "after mode" "flu" linux download --models flu
check_selection "before platform" "flu" --models flu linux
check_selection "download order, not list order" "flu rsv" linux --models rsv,flu
check_selection "duplicates" "flu rsv" linux --models rsv,flu,rsv
check_selection "mixed case" "flu rsv" linux --models Flu,RSV
check_selection "spaces after commas" "flu rsv" linux --models "flu, rsv"
check_selection "build ignores it" "" linux build --models flu

check_error "unknown name" linux --models flu,bogus
check_error "only unknown name" linux --models bogus
check_error "no value" linux --models
check_error "empty value" linux --models ""
check_error "given twice" linux --models flu --models rsv
check_error "empty entry" linux --models flu,,rsv
check_error "trailing comma" linux --models flu,
check_error "all with a name" linux --models all,flu
check_error "none with a name" linux --models none,flu

# --list-models: one line per library plus a final 'total' line, each library
# selectable with --models, no platform needed
n=`sh $INSTALLSCRIPT --list-models | grep -v '^total ' | wc -l`
if [ "$n" -ne 8 ]; then fail "--list-models printed $n library lines, expected 8"; fi
for m in `sh $INSTALLSCRIPT --list-models | grep -v '^total ' | awk '{ print $1 }'`; do
    n=`models_fetched linux --models $m | wc -l`
    if [ "$n" -ne 1 ]; then fail "--list-models names $m but --models $m selects $n libraries"; fi
done
sh $INSTALLSCRIPT --list-models > /dev/null || fail "--list-models exit status not 0"

# argument parsing that must be unchanged
sh $INSTALLSCRIPT > /dev/null 2>&1 && fail "no arguments did not fail"
sh $INSTALLSCRIPT linux download build > /dev/null 2>&1 && fail "download and build together did not fail"
sh $INSTALLSCRIPT linux --dry-run 2>&1 | grep -q '^Usage:' && fail "a valid command line printed usage"
sh $INSTALLSCRIPT 2>&1 | grep -q '^Usage:' || fail "no arguments did not print usage"

if [ "$RETVAL" -eq 0 ]; then
   echo "Success: all tests passed [do-install-models-tests.sh]"
   exit 0
else
   echo "FAIL: at least one test failed [do-install-models-tests.sh]"
   exit 1
fi

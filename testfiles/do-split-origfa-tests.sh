#!/bin/sh
#
# Tests that v-annotate.pl --split --origfa leaves the caller's input
# fasta file in place, and removes the chunk files (and their .ssi
# indices) it creates, which with --origfa are written next to the
# input file. Also tests v-scan.pl -m --cpu 2 on a small input, which
# runs v-annotate.pl --split --origfa once per model library on the
# same input file.
#
# Input files are copied into a temporary directory first, so that
# chunk files are never written to testfiles/.
#
RETVAL=0

if [ -z "$VADRSCRIPTSDIR" ]; then
    echo "FAIL: VADRSCRIPTSDIR must be set [do-split-origfa-tests.sh]"
    exit 1
fi

TMPROOT=va-splitorigfa.$$
mkdir $TMPROOT
MDIR=$VADRSCRIPTSDIR/testfiles/models

check () {
    if [ "$2" = "0" ]; then
        printf "#\t%-100s ... pass\n" "$1"
    else
        printf "#\t%-100s ... FAIL\n" "$1"
        RETVAL=1
    fi
}

# usage: run_case <name> <input fasta> <v-annotate.pl model options>
# copies <input fasta> to $TMPROOT/<name>.fa, runs v-annotate.pl --split
# --cpu 2 --origfa on it and checks: zero exit status, the input file is
# unchanged, and no chunk files or .ssi indices of chunk files are left
run_case () {
    name=$1; infa=$2; shift 2
    fa=$TMPROOT/$name.fa
    cp $infa $fa
    $VADRSCRIPTSDIR/v-annotate.pl --split --cpu 2 --origfa "$@" $fa $TMPROOT/$name > $TMPROOT/$name.stdout 2> $TMPROOT/$name.stderr
    status=$?
    [ $status -eq 0 ];                                check "$name: v-annotate.pl --split --origfa exits with zero status" $?
    [ -e $fa ] && cmp -s $fa $infa;                   check "$name: input fasta file still exists and is unchanged" $?
    left=`ls $fa.[0-9]* 2> /dev/null`
    [ -z "$left" ];                                   check "$name: no chunk files or chunk .ssi files are left" $?
}

# 1. one sequence: v-annotate.pl does not split the input, and uses it as the only chunk
run_case one $MDIR/entoy100a-dcr-del.fa --pv_skip --mdir $MDIR --mkey entoy100a-dcr-del

# 2. three short sequences: esl-ssplit -r -n 2 creates only one chunk file
run_case three $VADRSCRIPTSDIR/testfiles/vscan-m1.fa -s --cls_only --mdir $MDIR --mkey dengue.2

# 3. six sequences: two chunk files
run_case six $VADRSCRIPTSDIR/testfiles/vscan-m.fa -s --cls_only --mdir $MDIR --mkey dengue.2

# 4. v-scan.pl -m --cpu 2 with two model libraries on three sequences:
#    the second library's v-annotate.pl --cls_only run needs the input
#    file the first one used
sed "s:@MDIR@:$MDIR:" $VADRSCRIPTSDIR/testfiles/vscan-m.config > $TMPROOT/vscan-m.config
#    (run in $TMPROOT because v-scan.pl's output directory must be in the
#    current directory)
(cd $TMPROOT && perl $VADRSCRIPTSDIR/v-scan.pl -f -m --cpu 2 -c vscan-m.config $VADRSCRIPTSDIR/testfiles/vscan-m1.fa vscan > vscan.stdout 2> vscan.stderr)
[ $? -eq 0 ]; check "vscan: v-scan.pl -m --cpu 2 on 3 sequences with 2 libraries exits with zero status" $?

if [ "$RETVAL" -eq 0 ]; then
    rm -rf $TMPROOT
    echo "Success: all tests passed [do-split-origfa-tests.sh]"
    exit 0
else
    echo "FAIL: at least one test failed, output left in $TMPROOT [do-split-origfa-tests.sh]"
    exit 1
fi

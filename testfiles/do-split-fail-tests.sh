#!/bin/sh
#
# Tests that v-annotate.pl --split fails promptly and cleanly when one of
# its per-chunk v-annotate.pl jobs fails: it must exit non-zero within a
# time limit (not wait out --wait), name the failed chunk in its error
# message, and leave none of its worker processes running.
#
# To make a chunk fail deterministically, $VADRINFERNALDIR is pointed at a
# temporary directory of symlinks to the real Infernal executables, except
# that cmalign is a wrapper that, when the sequence file it is given
# contains a sequence named:
#   failme-kill: kills itself with SIGKILL (like an out-of-memory kill)
#   failme-exit: exits with status 1
#   slowme:      sleeps for 600 seconds first (so its chunk is still
#                running when another chunk fails)
# and otherwise runs the real cmalign.
#
RETVAL=0

if [ -z "$VADRSCRIPTSDIR" ] || [ -z "$VADRINFERNALDIR" ]; then
    echo "FAIL: VADRSCRIPTSDIR and VADRINFERNALDIR must be set [do-split-fail-tests.sh]"
    exit 1
fi

MAXSECS=90
TMPROOT=va-splitfail.$$
REALINFDIR=$VADRINFERNALDIR
mkdir $TMPROOT
mkdir $TMPROOT/infernal
for f in $REALINFDIR/*; do
    ln -s $f $TMPROOT/infernal/
done
rm $TMPROOT/infernal/cmalign
cat > $TMPROOT/infernal/cmalign << EOF
#!/bin/sh
for seqfile in "\$@"; do :; done
if grep -q '^>failme-kill' "\$seqfile"; then kill -9 \$\$; fi
if grep -q '^>failme-exit' "\$seqfile"; then echo "cmalign wrapper: deliberate failure" 1>&2; exit 1; fi
if grep -q '^>slowme' "\$seqfile"; then sleep 600; fi
exec $REALINFDIR/cmalign "\$@"
EOF
chmod +x $TMPROOT/infernal/cmalign

# write a fasta file of <n> copies of the toy model's reference sequence,
# with sequence <i> named <name>, for each <i>:<name> pair given
# usage: make_fasta <out.fa> <n> [<i>:<name> ...]
REFSEQ=`grep -v '^>' $VADRSCRIPTSDIR/testfiles/models/entoy100a-dcr-del.fa | tr -d '\n'`
make_fasta () {
    out=$1; n=$2; shift 2
    : > $out
    i=1
    while [ $i -le $n ]; do
        name="seq$i"
        for pair in "$@"; do
            if [ "${pair%%:*}" = "$i" ]; then name="${pair#*:}"; fi
        done
        printf ">%s\n%s\n" $name $REFSEQ >> $out
        i=$((i+1))
    done
}

check () {
    if [ "$2" = "0" ]; then
        printf "#\t%-100s ... pass\n" "$1"
    else
        printf "#\t%-100s ... FAIL\n" "$1"
        RETVAL=1
    fi
}

# usage: run_case <name> <ncpu> <fasta>
# runs v-annotate.pl --split and checks: non-zero exit, finished within
# $MAXSECS seconds, error message names the chunk holding the failme
# sequence, and no process of the run is left
run_case () {
    name=$1; ncpu=$2; fasta=$3
    out=$TMPROOT/$name
    start=`date +%s`
    VADRINFERNALDIR=$TMPROOT/infernal $VADRSCRIPTSDIR/v-annotate.pl --split --cpu $ncpu --nkb 1 --keep --pv_skip \
        --mdir $VADRSCRIPTSDIR/testfiles/models --mkey entoy100a-dcr-del $fasta $out > $out.stdout 2> $out.stderr &
    vpid=$!
    # watchdog: if v-annotate.pl is still running well past $MAXSECS, kill it 
    # and everything it started, so a regression fails here instead of hanging
    while kill -0 $vpid 2> /dev/null && [ $((`date +%s` - start)) -le $((MAXSECS + 30)) ]; do
        sleep 1
    done
    if kill -0 $vpid 2> /dev/null; then
        kill -9 $vpid > /dev/null 2>&1
        pkill -9 -f "$out/" > /dev/null 2>&1
    fi
    wait $vpid
    status=$?
    secs=$((`date +%s` - start))
    [ $status -ne 0 ];                   check "$name: v-annotate.pl --split exits with non-zero status" $?
    [ $secs -le $MAXSECS ];              check "$name: fails within $MAXSECS seconds (took $secs)" $?
    failchunk=`grep -l '^>failme' $out/$name.vadr.in.fa.[0-9]* 2>/dev/null | head -n 1`
    [ -n "$failchunk" ] && grep -q "failed on $failchunk " $out.stderr
    check "$name: error message names the failed chunk ($failchunk)" $?
    sleep 1
    if ps -A -o args= | grep -v grep | grep -q "$out/"; then left=1; else left=0; fi
    check "$name: no worker processes are left running" $left
    if [ $left -ne 0 ]; then
        pkill -9 -f "$out/" > /dev/null 2>&1
    fi
}

# 20 seqs of 100 nt with --nkb 1 make 2 chunks, 30 seqs make 3, 40 seqs make 4;
# with --cpu N, worker script 1 runs chunks 1, N+1, ... in the foreground and
# worker script k runs chunks k, N+k, ... in the background

# 1. the background script's only chunk is SIGKILLed
make_fasta $TMPROOT/bgkill.fa 20 20:failme-kill
run_case bgkill 2 $TMPROOT/bgkill.fa

# 2. the foreground script's chunk fails
make_fasta $TMPROOT/fgexit.fa 20 1:failme-exit
run_case fgexit 2 $TMPROOT/fgexit.fa

# 3. the first of a background script's two chunks fails (4 chunks, 2 scripts)
make_fasta $TMPROOT/midexit.fa 40 15:failme-exit
run_case midexit 2 $TMPROOT/midexit.fa

# 4. a background script's chunk fails while another background script's
#    chunk is still running (it must be killed)
make_fasta $TMPROOT/sibling.fa 30 15:failme-exit 25:slowme
run_case sibling 3 $TMPROOT/sibling.fa

if [ "$RETVAL" -eq 0 ]; then
   rm -rf $TMPROOT
   echo "Success: all tests passed [do-split-fail-tests.sh]"
   exit 0
else
   echo "FAIL: at least one test failed [do-split-fail-tests.sh] (output left in $TMPROOT)"
   exit 1
fi

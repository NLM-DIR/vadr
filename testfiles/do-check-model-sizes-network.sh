#!/bin/bash
#
# RELEASE STEP, NEEDS NETWORK. Checks every model URL vadr-install.sh would fetch
# against the FTP site: that it resolves (HTTP 200) AND that its Content-Length
# equals the size in bytes that vadr-install.sh's model_size() table (shown by
# 'vadr-install.sh --list-models') has for it. Run it whenever a model version
# pin changes and before every release. Not part of do-all-tests.sh.
#
# It cannot run under qsub: SGE execution nodes have no internet.
# There is no tolerance; a size that differs by one byte is reported.
#
# usage: do-check-model-sizes-network.sh [path to vadr-install.sh]
# exit status: 0 if every URL resolves and every size matches, 1 otherwise

TESTDIR=`dirname $0`
INSTALLSCRIPT=${1:-$TESTDIR/../vadr-install.sh}
RETVAL=0
NCHECKED=0

# the URLs come from a real --dry-run, so this checks what the installer fetches
# and the sizes come from the script itself, so there is no second copy here
FETCHES=`sh $INSTALLSCRIPT linux download --models all --dry-run 2>/dev/null | grep '^FETCH .*vadr-models-' | awk '{ print $2 }'`
if [ "$FETCHES" = "" ]; then echo "FAIL: could not get model URLs from $INSTALLSCRIPT"; exit 1; fi

for url in $FETCHES; do
    lib=`basename $url | sed 's/^vadr-models-//; s/-[0-9][0-9.]*-[0-9]*\.tar\.gz$//'`
    expected=`sed -n "/^model_size ()/,/^}/p" $INSTALLSCRIPT | awk -v m=$lib '$1 == m")" { print $3 }'`
    NCHECKED=$((NCHECKED+1))
    headers=`curl -skIL --retry 3 --retry-delay 5 "$url" | tr -d '\r'`
    status=`echo "$headers" | awk '/^HTTP/ { s = $2 } END { print s }'`
    actual=`echo "$headers" | awk 'tolower($1) == "content-length:" { l = $2 } END { print l }'`
    if [ "$status" != "200" ]; then
        echo "FAIL: $lib: $url returned HTTP status '$status'"; RETVAL=1
    elif [ "$expected" = "" ]; then
        echo "FAIL: $lib: no size in model_size() of $INSTALLSCRIPT"; RETVAL=1
    elif [ "$actual" != "$expected" ]; then
        echo "FAIL: $lib: Content-Length is $actual but model_size() says $expected ($url)"; RETVAL=1
    else
        echo "ok:   $lib $actual bytes"
    fi
done
if [ "$NCHECKED" -ne 8 ]; then echo "FAIL: checked $NCHECKED URLs, expected 8"; RETVAL=1; fi

if [ $RETVAL -eq 0 ]; then echo "Success: all model URLs resolve and all sizes match [do-check-model-sizes-network.sh]"
else echo "FAIL: at least one check failed [do-check-model-sizes-network.sh]"; fi
exit $RETVAL

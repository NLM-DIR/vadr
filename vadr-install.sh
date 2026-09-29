#!/bin/bash
# EPN, Wed Nov 20 06:06:22 2019
#
# vadr-install.sh
# A shell script for downloading and installing VADR and its dependencies.
# 
# usage: 
# to download and build files:
# vadr-install.sh <"linux" or "macosx-silicon" or "macosx-intel">
#
# or to only download files:
# vadr-install.sh <"linux" or "macosx-silicon" or "macosx-intel"> download
#
# or to only build files (after running in 'download' mode):
# vadr-install.sh <"linux" or "macosx-silicon" or "macosx-intel"> build
# 
# to choose which of the model libraries are downloaded (default: all eight),
# add --models followed by a comma-separated list of library names, or 'all' or
# 'none'. Use --list-models to print the library names and their versions:
# vadr-install.sh <"linux" or "macosx-silicon" or "macosx-intel"> --models flu,rsv
# vadr-install.sh --list-models
# 
# for example:
# vadr-install.sh linux
# 
# or
# vadr-install.sh macosx-silicon download
# vadr-install.sh macosx-silicon build
# vadr-install.sh linux download --models flu
# 
# Requirements: a C and C++ compiler, make, perl, curl, unzip and git.
# Installing R2DT, which is used only by 'v-annotate.pl --draw_r2dt',
# additionally requires python3 (see R2DTMINPYTHON below) and network access to
# PyPI. R2DT is the only optional dependency: if it cannot be installed, this
# script warns and installs the rest of VADR.
#
# The following line will make the script fail if any commands fail
set -e

VADRINSTALLDIR=$PWD

# versions
VERSION="1.7.2"
# bio-easel (need this version info here only so we can check out correct easel branch in Bio-Easel/src)
BEVERSION="Bio-Easel-0.18"
# blast+
BVERSION="2.17.0"
# infernal
IVERSION="1.1.5"
# fasta
FVERSION="36.3.8h"
FVERSIONGIT="v36.3.8h_04-May-2020"
FVERSIONGITNOV="36.3.8h_04-May-2020"
# minimap2
MM2VERSIONGIT="v2.30"
MM2VERSIONGITNOV="2.30"
# dependency git tag
VVERSION="vadr-$VERSION"
# vadr models
CALICIVERSION="1.7-2"
FLAVIVERSION="1.7-2"
ZIKAVERSION="1.7.1-2"
CORONAVERSION="1.3-3"
SARSCOV2VERSION="1.6.3-1"
FLUVERSION="1.7-2"
RSVVERSION="1.7-1"
MPXVVERSION="1.4.2-1"
# hmmer (not needed in this release, we can use infernal's hmmer executables)
#HVERSION="3.4"
# R2DT (used only by 'v-annotate.pl --draw_r2dt')
R2DTVERSION="v2.3"
# traveler, the program R2DT uses to render diagrams. This commit is taken from
# R2DT's own base_image/Dockerfile, so it is a property of R2DTVERSION and must
# be updated together with it.
TVERSION="4b4abd25f07b67c677e8ec57eda9b63bcb448e0a"
# jiffy-infernal-hmmer-scripts, also required by R2DT's drawing path, also
# pinned by R2DT's base_image/Dockerfile
JVERSION="31d6c3b826d432a30620507830749cee58e15e68"
# minimum python3 version R2DT's python requirements can be installed on
R2DTMINPYTHON="3.9"

# set defaults
INPUTSYSTEM="?"
DOWNLOADORBUILD="both"
DRYRUN=0
MODELSGIVEN=0
LISTMODELS=0

# the model libraries, in the order they are downloaded, and which of them to
# download. SELECTEDMODELS is all of them unless --models says otherwise.
ALLMODELS="calici flavi zika corona sarscov2 flu rsv mpxv"
SELECTEDMODELS="$ALLMODELS"

# model_version(): echo the version of model library $1, from the pinned
# versions above. This and model_urldir() are the only places that know which
# library has which version and lives in which directory of the FTP site, and
# both --list-models and --models use them, so anything --list-models prints
# is something --models can select.
model_version () {
    case "$1" in
        calici)   echo "$CALICIVERSION" ;;
        flavi)    echo "$FLAVIVERSION" ;;
        zika)     echo "$ZIKAVERSION" ;;
        corona)   echo "$CORONAVERSION" ;;
        sarscov2) echo "$SARSCOV2VERSION" ;;
        flu)      echo "$FLUVERSION" ;;
        rsv)      echo "$RSVVERSION" ;;
        mpxv)     echo "$MPXVVERSION" ;;
    esac
}

# model_urldir(): echo the directory of the FTP site that model library $1 is
# in. Three libraries are in <name>viridae directories, the others in <name>.
model_urldir () {
    case "$1" in
        calici|flavi|corona) echo "${1}viridae" ;;
        *)                   echo "$1" ;;
    esac
}

# model_size(): echo the size in bytes of the tar.gz file of model library $1,
# exactly as the FTP site reports it in Content-Length. It is only displayed by
# --list-models, never used to decide what is fetched. ** These sizes must be
# updated whenever the versions above are. ** testfiles/do-check-model-sizes-network.sh
# compares them to the FTP site and fails if any is out of date; run it as
# part of every release.
model_size () {
    case "$1" in
        calici)   echo 71394880 ;;
        flavi)    echo 219804683 ;;
        zika)     echo 1435731 ;;
        corona)   echo 199367695 ;;
        sarscov2) echo 4282450 ;;
        flu)      echo 39870557 ;;
        rsv)      echo 5484325 ;;
        mpxv)     echo 6462871 ;;
    esac
}

# mb(): echo $1 bytes as a whole number of MB (1 MB = 1048576 bytes), rounded
mb () {
    echo $(( ($1 + 524288) / 1048576 ))
}

# selected_bytes(): echo the total size in bytes of the SELECTEDMODELS
selected_bytes () {
    TOTALBYTES=0
    for v in $SELECTEDMODELS; do
        TOTALBYTES=$(( TOTALBYTES + `model_size $v` ))
    done
    echo $TOTALBYTES
}

# list_models(): print each selected model library, its version and its download
# size, one per line, then the total size. The total is rounded from the total
# number of bytes, so it can differ by 1 MB from the sum of the rounded sizes.
list_models () {
    for v in $SELECTEDMODELS; do
        SZ=`model_size $v`
        printf "%-9s %-9s %4d MB\n" "$v" "`model_version $v`" "`mb $SZ`"
    done
    TOT=`selected_bytes`
    printf "%-9s %-9s %4d MB\n" "total" "" "`mb $TOT`"
}

# parse_models(): set SELECTEDMODELS from the value $1 of --models: 'all', 'none',
# or a comma-separated list of library names. Case does not matter, white
# space around a name is ignored, and a name listed more than once is
# downloaded once. Anything else is an error, so that a mistyped name can
# never quietly install fewer libraries than were asked for. The libraries are
# always downloaded in the order of ALLMODELS, whatever order they were listed in.
parse_models () {
    MODELSARG=`echo "$1" | tr 'A-Z' 'a-z' | tr -d ' \t'`
    case "$MODELSARG" in
        "")
            usage_error "option --models requires a value: 'all', 'none', or a comma-separated list of model libraries ($ALLMODELS)"
            ;;
        all)
            SELECTEDMODELS="$ALLMODELS"
            return
            ;;
        none)
            SELECTEDMODELS=""
            return
            ;;
    esac
    # the trailing comma makes every name, including the last, end in a comma,
    # and turns an empty name (as in 'flu,,rsv' or 'flu,') into an error
    LISTREST="$MODELSARG,"
    LISTGIVEN=","
    while [ "$LISTREST" != "" ]; do
        NAME="${LISTREST%%,*}"
        LISTREST="${LISTREST#*,}"
        case " $ALLMODELS " in
            *" $NAME "*)
                if [ "$NAME" != "" ]; then
                    LISTGIVEN="$LISTGIVEN$NAME,"
                    continue
                fi
                ;;
        esac
        if [ "$NAME" = "all" ] || [ "$NAME" = "none" ]; then
            usage_error "'$NAME' cannot be combined with other names in --models"
        fi
        if [ "$NAME" = "" ]; then
            usage_error "empty entry in --models '$1' (a stray or doubled comma?)"
        fi
        usage_error "unrecognized model library '$NAME' in --models '$1'; the model libraries are: $ALLMODELS"
    done
    SELECTEDMODELS=""
    for v in $ALLMODELS; do
        case "$LISTGIVEN" in
            *",$v,"*) SELECTEDMODELS="$SELECTEDMODELS $v" ;;
        esac
    done
    SELECTEDMODELS="${SELECTEDMODELS# }"
}

# R2DT is the one dependency this script treats as optional: it is used only by
# 'v-annotate.pl --draw_r2dt', it is the only dependency that needs python3 and
# network access to PyPI, and everything else VADR does works without it. If any
# part of the R2DT install fails we report it loudly and finish installing the
# rest of VADR, rather than leaving the user with no VADR at all. R2DTFAILED is
# set to 1 if that happens, so that a warning can be repeated at the very end.
R2DTFAILED=0
R2DTDIR="$VADRINSTALLDIR/R2DT"
R2DTVENVDIR="$VADRINSTALLDIR/r2dt-venv"
R2DTTRAVELERDIR="$VADRINSTALLDIR/traveler"
R2DTJIFFYDIR="$VADRINSTALLDIR/jiffy-infernal-hmmer-scripts"
R2DTLOG="$VADRINSTALLDIR/r2dt-install.log"

# r2dt_failure(): report that the R2DT install did not complete, explain what
# still works and what does not, and make sure nothing is left behind that could
# be mistaken for a working R2DT install. In particular the site config file
# $R2DTDIR/r2dt-vadr-env.sh is only ever written once every step has succeeded,
# so a partial install cannot silently produce empty diagrams.
r2dt_failure () {
    R2DTFAILED=1
    echo ""
    echo "************************************************************"
    echo "WARNING: the R2DT install did not complete."
    echo ""
    echo "Reason: $1"
    echo ""
    echo "The rest of VADR is unaffected and this script will continue."
    echo "Everything except 'v-annotate.pl --draw_r2dt' will work normally."
    echo "R2DT is only used to draw secondary structure diagrams."
    echo ""
    echo "To retry after fixing the problem above, remove these if they exist"
    echo "and rerun this script:"
    echo "  $R2DTDIR"
    echo "  $R2DTVENVDIR"
    echo "  $R2DTTRAVELERDIR"
    echo "  $R2DTJIFFYDIR"
    echo "************************************************************"
    echo ""
    # remove the site config file if a previous run left one: without it,
    # v-annotate.pl --draw_r2dt fails with a clear error instead of running
    # r2dt.py in an environment that cannot work.
    rm -f "$R2DTDIR/r2dt-vadr-env.sh"
}

# r2dt_find_python(): echo the path of a python3 that R2DT's requirements can be
# installed on, or echo nothing if there is none. The user's own python3 is
# preferred when it is new enough, otherwise the newest suitable python3.X on
# PATH is used. Set VADRPYTHON to override this entirely.
r2dt_python_is_new_enough () {
    $1 -c "import sys; sys.exit(0 if sys.version_info[:2] >= tuple(int(x) for x in \"$R2DTMINPYTHON\".split(\".\")) else 1)" > /dev/null 2>&1
}
r2dt_find_python () {
    if [ "$VADRPYTHON" != "" ]; then
        # an explicitly requested interpreter is still checked, so that a stale
        # or wrong VADRPYTHON is reported as such instead of failing later with
        # a less obvious error
        if r2dt_python_is_new_enough "$VADRPYTHON"; then
            echo "$VADRPYTHON"
        fi
        return
    fi
    for p in python3 python3.13 python3.12 python3.11 python3.10 python3.9; do
        if command -v $p > /dev/null 2>&1; then
            if r2dt_python_is_new_enough $p; then
                command -v $p
                return
            fi
        fi
    done
}

# fetch(): download URL $1 to file $2. Every download this script does
# with curl goes through here. --fail makes an HTTP error (a 404, say)
# an error here, rather than the error page being saved as $2 and the
# problem only surfacing later as a failure to unpack it. --retry retries
# only transient failures (timeouts and some 5xx responses), not a 404.
fetch () {
    if [ "$DRYRUN" = "1" ]; then
        echo "FETCH $1 -> $2"
        return 0
    fi
    if ! curl -k -L --fail --retry 3 --retry-delay 5 -o "$2" "$1"; then
        echo "ERROR: failed to download $1" >&2
        exit 1
    fi
}

# extract(): unpack the .zip or .tar.gz archive $1 and remove it. If
# given, $2 is the directory the archive unpacks to and $3 is what it
# is renamed to.
extract () {
    if [ "$DRYRUN" = "1" ]; then
        return 0
    fi
    case "$1" in
        *.zip)
            unzip "$1"
            ;;
        *)
            tar xfz "$1"
            ;;
    esac
    if [ "$#" -eq 3 ]; then
        mv "$2" "$3"
    fi
    rm "$1"
}

# run(): run a command, unless this is a dry run. Used for the steps in the
# download section that act on what fetch() and extract() would have
# downloaded and unpacked, which a dry run does not.
run () {
    if [ "$DRYRUN" = "0" ]; then
        "$@"
    fi
}

# usage(): print the usage message. Called with its output sent to stderr
# when the command line is wrong.
usage () {
    cat << EOF
Usage:
To download and build:
  $0 <"linux" or "macosx-silicon" or "macosx-intel">

or to only download files:
  $0 <"linux" or "macosx-silicon" or "macosx-intel"> download

or to only build the software (after running in download mode):
  $0 <"linux" or "macosx-silicon" or "macosx-intel"> build

To download only some of the model libraries (all eight are downloaded by default):
  $0 <"linux" or "macosx-silicon" or "macosx-intel"> --models <list>
  where <list> is a comma-separated list of library names, for example flu,rsv
  or 'all' or 'none'. --models can be combined with 'download' and can go before
  or after it. It has no effect on 'build'.

Options:
  -h, --help       print this message and exit
  --models <list>  the model libraries to download: 'all' (default), 'none', or a
                   comma-separated list of library names (see --list-models)
  --list-models    print the names, versions and download sizes of the model
                   libraries (only those in --models, if given) and exit
  --dry-run        list the files that would be downloaded, download nothing, and exit

EOF
}

# usage_error(): report an error in the command line, print the usage
# message, and exit
usage_error () {
    echo "ERROR: $1" >&2
    echo "" >&2
    usage >&2
    exit 1
}

# need_value(): for an option that takes a value, given as '--opt value'
# rather than '--opt=value': exit with an error if the option was the last
# argument, so that there is no value to take. Call it as
#   need_value "$OPT" $#
# before taking the value from "$1" and shifting past it.
need_value () {
    if [ "$2" -eq 0 ]; then
        usage_error "option $1 requires a value"
    fi
}

##########################
# Parse the command line
##########################
# The platform ("linux", "macosx-silicon" or "macosx-intel") is required and
# the mode ("download" or "build") is optional. Both are recognized by value,
# so they can be given in either order, and options can come before, between
# or after them. An option that takes a value can be given as '--opt value' or
# '--opt=value'. A bare '--' ends the options: every argument after it is
# treated as a platform or mode.
ENDOFOPTIONS=0
while [ $# -gt 0 ]; do
    ARG="$1"
    shift
    if [ "$ENDOFOPTIONS" = "0" ]; then
        case "$ARG" in
            --)
                ENDOFOPTIONS=1
                continue
                ;;
            -*=*)
                OPT="${ARG%%=*}"
                OPTVALUE="${ARG#*=}"
                OPTHASVALUE=1
                ;;
            -*)
                OPT="$ARG"
                OPTHASVALUE=0
                ;;
            *)
                OPT=""
                ;;
        esac
        if [ "$OPT" != "" ]; then
            case "$OPT" in
                -h|--help)
                    if [ "$OPTHASVALUE" = "1" ]; then
                        usage_error "option $OPT does not take a value"
                    fi
                    usage
                    exit 0
                    ;;
                --dry-run)
                    if [ "$OPTHASVALUE" = "1" ]; then
                        usage_error "option $OPT does not take a value"
                    fi
                    DRYRUN=1
                    ;;
                --list-models)
                    if [ "$OPTHASVALUE" = "1" ]; then
                        usage_error "option $OPT does not take a value"
                    fi
                    LISTMODELS=1
                    ;;
                --models)
                    if [ "$MODELSGIVEN" = "1" ]; then
                        usage_error "option --models given more than once"
                    fi
                    MODELSGIVEN=1
                    if [ "$OPTHASVALUE" = "0" ]; then
                        need_value "$OPT" $#
                        OPTVALUE="$1"
                        shift
                    fi
                    parse_models "$OPTVALUE"
                    ;;
                *)
                    usage_error "unrecognized option: $OPT"
                    ;;
            esac
            continue
        fi
    fi
    case "$ARG" in
        linux|macosx-silicon|macosx-intel)
            if [ "$INPUTSYSTEM" != "?" ]; then
                usage_error "more than one platform given: $INPUTSYSTEM and $ARG"
            fi
            INPUTSYSTEM="$ARG"
            ;;
        download|build)
            if [ "$DOWNLOADORBUILD" != "both" ]; then
                usage_error "more than one of 'download' and 'build' given"
            fi
            DOWNLOADORBUILD="$ARG"
            ;;
        *)
            usage_error "unrecognized argument: $ARG"
            ;;
    esac
done
# --list-models waits until here so that a --models after it is honored
if [ "$LISTMODELS" = "1" ]; then
    list_models
    exit 0
fi
if [ "$INPUTSYSTEM" = "?" ]; then
    usage_error "no platform given"
fi

########################################################
if [ "$DOWNLOADORBUILD" = "both" ]; then 
    echo "------------------------------------------------------------"
    echo "DOWNLOADING AND BUILDING VADR $VERSION"
    echo "------------------------------------------------------------"
fi
if [ "$DOWNLOADORBUILD" = "download" ]; then 
    echo "------------------------------------------------------------"
    echo "DOWNLOADING VADR $VERSION"
    echo "------------------------------------------------------------"
fi
if [ "$DOWNLOADORBUILD" = "build" ]; then 
    echo "------------------------------------------------------------"
    echo "BUILDING VADR $VERSION"
    echo "------------------------------------------------------------"
fi
if [ "$DOWNLOADORBUILD" != "download" ]; then 
    echo ""
    echo "************************************************************"
    echo "IMPORTANT: BEFORE YOU WILL BE ABLE TO RUN VADR SCRIPTS,"
    echo "YOU NEED TO FOLLOW THE INSTRUCTIONS OUTPUT AT THE END"
    echo "OF THIS SCRIPT TO UPDATE YOUR ENVIRONMENT VARIABLES."
    echo "************************************************************"
    echo ""
    echo "Determining current directory ... "
    echo "Set VADRINSTALLDIR as current directory ($VADRINSTALLDIR)."
fi


###########################################
# Download section
###########################################
if [ "$DOWNLOADORBUILD" != "build" ]; then
    echo "------------------------------------------------------------"
    # vadr
    echo "Downloading vadr ... "
    fetch https://github.com/ncbi/vadr/archive/$VVERSION.zip $VVERSION.zip
    extract $VVERSION.zip vadr-$VVERSION vadr
    # for a test build of a release, comment out above fetch and extract and uncomment block below
    # ------------------------------------------------------------
    #git clone https://github.com/ncbi/vadr.git vadr
    #cd vadr
    #git checkout release-$VERSION
    #rm -rf .git
    #cd ..
    # ----------------------------------------------------------------------------
 
    # sequip and Bio-Easel
    for m in sequip Bio-Easel; do 
        echo "Downloading $m ... "
        fetch https://github.com/nawrockie/$m/archive/$VVERSION.zip $m-$VVERSION.zip
        extract $m-$VVERSION.zip $m-$VVERSION $m
    done
    run cd Bio-Easel
    run mkdir src
    (run cd src; fetch https://github.com/EddyRivasLab/easel/archive/$BEVERSION.zip easel-$BEVERSION.zip; extract easel-$BEVERSION.zip easel-$BEVERSION easel; run cd easel; run autoconf)
    run cd ..
    echo "------------------------------------------------------------"


    echo "Downloading Infernal version $IVERSION src distribution"
    fetch http://eddylab.org/infernal/infernal-$IVERSION.tar.gz infernal.tar.gz
    extract infernal.tar.gz
    echo "------------------------------------------------------------"

    # download fasta source distribution from github
    echo "Downloading FASTA version $FVERSIONGIT src distribution"
    fetch https://github.com/wrpearson/fasta36/archive/$FVERSIONGIT.zip $FVERSIONGIT.zip
    extract $FVERSIONGIT.zip fasta36-$FVERSIONGITNOV fasta
    # patch Makefile with vadr specific changes and copy to expected name so 'build' step is linux/osx agnostic
    if [ "$INPUTSYSTEM" = "linux" ]; then
        run patch fasta/make/Makefile.linux vadr/fasta-mods/vadr-fasta-Makefile.linux.patch
        run cp fasta/make/Makefile.linux fasta/make/Makefile.vadr_install
    else 
        run patch fasta/make/Makefile.os_x86_64 vadr/fasta-mods/vadr-fasta-Makefile.os_x86_64.patch
        run cp fasta/make/Makefile.os_x86_64 fasta/make/Makefile.vadr_install
    fi
    # patch defs.h with vadr specific changes
    run patch fasta/src/defs.h vadr/fasta-mods/vadr-fasta-defs.patch
    echo "------------------------------------------------------------"

    # download minimap2 source distribution from github
    echo "Downloading minimap2 version $MM2VERSIONGIT src distribution"
    fetch https://github.com/lh3/minimap2/archive/$MM2VERSIONGIT.zip $MM2VERSIONGIT.zip
    extract $MM2VERSIONGIT.zip minimap2-$MM2VERSIONGITNOV minimap2
    echo "------------------------------------------------------------"
    
    # download blast binaries
    if [ "$INPUTSYSTEM" = "linux" ]; then
        echo "Downloading BLAST version $BVERSION for Linux"
        fetch https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/$BVERSION/ncbi-blast-$BVERSION+-x64-linux.tar.gz blast.tar.gz
    else 
        echo "Downloading BLAST version $BVERSION for Mac/OSX"
        fetch https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/$BVERSION/ncbi-blast-$BVERSION+-x64-macosx.tar.gz blast.tar.gz
    fi
    extract blast.tar.gz ncbi-blast-$BVERSION+ ncbi-blast
    echo "------------------------------------------------------------"

    # download vadr models
    if [ "$SELECTEDMODELS" != "" ]; then
        # a dry run downloads nothing, so say what it would download instead
        MODELMB=$(mb $(selected_bytes))
        if [ "$DRYRUN" = "1" ]; then
            echo "Would download $MODELMB MB of VADR model files."
        else
            echo "Downloading $MODELMB MB of VADR model files ..."
        fi
    fi
    for v in $SELECTEDMODELS; do 
        MVERSION=`model_version $v`
        echo "Downloading VADR $v models ($MVERSION) ... "
        fetch https://ftp.ncbi.nlm.nih.gov/pub/nawrocki/vadr-models/`model_urldir $v`/$MVERSION/vadr-models-$v-$MVERSION.tar.gz vadr-models-$v.tar.gz
        extract vadr-models-$v.tar.gz vadr-models-$v-$MVERSION vadr-models-$v
    done
    if [ "$SELECTEDMODELS" = "" ]; then
        echo "Not downloading any VADR model libraries (--models none)."
    fi
    echo "------------------------------------------------------------"

    if [ "$DRYRUN" = "1" ]; then
        echo "Dry run: stopping before the R2DT download and the build."
        exit 0
    fi

    ###########################################
    # R2DT download (optional dependency)
    ###########################################
    # Everything that needs the network happens here, including installing
    # R2DT's python requirements into a virtual environment, so that a later
    # run in 'build' mode needs a compiler but not a network connection, the
    # same as for every other dependency.
    echo "Downloading R2DT (needed only by 'v-annotate.pl --draw_r2dt') ... "
    echo "  (see $R2DTLOG for the full log of this step)"
    R2DTPYTHON=`r2dt_find_python`
    if [ "$R2DTPYTHON" = "" ]; then
        if [ "$VADRPYTHON" != "" ]; then
            r2dt_failure "VADRPYTHON is set to '$VADRPYTHON', which is not a working python3 of version $R2DTMINPYTHON or later. R2DT's python requirements cannot be installed with it. Set VADRPYTHON to the full path of a newer python3, or unset it to let this script look for one, then rerun this script."
        else
            r2dt_failure "no python3 of version $R2DTMINPYTHON or later was found on your PATH. R2DT's python requirements cannot be installed without one. Install a newer python3, or set the VADRPYTHON environment variable to the full path of one, then rerun this script."
        fi
    else
        echo "  Using python: $R2DTPYTHON (`$R2DTPYTHON --version 2>&1`)"
        # NOTE: the subshell below is deliberately NOT run as the condition of
        # an 'if'. Inside an 'if' condition bash ignores errexit for the whole
        # command, including a 'set -e' the subshell runs itself, so a step
        # failing halfway through would not stop the steps after it. Disabling
        # errexit around a plain subshell and testing $? afterwards does behave
        # as intended.
        set +e
        ( set -e
             exec > "$R2DTLOG" 2>&1
             cd "$VADRINSTALLDIR"
             rm -rf "$R2DTDIR" "$R2DTVENVDIR" "$R2DTTRAVELERDIR" "$R2DTJIFFYDIR"

             echo "== cloning R2DT at $R2DTVERSION =="
             git clone https://github.com/r2dt-bio/R2DT.git R2DT
             (cd R2DT && git checkout $R2DTVERSION)

             echo "== cloning jiffy-infernal-hmmer-scripts at $JVERSION =="
             git clone https://github.com/nawrockie/jiffy-infernal-hmmer-scripts.git jiffy-infernal-hmmer-scripts
             (cd jiffy-infernal-hmmer-scripts && git checkout $JVERSION)
             # R2DT runs these as commands found on PATH, but not all of them
             # are executable in the repository, so make them all executable,
             # exactly as R2DT's own base_image/Dockerfile does. Without this,
             # r2dt.py fails with "Permission denied" on
             # ali-pfam-lowercase-rf-gap-columns.pl and draws nothing.
             chmod +x jiffy-infernal-hmmer-scripts/*.pl

             echo "== cloning traveler at $TVERSION =="
             git clone https://github.com/cusbg/traveler.git traveler
             (cd traveler && git checkout $TVERSION)
             echo "== installing the <bits/stdc++.h> portability shim =="
             mkdir -p traveler/src/include/bits
             cp vadr/traveler-mods/bits-stdcxx-shim.h traveler/src/include/bits/stdc++.h

             echo "== creating python virtual environment =="
             "$R2DTPYTHON" -m venv "$R2DTVENVDIR"
             echo "== installing R2DT python requirements =="
             "$R2DTVENVDIR/bin/python" -m pip install --upgrade pip
             "$R2DTVENVDIR/bin/python" -m pip install -r "$R2DTDIR/requirements-minimal.txt"
             "$R2DTVENVDIR/bin/python" -m pip list
        )
        R2DTSTATUS=$?
        set -e
        if [ $R2DTSTATUS -eq 0 ]; then
            echo "Finished downloading R2DT."
        else
            r2dt_failure "one of the R2DT download steps failed. The last lines of $R2DTLOG were:
`tail -20 "$R2DTLOG" 2>/dev/null`"
        fi
    fi
    echo "------------------------------------------------------------"
fi

if [ "$DRYRUN" = "1" ]; then
    echo "Dry run: nothing is downloaded in build mode."
    exit 0
fi

if [ "$DOWNLOADORBUILD" = "download" ]; then
    echo ""
    echo ""
    echo "********************************************************"
    echo "Downloads finished successfully."
    echo "You will need to build the software before you can use it."
    echo "To do that, run this script in 'build' mode with the command:"
    echo "  $0 <\"linux\" or \"macosx-silicon\" or \"macosx-intel\"> build"
    echo "********************************************************"
    echo ""
fi

###########################################
# Build section
###########################################
if [ "$DOWNLOADORBUILD" != "download" ]; then

    # Build Bio-Easel:
    if [ ! -d Bio-Easel ]; then
        echo ""
        echo "ERROR: Bio-Easel dir does not exist"
        if [ "$DOWNLOADORBUILD" = "build" ]; then
            echo ""
            echo "This may be because you did not yet run this script in download mode from this directory,"
            echo "which is required prior to running in build mode. To do that, execute:"
            echo "  $0 <\"linux\" or \"macosx-silicon\" or \"macosx-intel\"> download"
            echo ""
            exit 1
        fi
        exit 1
    fi
    echo "------------------------------------------------------------"
    echo "Building Bio-Easel ... "
    cd Bio-Easel
    perl Makefile.PL
    make
    make test
    cd ..
    echo "Finished building Bio-Easel."
    echo "------------------------------------------------------------"
    
    # Build infernal:
    if [ ! -d infernal-$IVERSION ]; then
        echo ""
        echo "ERROR: infernal-$IVERSION dir does not exist"
        if [ "$DOWNLOADORBUILD" = "build" ]; then
            echo ""
            echo "This may be because you did not yet run this script in download mode from this directory,"
            echo "which is required prior to running in build mode. To do that, execute:"
            echo "  $0 <\"linux\" or \"macosx-silicon\" or \"macosx-intel\"> download"
            echo ""
            exit 1
        fi
        exit 1
    fi
    echo "------------------------------------------------------------"
    echo "Building Infernal ... "
    mv infernal-$IVERSION infernal
    cd infernal
    mkdir binaries
    sh ./configure --bindir=$PWD/binaries --prefix=$PWD
    make
    make install
    (cd easel/miniapps; make install)
    (cd hmmer; make install)
    cd ..
    echo "Finished building Infernal."
    echo "------------------------------------------------------------"

    # Build FASTA:
    if [ ! -d fasta ]; then
        echo ""
        echo "ERROR: fasta dir does not exist"
        if [ "$DOWNLOADORBUILD" = "build" ]; then
            echo ""
            echo "This may be because you did not yet run this script in download mode from this directory,"
            echo "which is required prior to running in build mode. To do that, execute:"
            echo "  $0 <\"linux\" or \"macosx-silicon\" or \"macosx-intel\"> download"
            echo ""
            exit 1
        fi
        exit 1
    fi
    echo "------------------------------------------------------------"
    echo "Building FASTA ... "
    cd fasta/src
    # note, download step copied either ../make/Makefile.linux_sse2 or ../make/Makefile.os_x86_64 to ../make/Makefile.vadr_install
    make -f ../make/Makefile.vadr_install all
    cd ../../
    echo "Finished building FASTA."
    echo "------------------------------------------------------------"

    # Build minimap2:
    if [ ! -d minimap2 ]; then
        echo ""
        echo "ERROR: minimap2 dir does not exist"
        if [ "$DOWNLOADORBUILD" = "build" ]; then
            echo ""
            echo "This may be because you did not yet run this script in download mode from this directory,"
            echo "which is required prior to running in build mode. To do that, execute:"
            echo "  $0 <\"linux\" or \"macosx-silicon\" or \"macosx-intel\"> download"
            echo ""
            exit 1
        fi
        exit 1
    fi
    echo "------------------------------------------------------------"
    echo "Building minimap2 ... "
    cd minimap2
    if [ "$INPUTSYSTEM" = "macosx-silicon" ]; then
        make arm_neon=1 aarch64=1
    fi
    if [ "$INPUTSYSTEM" != "macosx-silicon" ]; then
        make
    fi
    cd ..
    echo "Finished building minimap2."
    echo "------------------------------------------------------------"

    ###########################################
    # R2DT build (optional dependency)
    ###########################################
    # Nothing here needs the network: the download step already cloned the
    # sources and populated the python virtual environment.
    cd "$VADRINSTALLDIR"
    if [ ! -d "$R2DTDIR" ] || [ ! -d "$R2DTTRAVELERDIR" ] || [ ! -d "$R2DTJIFFYDIR" ] || [ ! -d "$R2DTVENVDIR" ]; then
        r2dt_failure "the R2DT source directories are not all present, so the download step for R2DT either did not run or did not complete."
    else
        echo "------------------------------------------------------------"
        echo "Building traveler (the renderer R2DT uses) ... "
        echo "  (appending to $R2DTLOG)"
        set +e
        ( set -e
             exec >> "$R2DTLOG" 2>&1
             echo "== building traveler =="
             cd "$R2DTTRAVELERDIR/src"
             make build
             test -x "$R2DTTRAVELERDIR/bin/traveler"
             # R2DT locates traveler's utils/ directory (infernal2mapping.py,
             # enrich_json.py, json2svg.py) relative to the traveler executable
             # it finds on PATH, so bin/ and utils/ must stay siblings. They are,
             # because traveler is built in place inside its own checkout.
             test -f "$R2DTTRAVELERDIR/utils/infernal2mapping.py"
        )
        R2DTSTATUS=$?
        set -e
        if [ $R2DTSTATUS -ne 0 ]; then
            r2dt_failure "the traveler build failed. The last lines of $R2DTLOG were:
`tail -20 "$R2DTLOG" 2>/dev/null`"
        else
            echo "Finished building traveler."
            echo "------------------------------------------------------------"
            echo "Writing R2DT site configuration ... "
            # v-annotate.pl --draw_r2dt sources $R2DT_DIR/r2dt-vadr-env.sh, if it
            # exists, immediately before running r2dt.py. Writing it here is what
            # makes --draw_r2dt work with no further configuration by the user.
            # It is written last, and only after every other R2DT step has
            # succeeded, so that a partial install never looks like a working one.
            # It is sourced with POSIX '.', so keep it POSIX compatible.
            cat > "$R2DTDIR/r2dt-vadr-env.sh" << EOF
# Site configuration for 'v-annotate.pl --draw_r2dt', written by vadr-install.sh.
#
# v-annotate.pl --draw_r2dt sources this file with POSIX '.' immediately before
# invoking r2dt.py, so that the environment r2dt.py needs is supplied here
# rather than hardcoded in VADR. If this file is removed, --draw_r2dt will only
# work if 'python \$R2DT_DIR/r2dt.py' already works in the calling environment.
#
# The paths below are expressed relative to \$R2DT_DIR (set by the caller,
# v-annotate.pl dies if it is unset), rather than baked in as the absolute
# paths this installation happened to have. That makes this file -- and so
# the whole install tree -- relocatable: move the tree, re-set R2DT_DIR to
# the new location, and these paths resolve correctly with no edits here.

# The python virtual environment holding R2DT's python requirements is put
# first, so that 'python' resolves to it. The virtual environment is put on PATH
# rather than activated, which keeps this file POSIX compatible: a virtual
# environment python works by virtue of where it sits on PATH.
#
# The remaining directories hold the external programs R2DT calls:
#   Infernal (cmalign, cmbuild, and the esl-* Easel miniapps), the Bio-Easel
#   scripts, the jiffy Infernal/HMMER scripts, and traveler.
export PATH="\${R2DT_DIR}/../r2dt-venv/bin:\${R2DT_DIR}/../infernal/binaries:\${R2DT_DIR}/../Bio-Easel/scripts:\${R2DT_DIR}/../jiffy-infernal-hmmer-scripts:\${R2DT_DIR}/../traveler/bin:\$PATH"

# The Bio-Easel perl modules, needed by the Bio-Easel and jiffy scripts above.
export PERL5LIB="\${R2DT_DIR}/../Bio-Easel/blib/lib:\${R2DT_DIR}/../Bio-Easel/blib/arch:\$PERL5LIB"
EOF
            echo "Wrote $R2DTDIR/r2dt-vadr-env.sh"
            echo "Installing R2DT templates shipped with the zika models (if installed) ... "
            # The zika model package (downloaded above) ships its own R2DT
            # templates under r2dt-templates/, referenced by the R2DT_TEMPLATE
            # lines in its .minfo. Symlink each into R2DT's own template
            # directory so --draw_r2dt finds them with no manual step. A
            # relative symlink (not absolute, not a copy) is used deliberately:
            # relative survives the whole install tree being moved (both
            # endpoints are under $VADRINSTALLDIR), and a symlink -- rather
            # than a copy -- fails loudly (a dangling link) if the model
            # package is later upgraded with revised templates, instead of
            # silently drawing with stale template data.
            # The zika models are one of the libraries --models can leave out. If they
            # are not installed there are no templates to link, and the ln and
            # cp below would fail, stopping the script under 'set -e'.
            if [ -d "$VADRINSTALLDIR/vadr-models-zika" ]; then
                mkdir -p "$R2DTDIR/data/local_data"
                for t in zika-linear zika-circular; do
                    if [ ! -e "$R2DTDIR/data/local_data/$t" ]; then
                        ln -s ../../../vadr-models-zika/r2dt-templates/$t "$R2DTDIR/data/local_data/$t" 2>/dev/null \
                          || cp -r "$VADRINSTALLDIR/vadr-models-zika/r2dt-templates/$t" "$R2DTDIR/data/local_data/$t"
                    fi
                done
            fi
            echo "Finished installing R2DT."
            echo "------------------------------------------------------------"
        fi
    fi

    ###############################################
    # Message about setting environment variables
    ###############################################
    # v-annotate.pl dies at startup unless the directory $VADRMODELDIR names
    # exists, so it must name a model library that is installed. That is
    # calici, unless it was left out with --models (or --models was used in an
    # earlier 'download' run), in which case it is the first installed library
    # in download order. With no libraries at all it is $VADRINSTALLDIR, which
    # exists but holds no models: models are then given to v-annotate.pl with
    # --mdir and --mkey.
    MODELDIRLINE="\$VADRINSTALLDIR"
    MODELDIRNOTE=""
    for v in $ALLMODELS; do
        if [ -d "$VADRINSTALLDIR/vadr-models-$v" ]; then
            MODELDIRLINE="\$VADRINSTALLDIR/vadr-models-$v"
            break
        fi
    done
    if [ "$MODELDIRLINE" = "\$VADRINSTALLDIR" ]; then
        MODELDIRNOTE="No model libraries are installed, so VADRMODELDIR is set to a directory with no models in it. Give v-annotate.pl your models with --mdir and --mkey."
    fi
    echo ""
    echo ""
    echo "********************************************************"
    echo "The final step is to update your environment variables."
    echo "(See https://github.com/ncbi/vadr/blob/$VERSION/documentation/install.md for more information.)"
    echo ""
    echo "If you are using the bash or zsh shell (zsh is default in MacOS/X as"
    echo "of v10.15 (Catalina)), add the following lines to the end of your"
    echo "'.bashrc' or '.zshrc' file in your home directory:"
    echo ""
    echo "export VADRINSTALLDIR=\"$VADRINSTALLDIR\""
    echo "export VADRSCRIPTSDIR=\"\$VADRINSTALLDIR/vadr\""
    echo "export VADRCONFIGFILE=\"\$VADRSCRIPTSDIR/vadr.config\""
    echo "export VADRMODELDIR=\"$MODELDIRLINE\""
    echo "export VADRINFERNALDIR=\"\$VADRINSTALLDIR/infernal/binaries\""
    echo "export VADREASELDIR=\"\$VADRINSTALLDIR/infernal/binaries\""
    echo "export VADRHMMERDIR=\"\$VADRINSTALLDIR/infernal/binaries\""
    echo "export VADRBIOEASELDIR=\"\$VADRINSTALLDIR/Bio-Easel\""
    echo "export VADRSEQUIPDIR=\"\$VADRINSTALLDIR/sequip\""
    echo "export VADRBLASTDIR=\"\$VADRINSTALLDIR/ncbi-blast/bin\""
    echo "export VADRFASTADIR=\"\$VADRINSTALLDIR/fasta/bin\""
    echo "export VADRMINIMAP2DIR=\"\$VADRINSTALLDIR/minimap2\""
    if [ "$R2DTFAILED" = "0" ]; then
        echo "export R2DT_DIR=\"\$VADRINSTALLDIR/R2DT\""
    fi
    echo "export PERL5LIB=\"\$VADRSCRIPTSDIR\":\"\$VADRSEQUIPDIR\":\"\$VADRBIOEASELDIR/blib/lib\":\"\$VADRBIOEASELDIR/blib/arch\":\"\$PERL5LIB\""
    echo "export PATH=\"\$VADRSCRIPTSDIR\":\"\$PATH\""
    echo ""
    echo "After adding the export lines to your .bashrc or .zshrc file, source that file"
    echo "to update your current environment with the command:"
    echo ""
    echo "source ~/.bashrc"
    echo ""
    echo "OR"
    echo ""
    echo "source ~/.zshrc"
    echo ""
    echo "---"
    echo "If you are using the C shell, add the following"
    echo "lines to the end of your '.cshrc' file in your home"
    echo "directory:"
    echo ""
    echo "setenv VADRINSTALLDIR \"$VADRINSTALLDIR\""
    echo "setenv VADRSCRIPTSDIR \"\$VADRINSTALLDIR/vadr\""
    echo "setenv VADRCONFIGFILE \"\$VADRSCRIPTSDIR/vadr.config\""
    echo "setenv VADRMODELDIR \"$MODELDIRLINE\""
    echo "setenv VADRINFERNALDIR \"\$VADRINSTALLDIR/infernal/binaries\""
    echo "setenv VADRHMMERDIR \"\$VADRINSTALLDIR/infernal/binaries\""
    echo "setenv VADREASELDIR \"\$VADRINSTALLDIR/infernal/binaries\""
    echo "setenv VADRBIOEASELDIR \"\$VADRINSTALLDIR/Bio-Easel\""
    echo "setenv VADRSEQUIPDIR \"\$VADRINSTALLDIR/sequip\""
    echo "setenv VADRBLASTDIR \"\$VADRINSTALLDIR/ncbi-blast/bin\""
    echo "setenv VADRFASTADIR \"\$VADRINSTALLDIR/fasta/bin\""
    echo "setenv VADRMINIMAP2DIR \"\$VADRINSTALLDIR/minimap2\""
    if [ "$R2DTFAILED" = "0" ]; then
        echo "setenv R2DT_DIR \"\$VADRINSTALLDIR/R2DT\""
    fi
    echo "setenv PERL5LIB \"\$VADRSCRIPTSDIR\":\"\$VADRSEQUIPDIR\":\"\$VADRBIOEASELDIR/blib/lib\":\"\$VADRBIOEASELDIR/blib/arch\":\"\$PERL5LIB\""
    echo "setenv PATH \"\$VADRSCRIPTSDIR\":\"\$PATH\""
    echo ""
    echo "After adding the setenv lines to your .cshrc file, source that file"
    echo "to update your current environment with the command:"
    echo ""
    echo "source ~/.cshrc"
    echo ""
    echo "(To determine which shell you use, type: 'echo \$SHELL')"
    echo ""
    echo ""
    echo "********************************************************"
    echo ""
    if [ "$MODELDIRNOTE" != "" ]; then
        echo "NOTE: $MODELDIRNOTE"
        echo ""
    fi
    if [ "$R2DTFAILED" = "1" ]; then
        echo "************************************************************"
        echo "WARNING: VADR was installed, but R2DT was NOT."
        echo ""
        echo "'v-annotate.pl --draw_r2dt' will not work. Everything else"
        echo "will. See the warning earlier in this script's output, and"
        echo "$R2DTLOG, for the reason."
        echo "************************************************************"
        echo ""
    fi
fi

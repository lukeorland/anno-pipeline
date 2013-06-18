#!/bin/bash

# This annotates a Gigaword document using Splitta 1.03,
# the Stanford PTB Tokenizer, the UMD parser, and a modified
# Stanford CoreNLP pipeline (including dependencies, coref
# chains, and NER).
#
# ./pipeline FILE DIR [OPTIONS]
#
# where FILE is the input file and DIR is the directory where
# the intermediate files (necessary for the pipeline) and 
# annotated file are saved.
#
# Options are
# --tok      t|f   : perform tokenization (default: t)
# --split    t|f   : perform sentence segmentation (default: t)
# --recase   t|f   : perform true-casing (default: t)
# --nbsp     t|f   : remove non-breaking spaces (default: t)
# --sgml     t|f   : FILE is in SGML format (default: t)
# --parsed   t|f   : input is parsed (default: f)
# --merge    t|f   : merge parses with mark-up
# --end_hack t|f   : use a hack at the end to remove any unwanted 
#                    unicode characters (default: f)
# --doc      t|f   : text has a document structure (default: t)
#                    if f, then coreference resolution is not done
# --qsub     t|f   : parallelize via qsub (default: t)
#
# --sgml f assumes that there is one doc in FILE. If there is 
# more than one doc in FILE and FILE is not in SGML format, set
# --doc f
#
# The final output will be in DIR/FILE.annotated.xml
#
# Courtney Napoles, cdnapoles@gmail.com
# 2012-06-29, ed. 2013-02-28
# edited Frank Ferraro, ferraro@cs.jhu.edu: 2013-06-10

function usage {
    echo "Usage: ./pipeline INPUT_DIR DIR RECASER_HOST [OPTIONS] 

INPUT_DIR is the input directory and DIR is the directory where intermediate
files and the annotated file are saved. Options are
    --tok      t|f   : perform tokenization (default: t)
    --split    t|f   : perform sentence segmentation (default: t)
    --recase   t|f   : perform true-casing (default: t)
    --nbsp     t|f   : remove non-breaking spaces (default: t)
    --sgml     t|f   : FILE is in SGML format (default: t)
    --parsed   t|f   : input is parsed (default: f)
    --merge    t|f   : merge parses with mark-up
    --end_hack t|f   : use a hack at the end to remove any unwanted 
                       unicode characters (default: f)
    --doc      t|f   : text has a document structure (default: t)
                       if f, then coreference resolution is not done
    --qsub     t|f   : parallelize via qsub (default: t)

The final annotation will be saved in DIR/FILE.annotated.xml"
    exit
}

function check_recase_status {
    if ${FLAGS["recase"]} ; then
	if [[ -z "$RECASER_SERVER_UP" ]]; then
	    if [[ -z "$(nc -z ${RECASER_HOST} ${RECASER_PORT})" ]]; then
		echo "Please start RECASER server and set RECASER_PORT and RECASER_HOST appropriately."
		echo "See $RUN_DIR/scripts/start-recaser.sh"
		exit 1
	    fi
	fi
    fi
}

if [ $# -lt 2 ]; then
    usage
fi

RUN_DIR=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)/
: ${real_run=true}
: ${force_rewrite=0}
: ${consistent_flags=true}

: ${RECASER_PORT=5698}
: ${RECASER_THREADS=4}
: ${TIMESTAMP=$(date +%Y%m%d-%H%M%S)}
: ${sym_link_okay=1}
: ${DIR_TO_SINGLE_FILE="perl ${RUN_DIR}/scripts/raw_text_to_agiga_input.pl"}
: ${CONVERT_INPUT=false}
: ${RECASER_SCRIPT="${RUN_DIR}/scripts/recase.sh"}
RECASER_SCRIPT="$(readlink -f $RECASER_SCRIPT)"


: ${MAIL_OPTIONS=""}
: ${Q_SHELL="-S /bin/bash "}


INPUT=$(readlink -f "$1")
if [[ ! -d "$INPUT" ]] && [[ ! -e "$INPUT" ]]; then
    echo "input \"$1\" doesn't exist"
    echo "$INPUT"
    exit 1
fi
shift

wrkdir=$1/${TIMESTAMP}
shift
RECASER_HOST=
if [[ "${1:0:2}" = "--" ]]; then #RECASER_HOST not set
    recaser_set=false
else
    recaser_set=true
    RECASER_HOST="$1"
    shift
fi

#file prefix
f=''
#next stage depends on this suffix
suffix=''

export LC_ALL=en_US.UTF-8
export PYTHONPATH=$PYTHONPATH:${RUN_DIR}/lib/splitta.1.03 
export PERL5LIB=$PERL5LIB:${RUN_DIR}/lib/perl5:${RUN_DIR}/lib/perl5/site_perl:${RUN_DIR}/lib/perl5/site_perl/5.16.0/x86_64-linux-thread-multi-ld/ 



USE_QSUB=true

# pipeline RESOURCE settings
: ${PARSE_HEAP="16G"}
: ${PARSE_SS="10m"}
: ${PARSE_WORKERS=8}
: ${TOKENIZER_HEAP="100m"}
: ${ANNOTATE_HEAP="16G"}

STEPS=("split" "tok" "sgml" "nbsp" "recase" "parse" "merge" "annotate" "end_hack")
#defaults, in case someone forgets to add variables
: ${NUM_PROC_=1}
: ${MEM_FREE_="4G"}
: ${H_RT_="1:00:00"}

#pre-made step resource limits
: ${NUM_PROC_split=1}
: ${MEM_FREE_split="2G"}
: ${H_RT_split="1:00:00"}

: ${NUM_PROC_tok=1}
: ${MEM_FREE_tok="2G"}
: ${H_RT_tok="1:00:00"}

: ${NUM_PROC_sgml=1}
: ${MEM_FREE_sgml="500M"}
: ${H_RT_sgml="1:00:00"}

: ${NUM_PROC_nbsp=1}
: ${MEM_FREE_nbsp="4G"}
: ${H_RT_nbsp="1:00:00"}

: ${NUM_PROC_recase=1}
: ${MEM_FREE_recase="4G"}
: ${H_RT_recase="1:00:00"}

: ${NUM_PROC_parse=${PARSE_WORKERS}}
: ${MEM_FREE_parse="30G"}
: ${H_RT_parse="8:00:00"}

if [[ ! "$NUM_PROC_parse" -eq "${PARSE_WORKERS}" ]]; then
    echo "number of parse workers must = number of parse processors"
    echo "exiting..."
    exit 1
fi
    
: ${NUM_PROC_merge=1}
: ${MEM_FREE_merge="2G"}
: ${H_RT_merge="1:00:00"}

: ${NUM_PROC_annotate=8}
: ${MEM_FREE_annotate="30G"}
: ${H_RT_annotate="12:00:00"}

: ${NUM_PROC_end_hack=1}
: ${MEM_FREE_end_hack="1G"}
: ${H_RT_end_hack="1:00:00"}

declare -A STEP_ORDER
declare -A FLAGS
i=0
for step in "${STEPS[@]}"; do
    STEP_ORDER["${step}"]=$i
    FLAGS["${step}"]=true
    i=$(($i+1))
done
FLAGS["end_hack"]=false
doc=true
anno_flags=""

while true; do
    case "$1" in
	--tok) 
	    case "$2" in
		t) FLAGS["tok"]=true ; shift 2 ;;
		f) FLAGS["tok"]=false ; shift 2 ;;
		*) usage ;;
		esac ;;
	--split)
	    case "$2" in
		t) FLAGS["split"]=true ; shift 2 ;;
		f) FLAGS["split"]=false ; shift 2 ;;
		*) usage ;;
		esac ;;
	--recase)
	    case "$2" in
		t) FLAGS["recase"]=true ; shift 2 ;;
		f) FLAGS["recase"]=false ; shift 2 ;;
		*) usage ;;
		esac ;;
	--nbsp)
	    case "$2" in
		t) FLAGS["nbsp"]=true ; shift 2 ;;
		f) FLAGS["nbsp"]=false ; shift 2 ;;
		*) usage ;;
		esac ;;
	--sgml)
	    case "$2" in
		t) FLAGS["sgml"]=true ; shift 2 ;;
		f) FLAGS["sgml"]=false ; shift 2 ;;
		*) usage ;;
		esac ;;
	--merge)
	    case "$2" in
		t) FLAGS["merge"]=true ; shift 2 ;;
		f) FLAGS["merge"]=false ; shift 2 ;;
		*) usage ;;
		esac ;;
	--annotate)
	    case "$2" in
		t) FLAGS["annotate"]=true ; shift 2 ;;
		f) FLAGS["annotate"]=false ; shift 2 ;;
		*) usage ;;
		esac ;;
	--parsed)
	    case "$2" in
		t) FLAGS["parse"]=false ; shift 2 ;;
		f) FLAGS["parse"]=true ; shift 2 ;;
		*) usage ;;
		esac ;;
	--doc)
	    case "$2" in
		t) doc=true ; shift 2 ;;
		f) doc=false ; shift 2 ;;
		*) usage ;;
		esac ;;
	--qsub)
	    case "$2" in
		t) USE_QSUB=true ; shift 2 ;;
		f) USE_QSUB=false ; shift 2 ;;
		*) usage ;;
		esac ;;
	--end_hack)
	    case "$2" in
		t) FLAGS["end_hack"]=true ; shift 2 ;;
		f) FLAGS["end_hack"]=false ; shift 2 ;;
		*) usage ;;
		esac ;;
	--) shift ; break ;;
	-h|--help) usage ;;
	--*) echo "$1: illegal option"; usage ;;
	*) break ;;
    esac
done

if $consistent_flags ; then
    if ${FLAGS["sgml"]} && ${FLAGS["tok"]} ; then
	FLAGS["nbsp"]=true
    else
	FLAGS["nbsp"]=false
    fi

    if ${FLAGS["sgml"]} && ${FLAGS["parse"]} ; then
	FLAGS["merge"]=true
    else
	FLAGS["merge"]=false
    fi
fi

if ! ${FLAGS["sgml"]} ; then
    anno_flags="$anno_flags --sgml f"
fi

if ! $doc ; then
    if ! ${FLAGS["sgml"]} ; then
	anno_flags="$anno_flags --sents t"
    else
	anno_flags="$anno_flags --coref f"
    fi
fi

if ! $recaser_set && ${FLAGS["recase"]} ; then
    echo "You want to recase, but recaser host isn't set."
    usage
fi

check_recase_status
if [[ ! -e "${RECASER_SCRIPT}" ]] && ${FLAGS["recase"]} ; then
    echo "We want to true case the text, but can't find the script!"
    echo "We're looking here:"
    echo "$RECASER_SCRIPT"
    exit 1
fi

if [ ! -d "$wrkdir" ]; then
    mkdir "$wrkdir"
fi

function run_ncmd {
    cmd="$3 $2"
    if $real_run ; then
	eval $cmd
    fi
}

Q_DEPENDENCIES=""

function run_qcmd {
    np="NUM_PROC"_$1
    mf="MEM_FREE"_$1
    hrt="H_RT"_$1
    resources="num_proc=${!np},mem_free=${!mf},h_rt=${!hrt}"
    olog="-j y -o $wrkdir/$1.log"
    qname=annotate-$step-$TIMESTAMP
    cmd=''
    vlist=
    if [[ ! -z "$3" ]]; then
	vlist="-v ${3// /,}"
    fi
    if [[ -z $Q_DEPENDENCIES ]]; then
	cmd="qsub -N $qname -l $resources ${MAIL_OPTIONS} $Q_SHELL $olog -cwd -b y $vlist -V \"$2\""
    else
	cmd="qsub -N $qname -hold_jid $Q_DEPENDENCIES -l $resources ${MAIL_OPTIONS} $Q_SHELL $olog -cwd -b y $vlist -V \"$2\""
    fi
    echo "$cmd"
    if $real_run ; then
	eval "$cmd"
    fi
    if [[ -z $Q_DEPENDENCIES ]]; then
	Q_DEPENDENCIES=$qname
    else
	Q_DEPENDENCIES=$Q_DEPENDENCIES,$qname
    fi
    qname=""

}

cat <<EOF 1>&2

Working Timestamp: $TIMESTAMP
Output Directory:  $wrkdir

EOF

f=to_anno.${TIMESTAMP}
#put this control structure before above loop
# 0. make sure everything's in a single file
if [[ ! -e $wrkdir/$f.single_file ]] || [[ $force_rewrite -eq 1 ]]; then
    if [[ -d ${INPUT} ]] || $CONVERT_INPUT ; then #we're dealing with a directory
	cmd="$DIR_TO_SINGLE_FILE $(find "$INPUT" -type f) > $wrkdir/$f.single_file"
	echo $cmd
	eval $cmd
    else #dealing with a file
	f=`basename $INPUT`
	f=${f%.*}
	if [[ $sym_link_okay ]]; then
	    ln -s ${INPUT} $wrkdir/$f.single_file
	else
	    cp ${INPUT} $wrkdir/$f.single_file
	fi
    fi
else
    echo "Single file already exists, or force_rewrite = 0" 1>&2
fi

declare -A CMDS
declare -A ARGS
#declare -A NEEDED
# 1. Concatenate lines of text and split into sentences
#NEEDED["split"]=( "$wrkdir/$f.single_file" )
CMDS["split"]="${RUN_DIR}/scripts/scat $wrkdir/$f.single_file | \
	python ${RUN_DIR}/scripts/split_sentences.py > $wrkdir/$f.split"
# 2. Tokenize sentences
#NEEDED["tok"]=( "$wrkdir/$f.split" )
CMDS["tok"]="java -mx${TOKENIZER_HEAP} -cp ${RUN_DIR}/lib/stanford-corenlp-2012-05-22.jar \
	edu.stanford.nlp.process.PTBTokenizer -options ptb3Escaping \
        -preserveLines $wrkdir/$f.split > $wrkdir/$f.tok"
# 3. Separate SGML markup from tokenized lines (necessary because the 
#    parser does not skip markup).
#NEEDED["sgml"]=( "$wrkdir/$f.tok" )
CMDS["sgml"]="cat $wrkdir/$f.tok | python ${RUN_DIR}/scripts/separate_lines.py \
	$wrkdir/$f.markup > $wrkdir/$f.to_parse"
# 3a. Replace non-breaking spaces introduced by the PTB tokenizer in 
#     lines containing SGML markup.
#NEEDED["nbsp"]=( "$wrkdir/$f.markup" )
CMDS["nbsp"]="perl -p -ibak -e 's/\x{c2}\x{a0}/ /g;' $wrkdir/$f.markup"
# 3b. Recase
#NEEDED["recase"]=( "$wrkdir/$f.to_parse" )
ARGS["recase"]="RECASER_HOST=${RECASER_HOST} RECASER_PORT=${RECASER_PORT}"
CMDS["recase"]="${RECASER_SCRIPT} $wrkdir/$f.to_parse > $wrkdir/$f.recased"
# 4. Parse
parse_input_suffix=
if ${FLAGS["recase"]} ; then
    parse_input_suffix="recased"
else
    parse_input_suffix="markup"
fi
#NEEDED["parse"]=( "$wrkdir/$f.$parse_input_suffix" )
CMDS["parse"]="java -Xmx${PARSE_HEAP} -ss${PARSE_SS} -cp ${RUN_DIR}/lib/umd-parser.jar \
	edu.purdue.ece.speech.LAPCFG.PurdueParser -gr ${RUN_DIR}/lib/wsj-6.pml \
        -input $wrkdir/$f.$parse_input_suffix -output $wrkdir/$f.parse -jobs ${PARSE_WORKERS}"
# 5. Merge markup and parses into one file and make legal XML (by adding a root
#    node and escaping <>&.
#NEEDED["merge"]=( "$wrkdir/$f.markup" "$wrkdir/$f.parse" )
CMDS["merge"]="perl ${RUN_DIR}/scripts/merge_file.pl $wrkdir/$f.parse $wrkdir/$f.markup \
	> $wrkdir/$f.merged"
# 6. Annotate file with modified Stanford pipeline and convert to true XML
#    This assumes that the file will be structured as <FILE><DOC><TEXT>parsed 
#    lines</TEXT></DOC></FILE>. For more options see 
#    edu.jhu.annotation.GigawordAnnotator
#NEEDED["annotate"]=( "$wrkdir/$f.merged" )
CMDS["annotate"]="java -Xmx${ANNOTATE_HEAP} -Dfile.encoding=UTF-8 -cp ${RUN_DIR}/bin:${RUN_DIR}/lib/stanford-corenlp-2012-05-22.jar:${RUN_DIR}/lib/my-xom.jar:${RUN_DIR}/lib/stanford-corenlp-2012-05-22-models.jar:${RUN_DIR}/lib/joda-time.jar \
    edu.jhu.annotation.GigawordAnnotator --in $wrkdir/$f.merged $anno_flags > $wrkdir/$f.annotated.xml 2>> $wrkdir/$f.errors"
# This is a bad hack that you need if illegal UTF8 characters are present
# in the output. This line will delete those characters. You should not do 
# this without examining what characters will be deleted.
CMDS["end_hack"]="cat $wrkdir/$f.intermed | iconv -t UTF8//IGNORE > $wrkdir/$f.xml"


#set the appropriate function pointer
runner=
if $USE_QSUB ; then
    runner=run_qcmd
else
    runner=run_ncmd
fi

prev_step=
for step in "${STEPS[@]}"; do
    echo -e "STEP $step (${FLAGS[$step]})"
    if ${FLAGS[$step]} ; then
	$runner "$step" "${CMDS[$step]}" "${ARGS[$step]}"
	echo -e "\n==========================\n"
    fi
    prev_step=$step
done
exit

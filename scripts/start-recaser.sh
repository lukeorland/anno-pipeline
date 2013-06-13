#!/bin/bash

: ${RECASER_THREADS=1}
: ${RECASER_PORT=5698}

set -o nounset

echo "using recaser from $RECASER"
echo "with run command $RECASER_RUN"

rcmd="$RECASER_RUN -server-port ${RECASER_PORT} -threads $RECASER_THREADS "
export RECASER_SERVER_UP="$(hostname):${RECASER_PORT}"
echo $RECASER_SERVER_UP
echo $rcmd
eval "$rcmd"



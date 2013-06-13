#!/bin/bash

: ${RECASER_PORT=9001}
: ${RECASER_HOST=$(hostname)}

IN_FILE=$(readlink -f "$1")

if [[ ! -e "$IN_FILE" ]]; then
    echo "input file \"$1\" doesn't exist"
    exit 1
fi

if [[ -z "$RECASER_SERVER_UP" ]]; then
    if [[ -z "$(nc -z ${RECASER_HOST} ${RECASER_PORT})" ]]; then
	echo "Please start RECASER server"
	exit 1
    fi
fi

function recase {
    echo "$1" | nc ${RECASER_HOST} ${RECASER_PORT}
}

docid=''
indoc=0
inp=0
para=''
while read -r line
do
    recase "$line"
done < "$IN_FILE"


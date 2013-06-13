#!/bin/bash

# This script will take a parsed file in Gigaword SGML format and 
# run it through the modified Stanford Core NLP pipeline

RUN_DIR=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)/

java -Xmx16g -Dfile.encoding=UTF-8 -cp ${RUN_DIR}/bin:${RUN_DIR}/lib/stanford-corenlp-2012-05-22.jar:${RUN_DIR}/lib/my-xom.jar:${RUN_DIR}/lib/stanford-corenlp-2012-05-22-models.jar:${RUN_DIR}/lib/joda-time.jar edu.jhu.annotation.GigawordAnnotator --in $@

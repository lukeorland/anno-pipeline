#!/usr/bin/python

# This script assumes that the input is not formatted with 
# one sentence per line. It skips suspected SGML markup (any
# line beginning with '<'). All other lines not separated 
# by an extra line break are concatenated and then split 
# with Splitta 1.03 by default, or use the command line argurment --nltk to use
# the NLTK English sentence splitter.
#
# cat sample.xml | python split_sentences.py
#
# Courtney Napoles, cdnapoles@gmail.com
# 2012-06-29

import sys, os

if len(sys.argv) > 1 and sys.argv[1] == '--nltk':
    import nltk_english_sentence_splitter
    splitter = 'NLTK'
else:
    import sbd
    splitter = 'Splitta'
    model_path = os.path.dirname(sbd.__file__)+'/model_svm/'
    model = sbd.load_sbd_model(model_path,True)


def split(lines) :
    if len(lines) > 0 :
        text = ' '.join(lines)
        if splitter is 'Splitta':
            test = sbd.get_text_data(text, tokenize=True)
            test.featurize(model)
            model.classify(test)
            split_sentences = test.segment(use_preds=True,list_only=True)
            # Splitta will drop the last sentence, apparently at random.
            # We will look for dropped sentences by offset and append them
            # to the split sentence ist. Recursively re-splitting missed 
            # sentences does not work because Splitta still will not 
            # recognize the dropped sentences
            new_length = len(' '.join(split_sentences))
            old_length = len(' '.join(lines))
            if new_length != old_length :
                split_sentences.append(' '.join(lines)[new_length:])
                sys.stderr.write('SBD ERROR\t'+' '.join(lines)+'\n')
        else:
            # Use NLTK to split sentences.
            split_sentences = nltk_english_sentence_splitter.split_sentences(text)

        for s in split_sentences:
            print s

lines = []
for line in sys.stdin :
    line = line.strip()
    # skip XML markup (lines starting with <)
    if line.startswith('<') :
        split(lines)
        lines = []
        print line.rstrip()
    else :
        # add this line to the text to be segmented
        if len(line) > 0 :
            lines.append(' '.join(line.split())) # join/split needed to normalize spacing
        else :
            print line # keep empty lines
if len(lines) > 0 : 
    split(lines)

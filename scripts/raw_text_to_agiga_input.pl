#!/usr/bin/perl -w
use strict;

# raw_text_to_agiga_input.pl
# author: Jonny Weese <jonny@cs.jhu.edu>
# edited: Frank Ferraro <ferraro@cs.jhu.edu>: 2013-06-10
#         removed FILE tags
#
# This script takes files listed on the command line, and prints their contents
# to stdout, surrounded by the following XML:
#
# <FILE name="filename">
# <DOC id="filename">
# <TEXT>
# [ ... contents of filename ... ]
# </TEXT>
# </DOC>
# </FILE>
#
# If multiple files are listed, each will be surrounded by the appropriate
# FILE tags.

foreach (@ARGV) {
	open CURR, "<$_" or die "$!";
	#print "<FILE name=\"$_\">\n";
	print "<DOC id=\"$_\">\n";
	print "<TEXT>\n";
	while (<CURR>) {
		print;
	}
	print "</TEXT>\n";
	print "</DOC>\n";
	#print "</FILE>\n";
	close CURR;
}

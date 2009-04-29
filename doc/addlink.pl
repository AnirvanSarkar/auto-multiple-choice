#! /usr/bin/perl

use File::Copy;

my $f=$ARGV[0];

if($f) {
    $fb=$f.'~';
    copy($f,$fb);
    open(ANCIEN,$fb);
    open(NOUVEAU,">$f");

    while(<ANCIEN>) {
	if(/\\DBKsubtitle/) {
	    s+\}$+ \\href{http://home.gna.org/auto-qcm/}{http://home.gna.org/auto-qcm/}}+;
	}
	print NOUVEAU;
    }

    close(ANCIEN);
    close(NOUVEAU);
}

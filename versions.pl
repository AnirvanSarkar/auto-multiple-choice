#! /usr/bin/perl

my %k=();

$s=`svnversion`;
if($s =~ /([0-9]+)[SM]*$/) {
    $k{'svn'}=1+$1;
}

open(CHL,"debian/changelog");
LINES: while(<CHL>) {
    if(/^[^\s]+ \(([0-9:.-]+)\)/) {
	$k{'deb'}=$1;
	last LINES;
    }
}

while(<>) {
    for my $i (keys %k) {
	s/\$$i\$/$k{$i}/g;
    }
    print;
}

    

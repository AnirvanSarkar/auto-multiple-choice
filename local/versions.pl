#! /usr/bin/perl

use Data::Dumper;

my %k=();

$s=`svnversion`;
if($s =~ /([0-9]+)[SM]*$/) {
    $k{'svn'}=$1;
}

open(CHL,"debian/changelog");
LINES: while(<CHL>) {
    if(/^[^\s]+ \(([0-9:.-]+)\)/) {
	$k{'deb'}=$1;
	last LINES;
    }
}

$d = Data::Dumper->new([\%k], ['k']); 

open(VPL,">nv.pl");
print VPL $d->Dump;
close(VPL);

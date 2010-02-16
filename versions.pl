#! /usr/bin/perl

do 'nv.pl';

while(<>) {
    for my $i (keys %$k) {
	s/\$$i\$/$k->{$i}/g;
    }
    print;
}

    

#! /usr/bin/perl

use Getopt::Long;
use XML::XPath;
use XML::XPath::XMLParser;
use Encode;

my $liste='';

GetOptions("liste=s"=>\$liste,
	   );

my @fichiers=@ARGV;

open(LOG,">$liste") if($liste);

for my $f (@fichiers) {

    print "*** Fichier $f\n";

    my $xp = XML::XPath->new(filename => $f);

    my $nodeset = $xp->find('//programlisting');

    foreach my $node ($nodeset->get_nodelist) {

	my $id=$node->getAttribute('id');
	my $ex=$node->string_value;

	if($id =~ /^(exemples)-(.*\.tex)$/) {
	    my $fich="$1/$2";
	    print "  * extrait $fich\n";
	    print LOG "$fich\n" if($liste);

	    open(EXT,">:encoding(iso-8859-1)",$fich) or die "Impossible d'ecrire dans $fich : $!";
	    print EXT $ex;
	    close EXT;
	}
    }
    
}

close(LOG) if($liste);



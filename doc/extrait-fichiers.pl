#! /usr/bin/perl
#
# Copyright (C) 2008-2010 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# Auto-Multiple-Choice is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Auto-Multiple-Choice.  If not, see
# <http://www.gnu.org/licenses/>.

use Getopt::Long;
use XML::XPath;
use XML::XPath::Node;
use XML::XPath::XMLParser;
use Encode;
use Archive::Tar;

my $liste='';

GetOptions("liste=s"=>\$liste,
	   );

my @fichiers=@ARGV;

open(LOG,">$liste") if($liste);

for my $f (@fichiers) {

    print "*** File $f\n";

    my $xp = XML::XPath->new(filename => $f);
    
    my $lang='';
    my @articles= $xp->find('/article')->get_nodelist;
    if($articles[0] && $articles[0]->getAttribute('lang')) {
	$lang=$articles[0]->getAttribute('lang');
	$lang =~ s/-.*//;
	print "  I lang=$lang\n";
    }

    my $nodeset = $xp->find('//programlisting');

    foreach my $node ($nodeset->get_nodelist) {

	my $id=$node->getAttribute('id');
	my $ex=$node->string_value;

	if($id =~ /^(exemples)-(.*\.tex)$/) {

	    my $rep=$1;
	    $rep.="/$lang" if($lang);
	    my $name=$2;
	    $name =~ s/\.tex$//;
	    my $code_name=$name;

	    print "  * extracting $rep/$code_name\n";

	    my $desc='Doc / sample LaTeX file';

	    my $parent=$node->getParentNode();
	    foreach my $fr ($parent->getChildNodes()) {
		if($fr->getNodeType() == COMMENT_NODE) {
		    my $c=$fr->toString();
		    if($c =~ /^<!--\s*NAME:\s*(.*)\n\s*DESC:\s*((?:.|\n)*)-->$/) {
			$name=$1;
			$desc=$2;
			print "    embedded description\n";
		    }
		}
	    }

	    my $tar = Archive::Tar->new;

	    $tar->add_data("$code_name.tex",encode_utf8($ex));
	    $tar->add_data("description.xml",
			   encode_utf8('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<description>
  <title>'.$name.'</title>
  <text>'.$desc.'</text>
</description>
')
			   );
	    $tar->add_data("options.xml",
			   encode_utf8('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<projetAMC>
  <texsrc>%PROJET/'.$code_name.'.tex</texsrc>
  <moteur_latex_b>pdflatex</moteur_latex_b>
</projetAMC>
'));

	    $tar->write("$rep/$code_name.tgz", COMPRESS_GZIP);

	    print LOG "$rep/$code_name.tgz\n" if($liste);

	}
    }
    
}

close(LOG) if($liste);



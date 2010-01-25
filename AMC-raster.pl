#! /usr/bin/perl -w
#
# Copyright (C) 2010 Alexis Bienvenue <paamc@passoire.fr>
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
use File::Temp;
use File::Copy;

my $moteur='auto';
my $page=1;
my $dpi=300;

GetOptions('moteur=s'=>\$moteur,
	   'page=s'=>\$page,
	   'dpi=s'=>\$dpi,
	   );

die "Mauvais nombre d'arguments" if($#ARGV!=1);

my ($pdf,$ppm)=@ARGV;

if($moteur eq 'auto') {
    $moteur='';
    open(INFO,"-|","pdfinfo","-meta",$pdf);
    while(<INFO>) {
	# imagemagick ne garde pas les bonnes couleurs pour un pdf xetex...
	$moteur='pdftoppm' if(/^Creator:.*xetex/i);
	$moteur='pdftoppm' if(/^Creator:.*dvips/i);
    }
    close(INFO);
    $moteur='im' if(!$moteur);
    print "Moteur utilise : $moteur\n";
}

if($moteur eq 'im') {
    exec("convert",
	 "-density",$dpi,
	 "-depth",8,
	 "+antialias",
	 $pdf.'['.($page-1).']',$ppm);
} elsif($moteur eq 'gm') {
    exec("gm","convert",
	 "-density",$dpi,
	 "-depth",8,
	 "+antialias",
	 $pdf.'['.($page-1).']',$ppm);
} elsif($moteur eq 'gs') {
    exec("gs","-sDEVICE=ppmraw","-dNOPAUSE","-dBATCH","-q","-o",$ppm,"-r".$dpi."x".$dpi,"-dFirstPage=$page","-dLastPage=$page",$pdf);
} elsif($moteur eq 'pdftoppm') {
    my $fh = File::Temp->new();
    system("pdftoppm","-f",$page,"-l",$page,
	   "-r",$dpi,
	   "-aa","no","-aaVector","no",
	   $pdf,$fh->filename);
    my $p=sprintf("%s-%06d.ppm",$fh->filename,$page);
    move($p,$ppm);
} else {
    die "Moteur non repertorie : $moteur";
}

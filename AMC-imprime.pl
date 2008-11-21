#! /usr/bin/perl
#
# Copyright (C) 2008 Alexis Bienvenue <paamc@passoire.fr>
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
use File::Temp qw/ tempfile tempdir /;

use AMC::MEPList;
use AMC::Gui::Avancement;

my $cmd_pid='';

sub catch_signal {
    my $signame = shift;
    print "*** AMC-calepage : signal $signame, je tue $cmd_pid...\n";
    kill 9,$cmd_pid if($cmd_pid);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

my $mep_dir="";
my $sujet='';
my $print_cmd='cupsdoprint %f';
my $progress='';

GetOptions(
	   "mep=s"=>\$mep_dir,
	   "sujet=s"=>\$sujet,
	   "progression=s"=>\$progress,
	   "print-command=s"=>\$print_cmd,
	   );

die "Repertoire MEP non specifie" if(!$mep_dir);
die "Fichier sujet non specifie" if(!$sujet);
die "Commande impression non specifiee" if(!$print_cmd);

my $avance=AMC::Gui::Avancement::new($progress);

$avance->init();

my $mep=AMC::MEPList::new($mep_dir);

my @es=$mep->etus();
my $n=0;


for my $e (@es) {
    my $debut=10000;
    my $fin=0;
    for ($mep->pages_etudiant($e)) {
	$debut=$_ if($_<$debut);
	$fin=$_ if($_>$fin);
    }
    $n++;
    
    $tmp = File::Temp->new( UNLINK => 1, SUFFIX => '.pdf' );
    $fn=$tmp->filename();

    print "Etudiant $e : pages $debut-$fin dans le fichier $fn...\n";

    $cmd_pid=system("pdftk",$sujet,
		    "cat","$debut-$fin",
		    "output",$fn);
    $avance->progres_abs((2*$n-1)/(2*(1+$#es)));

    my @c=map { s/[%]f/$fn/g;$_; } split(/\s+/,$print_cmd);
    #print STDERR join(' ',@c)."\n";
    $cmd_pid=system(@c);

    close($tmp);

    $avance->progres_abs($n/(1+$#es));
}

$avance->fin();



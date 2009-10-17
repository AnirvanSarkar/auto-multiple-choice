#! /usr/bin/perl
#
# Copyright (C) 2008-2009 Alexis Bienvenue <paamc@passoire.fr>
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

use Net::CUPS;
use Net::CUPS::PPD;

use AMC::Basic;
use AMC::MEPList;
use AMC::Gui::Avancement;

my $cmd_pid='';

sub catch_signal {
    my $signame = shift;
    debug "*** AMC-imprime : signal $signame, je tue $cmd_pid...\n";
    kill 9,$cmd_pid if($cmd_pid);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

my $mep_dir="";
my $sujet='';
my $print_cmd='cupsdoprint %f';
my $progress='';
my $progress_id='';
my $debug='';
my $fich_nums='';
my $methode='CUPS';
my $imprimante='';
my $options='number-up=1';

GetOptions(
	   "mep=s"=>\$mep_dir,
	   "sujet=s"=>\$sujet,
	   "fich-numeros=s"=>\$fich_nums,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "print-command=s"=>\$print_cmd,
	   "methode=s"=>\$methode,
	   "imprimante=s"=>\$imprimante,
	   "options=s"=>\$options,
	   "debug=s"=>\$debug,
	   );

set_debug($debug);

die "Repertoire MEP non specifie" if(!$mep_dir);
die "Fichier sujet non specifie" if(!$sujet);
die "Commande impression non specifiee" if(!$print_cmd);

sub commande_externe {
    my @c=@_;

    debug "Commande : ".join(' ',@c);

    $cmd_pid=fork();
    if($cmd_pid) {
	waitpid($cmd_pid,0);
    } else {
	exec(@c);
    }

}

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $mep=AMC::MEPList::new($mep_dir);

my @es;

if($fich_nums) {
    open(NUMS,$fich_nums);
    while(<NUMS>) {
	push @es,$1 if(/^([0-9]+)$/);
    }
    close(NUMS);
} else {
    @es=$mep->etus();
}


my $n=0;
my $cups;
my $dest;

if($methode =~ /^cups/i) {
    $cups=Net::CUPS->new();
    $dest=$cups->getDestination($imprimante);
    die "Imprimante inaccessible : $imprimante" if(!$dest);
    for my $o (split(/\s*,+\s*/,$options)) {
	my $on=$o;
	my $ov=1;
	if($o =~ /([^=]+)=(.*)/) {
	    $on=$1;
	    $ov=$2;
	}
	debug "Option : $on=$ov";
	$dest->addOption($on,$ov);
    }
}

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

    commande_externe("pdftk",$sujet,
		     "cat","$debut-$fin",
		     "output",$fn);

    $avance->progres(1/(2*(1+$#es)));

    if($methode =~ /^cups/i) {
	$dest->printFile($fn,"QCM : copie $e");
    } elsif($methode =~ /^command/i) {
	my @c=map { s/[%]f/$fn/g;$_; } split(/\s+/,$print_cmd);
	
	#print STDERR join(' ',@c)."\n";
	commande_externe(@c);
    } else {
	die "Methode non reconnue : $methode";
    }

    close($tmp);

    $avance->progres(1/(2*(1+$#es)));
}

$avance->fin();



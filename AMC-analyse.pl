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

use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp;
use Getopt::Long;

use AMC::Basic;
use AMC::MEPList;
use AMC::Queue;

my $pid='';
my $queue='';

sub catch_signal {
    my $signame = shift;
    debug "*** AMC-analyse : signal $signame, je signale $pid...";
    kill 2,$pid if($pid);
    $queue->killall() if($queue);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

my $mep_dir="";
my $cr_dir="";
my $binaire='';
my $debug='';
my $progress=0;
my $progress_id=0;
my $liste_f;
my $mep_file='';
my $n_procs=0;
my $seuil_coche='';
my $rep_projet='';

GetOptions("mep=s"=>\$mep_dir,
	   "mep-saved=s"=>\$mep_file,
	   "cr=s"=>\$cr_dir,
	   "binaire!"=>\$binaire,
	   "seuil-coche=s"=>\$seuil_coche,
	   "debug=s"=>\$debug,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "liste-fichiers=s"=>\$liste_f,
	   "projet=s"=>\$rep_projet,
	   "n-procs=s"=>\$n_procs,
	   );

set_debug($debug);

$queue=AMC::Queue::new('max.procs',$n_procs);

my @scans=@ARGV;

if($liste_f && open(LISTE,$liste_f)) {
    while(<LISTE>) {
	chomp;
	if(-f $_) {
	    debug "Scan from list : $_";
	    push @scans,$_;
	} else {
	    print STDERR "ATTENTION : fichier inexistant : $_\n";
	}
    }
    close(LISTE);
}

exit(0) if($#scans <0);

($e_volume,$e_vdirectories,$e_vfile) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
}

sub check_rep {
    my ($r,$create)=(@_);
    if($create && ! -x $r) {
	mkdir($r);
    }
    
    die "ERREUR: Repertoire inexistant : $r" if(! -d $r);
}

check_rep($mep_dir);
check_rep($cr_dir,1);

my $delta=$progress/(1+$#scans);
my $fh;

if(!$mep_file) {
    debug "Reconstruction de la liste des mises en page...";
    $fh=File::Temp->new(TEMPLATE => "mep-XXXXXX",
			TMPDIR => 1,
			UNLINK=> 1);
    $mep_file=$fh->filename;
    my $m=AMC::MEPList::new($mep_dir);
    $m->save($mep_file);
    $fh->seek( 0, SEEK_END );
    debug "OK";
}

for my $s (@scans) {
    my @c=with_prog("AMC-calepage.pl");
    push @c,"--debug",debug_file();
    push @c,"--seuil-coche",$seuil_coche if($seuil_coche);
    push @c,"--progression-id",$progress_id;
    push @c,"--progression",$delta;
    push @c,"--binaire" if($binaire);
    push @c,"--mep",$mep_dir if($mep_dir);
    push @c,"--mep-saved",$mep_file;
    push @c,"--projet",$rep_projet if($rep_projet);
    push @c,"--cr",$cr_dir,$s;

    $queue->add_process(@c);
}

$queue->run();



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
use Text::Unaccent;
use XML::Simple;

use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::AssocFile;
use AMC::NamesFile;

my $debug='';

my $cmd_pid='';

sub catch_signal {
    my $signame = shift;
    debug "*** AMC-regroupe : signal $signame, je tue $cmd_pid...\n";
    kill 9,$cmd_pid if($cmd_pid);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

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

################################################################

my $jpgdir='';
my $pdfdir='';
my $modele="";
my $progress=1;
my $progress_id='';
my $association='';
my $fich_noms='';
my $noms_encodage='utf-8';

my $debug='';

GetOptions("cr=s"=>\$cr,
	   "modele=s"=>\$modele,
	   "fich-assoc=s"=>\$association,
	   "fich-noms=s"=>\$fich_noms,
	   "noms-encodage=s"=>\$noms_encodage,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "debug=s"=>\$debug,
	   );

set_debug($debug);

my $jpgdir="$cr/corrections/jpg";
my $pdfdir="$cr/corrections/pdf";

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $assoc='';
my $lk='';

if($association) {
    $assoc=AMC::AssocFile::new($association);
    $assoc->load() if($assoc);
    $lk=$assoc->get_param('liste_key');
}

my $noms='';

if($fich_noms) {
    $noms=AMC::NamesFile::new($fich_noms,
			      "encodage"=>$noms_encodage);
}

opendir(JDIR, $jpgdir) || die "can't opendir $jpgdir: $!";
@pages = grep { /^page.*jpg$/ && -f "$jpgdir/$_" } readdir(JDIR);
closedir JDIR;

my %r=();
for my $f (@pages) {
    my ($e,$p)=get_ep(file2id($f));
    $r{$e}={} if(!$r{$e});
    $r{$e}->{$p}="$jpgdir/$f";
}

for my $e (keys %r) {
    print "Regroupement des pages pour ID=$e...\n";

    my $f=$modele;
    $f='(N)' if(!$f);
    $f.='.pdf' if($f !~ /\.pdf$/i);
    
    my $ex=sprintf("%04d",$e);
    $f =~ s/\(N\)/$ex/gi;

    if($assoc && $noms) {
	my $i=$assoc->effectif($e);
	my $nom='XXX';
	my $n;

	if($i) {
	    ($n)=$noms->data($lk,$i);
	    if($n) {
		$nom=$n->{'_ID_'};
	    }
	}

	$nom =~ s/^\s+//;
	$nom =~ s/\s+$//;
	$nom =~ s/\s+/_/g;
	$nom=unac_string("UTF-8",$nom);

	$f =~ s/\(NOM\)/$nom/gi;

	if($n) {
	    for my $k ($noms->heads()) {
		my ($t)=$n->{$k};
		if($t) {
		    debug "$k -> $t\n";
		    $f =~ s/\($k:([0-9]+)\)/sprintf("%0$1d",$t)/gie;
		    $f =~ s/\($k\)/$t/gi;
		}
	    }
	}
    }
    
    $f="$pdfdir/$f";

    debug "Fichier destination : $f";

    my @sp=sort { $a <=> $b } (keys %{$r{$e}});

    debug "Pages : ".join(", ",@sp);
    #print "Sources : ".join(", ",map { $r{$e}->{$_} } @sp)."\n";

    commande_externe('convert',
		     '-adjoin',
		     '-page','A4',
		     (map { $r{$e}->{$_} } @sp),
		     $f);
    
    $avance->progres(1/(1+$#pages));
}

$avance->fin();

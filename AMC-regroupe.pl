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
use Text::Unaccent;
use XML::Simple;

use AMC::Basic;
use AMC::Exec;
use AMC::Gui::Avancement;
use AMC::AssocFile;
use AMC::NamesFile;
use AMC::ANList;
use AMC::MEPList;

use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use File::Copy;

use Graphics::Magick;

my $debug='';

my $commandes=AMC::Exec::new('AMC-regroupe');
$commandes->signalise();

($e_volume,$e_vdirectories,$e_vfile) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
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
my $an_saved='';
my $mep_dir='';
my $mep_saved='';

my $compose='';

my $moteur_latex='pdflatex';
my $tex_src='';

my $debug='';

GetOptions("cr=s"=>\$cr,
	   "an-saved=s"=>\$an_saved,
	   "mep=s"=>\$mep_dir,
	   "mep-saved=s"=>\$mep_saved,
	   "tex-src=s"=>\$tex_src,
	   "with=s"=>\$moteur_latex,
	   "modele=s"=>\$modele,
	   "fich-assoc=s"=>\$association,
	   "fich-noms=s"=>\$fich_noms,
	   "noms-encodage=s"=>\$noms_encodage,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "compose!"=>\$compose,
	   "debug=s"=>\$debug,
	   );

set_debug($debug);

$temp_dir = tempdir( DIR=>tmpdir(),
		     CLEANUP => (!get_debug()) );

debug "dir = $temp_dir";

my $correc_indiv="$temp_dir/correc.pdf";

my $jpgdir="$cr/corrections/jpg";
my $pdfdir="$cr/corrections/pdf";

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $assoc='';
my $lk='';

if($association) {
    $assoc=AMC::AssocFile::new($association);
    if($assoc) {
	$assoc->load();
	$lk=$assoc->get_param('liste_key');
    }
}

my $noms='';

if($fich_noms) {
    $noms=AMC::NamesFile::new($fich_noms,
			      "encodage"=>$noms_encodage);

    debug "Dans le fichier de noms, on trouve les champs : ".join(", ",$noms->heads());
}

my $anl='';

if($an_saved) {
    $anl=AMC::ANList::new($cr,
			  'saved'=>$an_saved,
			  'action'=>'',
			  );
} elsif(-d $cr) {
    $anl=AMC::ANList::new($cr,
			  'saved'=>'',
			  );
}

# fabrique eventuellement la correction individualisee

my $correc_indiv_ok='';

sub check_correc {
    if(!$correc_indiv_ok) {
	$correc_indiv_ok=1;

	debug "Preparation de la correction individuelle...";

	$commandes->execute(with_prog("AMC-prepare.pl"),
			    "--with",$moteur_latex,
			    "--mode","k",
			    "--out-corrige",$correc_indiv,
			    "--debug",debug_file(),
			    $tex_src);
    }
}

# ecriture d'une image en PDF, bonne dimension

sub write_pdf {
    my ($img,$file)=@_;

    my ($h,$w)=$img->Get('height','width');
    my $d_x=$w/(21.0/2.54);
    my $d_y=$h/(29.7/2.54);
    my $dens=($d_x > $d_y ? $d_x : $d_y);
    
    debug "GEOMETRY : $w x $h\n";
    debug "DENSITY : $d_x x $d_y --> $dens\n";
    
    my $w=$img->Write('filename'=>$file,
		      'page'=>($dens*21/2.54).'x'.($dens*29.7/2.54),
		      'adjoin'=>'True','units'=>'PixelsPerInch',
		      'compression'=>'jpeg','density'=>$dens.'x'.$dens);
    
    if($w) {
	print "ERREUR ecriture : $w\n";
	debug "ERREUR ecriture : $w\n";
	return(0);
    } else {
	return(1);
    }
}

# 1) rassemble tous les numeros de copie utilises

my @ids_utiles=();

if($anl) {
    # soit grace aux analyses

    @ids_utiles=$anl->ids();
} else {
    # soit grace aux jpg

    opendir(JDIR, $jpgdir) || die "can't opendir $jpgdir: $!";
    @ids_utiles = map { file2id($_); }
    grep { /^page.*jpg$/ && -f "$jpgdir/$_" } readdir(JDIR);
    closedir JDIR;
}

my %copie_utile=();

for my $id (@ids_utiles) {
    my ($e,$p)=get_ep($id);
    $copie_utile{$e}=1;
}

@ids_utiles=(keys %copie_utile);
my $n_copies=1+$#ids_utiles;

# 2) pour chaque copie, quelles sont les pages existantes sur le sujet

my $mep=AMC::MEPList::new($mep_dir,'saved'=>$mep_saved);

my %pages_e=$mep->pages_etudiants('ip'=>1);

# 3) rassemblement

# stockage de bouts de PDF ou de collections d'images

my $stk_ii;
my @stk_pages=();
my $stk_type;

sub stk_begin {
    $stk_ii=1;
    $stk_file="$temp_dir/$stk_ii.pdf";
    $stk_type='';
    @stk_pages=();
    stk_pdf_begin();
    stk_ppm_begin();
}

sub stk_push {
    push @stk_pages,$stk_file;
    $stk_ii++;
    $stk_file="$temp_dir/$stk_ii.pdf";
}

sub stk_go {
    stk_pdf_go() if($stk_type eq 'pdf');
    stk_ppm_go() if($stk_type eq 'ppm');
    $stk_type='';
}

sub stk_add {
    my ($t)=@_;
    if($stk_type ne $t) {
	stk_go();
	$stk_type=$t;
    }
}

# pdf

my @stk_pdf_pages=();

sub stk_pdf_begin {
    @stk_pdf_pages=();
}

sub stk_pdf_add {
    stk_add('pdf');
    push @stk_pdf_pages,@_;
}

sub stk_pdf_go {
    debug "Page(s) ".join(',',@stk_pdf_pages)." de la correction";
    
    check_correc();
    
    $commandes->execute("pdftk",$correc_indiv,
			"cat",@stk_pdf_pages,
			"output",$stk_file);

    stk_push();

    stk_pdf_begin();
}

# ppm

my $stk_ppm_im;

sub stk_ppm_begin {
    $stk_ppm_im=Graphics::Magick->new();
}

sub stk_ppm_add {
    stk_add('ppm');
    $stk_ppm_im->ReadImage(shift);
}

sub stk_ppm_go {
    stk_push() if(write_pdf($stk_ppm_im,$stk_file));    

    stk_ppm_begin();
}

# boucle sur les copies...

for my $e (sort { $a <=> $b } (keys %copie_utile)) {
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

	debug "Association -> ID=$i";

	if($i) {
	    ($n)=$noms->data($lk,$i);
	    if($n) {
		debug "Nom retrouve";
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

    stk_begin();

    for my $pp (@{$pages_e{$e}}) {

	$ii++;
	my $f_p="$temp_dir/$ii.pdf";

	my $f_j="$jpgdir/page-".id2idf($pp->{id}).".jpg";

	if(-f $f_j) {
	    # correction JPG presente : on transforme en PDF

	    debug "Page $pp->{id} annotee";

	    stk_ppm_add($f_j);

	} elsif($compose) {
	    # pas de JPG annote : on prend la page corrigee

	    debug "Page $pp->{id} de la correction";

	    stk_pdf_add($pp->{page});
	}
    }

    # on regroupe les pages PDF

    stk_go();

    if($#stk_pages==0) {
	debug "Move $stk_pages[0] to $f";
	move($stk_pages[0],$f);
    } elsif($#stk_pages>0) {
	$commandes->execute("pdftk",
			    @stk_pages,
			    "output",$f,"compress");
    }

    $avance->progres(1/$n_copies);
}

$avance->fin();

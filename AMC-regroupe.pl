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
use Encode;
use Unicode::Normalize;
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
my $nombre_copies=0;

my $sujet='';
my $dest_size_x=21/2.54;
my $dest_size_y=29.7/2.54;

GetOptions("cr=s"=>\$cr,
	   "n-copies=s"=>\$nombre_copies,
	   "an-saved=s"=>\$an_saved,
	   "sujet=s"=>\$sujet,
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

debug_pm_version("Graphics::Magick");

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

    debug "Keys in names file: ".join(", ",$noms->heads());
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

	debug "Making individual corrected sheet...";

	$commandes->execute(with_prog("AMC-prepare.pl"),
			    "--n-copies",$nombre_copies,
			    "--with",$moteur_latex,
			    "--mode","k",
			    "--out-corrige",$correc_indiv,
			    "--debug",debug_file(),
			    $tex_src);
    }
}

# detecte bonne dimension depuis le sujet, si disponible

if($sujet) {
    if(-f $sujet) {
	my @c=("identify","-format","%w,%h",$sujet.'[0]');
	debug "IDENT << ".join(' ',@c);
	if(open(IDENT,"-|",@c)) {
	    while(<IDENT>) {
		if(/^([0-9.]+),([0-9.]+)$/) {
		    debug "Size from subject : $1 x $2";
		    $dest_size_x=$1/72;
		    $dest_size_y=$2/72;
		}
	    }
	    close IDENT;
	} else {
	    debug "Error execing: $!";
	}
    } else {
	debug "No subject: $sujet";
    }
}

# ecriture d'une image en PDF, bonne dimension

sub write_pdf {
    my ($img,$file)=@_;

    my ($h,$w)=$img->Get('height','width');
    my $d_x=$w/$dest_size_x;
    my $d_y=$h/$dest_size_y;
    my $dens=($d_x > $d_y ? $d_x : $d_y);
    
    debug "GEOMETRY : $w x $h\n";
    debug "DENSITY : $d_x x $d_y --> $dens\n";
    debug "destination: $file";
    
    my $w=$img->Write('filename'=>$file,
		      'page'=>($dens*$dest_size_x).'x'.($dens*$dest_size_y),
		      'adjoin'=>'True','units'=>'PixelsPerInch',
		      'compression'=>'jpeg','density'=>$dens.'x'.$dens);
    
    if($w) {
	print "Write error: $w\n";
	debug "Write error: $w\n";
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
    debug "Page(s) ".join(',',@stk_pdf_pages)." form corrected sheet";
    
    check_correc();
    
    my @ps=sort { $a <=> $b } @stk_pdf_pages;
    my @morceaux=();
    my $mii=0;
    while(@ps) {
	my $debut=shift @ps;
	my $fin=$debut;
	while($ps[0]==$fin+1) { $fin=shift @ps; }
	
	$mii++;
	my $un_morceau="$temp_dir/m.$mii.pdf";

	debug "Slice $debut-$fin to $un_morceau";

	$commandes->execute("gs","-dBATCH","-dNOPAUSE","-q",
			    "-sDEVICE=pdfwrite",
			    "-sOutputFile=$un_morceau",
			    "-dFirstPage=$debut","-dLastPage=$fin",
			    $correc_indiv);
	push @morceaux,$un_morceau;
    }

    if($#morceaux==0) {
	debug "Moving single slice to destination $stk_file";
	move($morceaux[0],$stk_file);
    } else {
	debug "Joining slices...";
	$commandes->execute("gs","-dBATCH","-dNOPAUSE","-q",
			    "-sDEVICE=pdfwrite",
			    "-sOutputFile=$stk_file",
			    @morceaux);
	unlink @morceaux;
    }
			
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
    print "Pages for ID=$e...\n";

    my $f=$modele;
    $f='(N)-(ID)' if(!$f);
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
		debug "Name found";
		$nom=$n->{'_ID_'};
	    }
	}

	$nom =~ s/^\s+//;
	$nom =~ s/\s+$//;
	$nom =~ s/\s+/_/g;

	$f =~ s/\(ID\)/$nom/g;

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
	
        # enlever accents et caracteres un peu speciaux...
	$f=NFKD($f);
	$f =~ s/\pM//og;

    }
    
    $f="$pdfdir/$f";

    debug "Dest file: $f";

    stk_begin();

    for my $pp (@{$pages_e{$e}}) {

	$ii++;
	my $f_p="$temp_dir/$ii.pdf";

	my $f_j="$jpgdir/page-".id2idf($pp->{id}).".jpg";

	if(-f $f_j) {
	    # correction JPG presente : on transforme en PDF

	    debug "Page $pp->{id} annotated ($f_j)";

	    stk_ppm_add($f_j);

	} elsif($compose) {
	    # pas de JPG annote : on prend la page corrigee

	    debug "Page $pp->{id} from corrected sheet";

	    stk_pdf_add($pp->{page});
	}
    }

    # on regroupe les pages PDF

    stk_go();

    if($#stk_pages==0) {
	debug "Move $stk_pages[0] to $f";
	move($stk_pages[0],$f);
    } elsif($#stk_pages>0) {
	$commandes->execute("gs","-dBATCH","-dNOPAUSE","-q",
			    "-sDEVICE=pdfwrite",
			    "-sOutputFile=$f",@stk_pages);
    }

    $avance->progres(1/$n_copies);
}

$avance->fin();

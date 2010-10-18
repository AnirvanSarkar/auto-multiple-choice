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

use XML::Simple;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use Data::Dumper;
use Getopt::Long;

use Graphics::Magick;

use AMC::Basic;
use AMC::Exec;
use AMC::MEPList;
use AMC::Calage;
use AMC::Image;
use AMC::Boite qw/min max/;
use AMC::Gui::Avancement;

my $anf_version=1;

($e_volume,$e_vdirectories,$e_vfile) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
}

my $theta=0;
my $alpha=1;
my $ta=0;
my $tb=0;

my $t_type='lineaire';

my $t_a=1;
my $t_b=0;
my $t_c=0;
my $t_d=1;
my $t_e=0;
my $t_f=0;

my @cx,@cy;

my $M_PI=atan2(1,1)*4;

my $cases='';
my $out_cadre='';
my $zoom_file="";
my $zoom_plus=10;
my $nom_file="";
my $seuil_coche=0.1;

my $tol_marque='';
my $tol_marque_plus=1/5;
my $tol_marque_moins=1/5;

my $detecte_via='c'; # gocr ou c

# amelioration du scan :
my $blur='defaut';
my $threshold='defaut';
my $dust_size=10;
my $dust_size_id=3;

my $prop=0.8;

my $id_sep="/";

my $n_page="";
my $dpi="";
my $id_page_fourni="";

my $rep_projet='';
my $repertoire_cr="";
my $ocr_file='';

my $manuel=1;
my $binaire='';

my $debug='';
my $progress=0;
my $progress_id='';
my $progress_debut=0;

my $pdf_source='';

my $mep_saved='';

GetOptions("page=s"=>\$out_cadre,
	   "modele!"=>\$modele,
	   "pdf-source=s"=>\$pdf_source,
	   "mep=s"=>\$xml_layout,
	   "mep-saved=s"=>\$mep_saved,
	   "transfo=s"=>\$t_type,
	   "zooms=s"=>\$zoom_file,
	   "nom=s"=>\$nom_file,
	   "analyse=s"=>\$analyse_file,
	   "id-page=s"=>\$id_page_fourni,
	   "page=s"=>\$n_page,
	   "dpi=s"=>\$dpi,
	   "seuil-coche=s"=>\$seuil_coche,
	   "dust-size=s"=>\$dust_size,
	   "dust-size-id=s"=>\$dust_size_id,
	   "projet=s"=>\$rep_projet,
	   "cr=s"=>\$repertoire_cr,
	   "ocr=s"=>\$ocr_file,
	   "debug=s"=>\$debug,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "progression-debut=s"=>\$progress_debut,
	   "manuel!"=>\$manuel,
	   "binaire!"=>\$binaire,
	   "tol-marque=s"=>\$tol_marque,
	   );

set_debug($debug);

my $commandes=AMC::Exec::new('AMC-calepage');
$commandes->signalise();

if($tol_marque) {
    if($tol_marque =~ /(.*),(.*)/) {
	$tol_marque_moins=$1;
	$tol_marque_plus=$2;
    } else {
	$tol_marque_moins=$tol_marque;
	$tol_marque_plus=$tol_marque;
    }
}

$blur = ($modele ? "" : "1x1") if($blur eq 'defaut');
$threshold = ($modele ? "" : "60%") if($threshold eq 'defaut');

$ocr_file="$repertoire_cr/ocr-manuel.xml" if($repertoire_cr && !$ocr_file);

$scan=$ARGV[0];

sub erreur {
    my $e=shift;
    debug "ERROR($scan)($id_page) : $e\n";
    print "ERROR($scan)($id_page) : $e\n";
    exit(1);
}

################################################################

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

$avance->progres($progress_debut);

$temp_loc=tmpdir();
$temp_dir = tempdir( DIR=>$temp_loc,
		     CLEANUP => (!get_debug()) );

debug "dir = $temp_dir";

$ppm="$temp_dir/image.ppm";

if($blur || $threshold || $scan !~ /\.ppm$/) {
    print "Converting to ppm...\n";

    my @ca=(magick_module('convert'));
    push @ca,"-blur",$blur if($blur);
    push @ca,"-threshold",$threshold if($threshold);
    push @ca,$scan,$ppm;
    $commandes->execute(@ca);
} else {
    $ppm=$scan;
}

open(CMD,"identify $ppm|");
while(<CMD>) {
    if(/\sP[NBP]M\s+([0-9]+)x([0-9]+)/) {
	$tiff_x=$1;
	$tiff_y=$2;
    }
}
close(CMD);

erreur("Taille non reconnue") if(!$tiff_x);

debug "IMAGE = $scan ($tiff_x x $tiff_y)\n";

##########################################################
# Initiation des utilitaires

my $mep_dispos;

$mep_dispos=AMC::MEPList::new($xml_layout,"saved"=>$mep_saved);

erreur("No layout") if($mep_dispos->nombre()==0 && !$modele);

debug "".$mep_dispos->nombre()." layouts\n";

my $cale=AMC::Calage::new('type'=>$t_type);

my $cadre_general,$cadre_origine;

my $lay;

sub calage_reperes {
    my $id=shift;
    $lay=$mep_dispos->mep($id);

    if($lay) {
        $cadre_origine=AMC::Boite::new_complete_xml($lay);

	debug "Origine : ".$cadre_origine->txt()."\n";

	my @cx=map { $cadre_origine->coordonnees($_,'x') } (0..3);
	my @cy=map { $cadre_origine->coordonnees($_,'y') } (0..3);
	my @cxp=map { $cadre_general->coordonnees($_,'x') } (0..3);
	my @cyp=map { $cadre_general->coordonnees($_,'y') } (0..3);
	
	$cale->calage(\@cx,\@cy,\@cxp,\@cyp);

	debug "MSE=".$cale->mse();
    }
}

my $traitement=AMC::Image::new($ppm);

##########################################################
# vecteur binaire -> nombre decimal

sub decimal {
    my @ch=(@_);
    my $r=0;
    for (@ch) {
	$r=2*$r+$_;
    }
    return($r);
}


##########################################################
# Localisation des quatre marques

$avance->progres((1-$progress_debut)/3);

my $diametre_marque;

if($modele) {
    my @box=();

    # pour le modele, on utilise les couleurs specifiques

    print "Looking for signs...\n";

    my $nm=0;
    for($traitement->commande("magick")) {
	if(/magick=([0-9]+)\s+exo=([0-9]+)\s+quest=([0-9]+)\s+\(([0-9]+),([0-9]+)\)-\(([0-9]+),([0-9]+)\)\s+:\s+([0-9]+)\s*x\s*([0-9]+)/) {
	    if($1==201 && $2==100) {
		$box[$3-1]=AMC::Boite::new_MD($4,$5,$8,$9);
		$nm++;
	    }
	}
    }
    
    erreur("$nm signs found, instead of 4") if($nm != 4);

    $cadre_general=AMC::Boite::new_complete(map { $_->centre() } (@box));

    for my $b (@box) {
	debug " Box ".$b->txt();
	$diametre_marque+=$b->diametre();
    }
    $diametre_marque /= $nm;

} else {

    #####
    # chargement d'une MEP au hasard pour recuperer la taille

    my $hmep=$mep_dispos->mep();

    $rx=$tiff_x / $hmep->{'tx'};
    $ry=$tiff_y / $hmep->{'ty'};
    
    $taille=$hmep->{'diametremarque'}*($rx+$ry)/2;
    $taille_max=$taille*(1+$tol_marque_plus);
    $taille_min=$taille*(1-$tol_marque_moins);
    
    debug "rx = $rx   ry = $ry\n";
    debug(sprintf("Target sign size : %.2f (%.2f to %.2f)",
		  $taille,
		  $taille_min,$taille_max));

    # pour un scan, on utilise gOCR, ou des manips morphologiques

    if($detecte_via eq 'gocr') {

	$xml="$temp_dir/ocr.xml";

	print "gOCR...\n";

	open(CMD,"gocr -f XML -d $dust_size -C \"\" $ppm |");
	open(XF,">$xml");
	while(<CMD>) {
	    s/type=unknown/type="unknown"/g;

	    if(/<box\s+x=\"([^\"]+)\"\s+y=\"([^\"]+)\"\s+dx=\"([^\"]+)\"\s+dy=\"([^\"]+)\"\s+/) {
		push @box,AMC::Boite::new_MD($1,$2,$3,$4);
	    }

	    print XF;
	}
	close(CMD);
	close(XF);
    } elsif($detecte_via eq 'c') {

	my $lisse_trous=1+int(($taille_min+$taille_max)/2 /20);
	my $lisse_pouss=1+int(($taille_min+$taille_max)/2 /8);

	print "Morphological operations (+$lisse_trous-$lisse_pouss) and signs detection...\n";
	
	$traitement->commande("etend $lisse_trous");
	$traitement->commande("erode ".($lisse_trous+$lisse_pouss));
	$traitement->commande("etend $lisse_pouss");
	$traitement->commande("calccc");

	for($traitement->commande("magick")) {
	    if(/\(([0-9]+),([0-9]+)\)-[^\s]*\s+:\s+([0-9]+)\s*x\s*([0-9]+)/) {
		push @box,AMC::Boite::new_MD($1,$2,$3,$4);
	    }
	}

	$traitement->ferme_commande();

    } else {
	erreur("Bad value for --detecte-via : $detecte_via");
    }

    print "".($#box+1)." boxes.\n";

    debug join("\n",map { $_->txt(); } @box);

    print "Searching signs...\n";

    @okbox=grep { $_->bonne_etendue($taille_min,$taille_max) } @box;

    @okbox=AMC::Boite::extremes(@okbox);

    if(get_debug()) {
	for my $c (@okbox) {
	    my ($dx,$dy)=$c->etendue_xy();
	    debug(sprintf("Sign size: $dx x $dy (%6.2f | %6.2f %%)",
			  100*($dx-$taille)/$taille,100*($dy-$taille)/$taille)); 
	}
    }

    $cadre_general=AMC::Boite::new_complete(map { $_->centre() } (@okbox));

}

debug "Global frame:",
    $cadre_general->txt();

###############################################################
# identification du numero de page : cas ecriture standard

$avance->progres((1-$progress_debut)/3);

my $bandeau=Graphics::Magick::new();

$bandeau->Read($scan);

# mesure de l'angle de la ligne superieure

my $angle=$cadre_general->direction(0,1);
my $dy_head=max($cadre_general->coordonnees(0,'y'),
		$cadre_general->coordonnees(1,'y'));
my $xa=$cadre_general->coordonnees(0,'x');
my $xb=$cadre_general->coordonnees(1,'x');

# coupe le haut de la page et le tourne pour qu'il soit droit

$bandeau->Crop(int($xb-$xa)."x".int($dy_head)."+".$xa."+0");
$bandeau->Rotate(-$angle*180/$M_PI);

# utilise gocr pour reconnaitre l'ID

if(!$binaire) {
    print "Reading page ID...\n";

    my $page_droite="$temp_dir/droit.pnm";

    $bandeau->Write($page_droite);
    
    open(OCR,"gocr -d $dust_size_id -C \"0123456789+$id_sep\" $page_droite |");
    while(<OCR>) {
	if(/([_\+][0-9\s]+$id_sep[0-9\s]+$id_sep[0-9\s]+[_\+])/) {
	    $_=$1;
	    s/\s+//g;
	    s/_/+/g;
	    $id_page=$_;
	    print "Page : $id_page\n";
	} 
    }
    close(OCR);
}

# perl -e 'use XML::Simple;use Data::Dumper;print Dumper(XMLin("points-cr/ocr-manuel.xml",ForceArray => 1,KeyAttr=>['scan']));'

my $id_page_f;

sub valide_id_page {

    # ID page reconnu manuellement, stocke dans fichier XML
    if($ocr_file && -f $ocr_file) {
	my $oc=XMLin($ocr_file,ForceArray => 1,KeyAttr=>['scan']);
	my $m=$oc->{'page'}->{$scan}->{'id'};
	if($m) {
	    print "Page (manual) : $m\n";
	    $id_page=$m;
	}
    }
    
    # ID fourni en ligne de commande
    if($id_page_fourni) {
	print "Page (option) : $m\n";
	if($id_page && $id_page ne $id_page_fourni) {
	    attention("WARNING: page ID mismatch!");
	}
	$id_page=$id_page_fourni;
    }

    attention("WARNING: No page ID!") if(!$id_page);
    
    $id_page_f=$id_page;
    $id_page_f =~ s/[^0-9]/-/g;
    $id_page_f =~ s/^-+//g;
    $id_page_f =~ s/-+$//g;
    
    if($repertoire_cr) {
	$out_cadre="$repertoire_cr/page-$id_page_f.jpg";
	$zoom_file="$repertoire_cr/zoom-$id_page_f.jpg";
	$nom_file="$repertoire_cr/nom-$id_page_f.jpg";
	$analyse_file="$repertoire_cr/analyse-$id_page_f.xml" if(!$modele);
    }
}

sub une_ligne {
    my ($ax,$ay,$bx,$by)=(@_);
    return("-draw",sprintf("line %.2f,%.2f %.2f,%.2f",$ax,$ay,$bx,$by));
}

###################################################
# gestion des cases

my %case=();

my %score,%score_data,%coins_test;

sub mesure_case {
    my ($k)=(@_);
    my $r=0;

    $coins_test{$k}=AMC::Boite::new();
    
    for($traitement->commande($case{$k}->commande_mesure($prop))) {
	
	if(/^COIN\s+(-?[0-9\.]+),(-?[0-9\.]+)$/) {
	    $coins_test{$k}->def_point_suivant($1,$2);
	}
	if(/^PIX\s+([0-9]+)\s+([0-9]+)$/) {
	    $r=($2==0 ? 0 : $1/$2);
	    printf " Case $k : %d/%d = %.4f\n",$1,$2,$r;
	    $score{$k}=$r;
	    $score_data{$k}="pixels=\"$2\" pixelsnoirs=\"$1\" r=\"$r\"";
	}
    }
    
    return($r);
}

sub code_cb {
    my ($nombre,$chiffre)=(@_);
    return("$nombre:$chiffre");
}

sub detecte_cb {
    my $k=shift;
    if($k =~ /^([0-9]+):([0-9]+)$/) {
	return($1,$2);
    } else {
	return();
    }
}

sub get_nb_binaire {
    my $i=shift;
    my @ch=();
    my $a=1;
    my $fin='';
    do {
	my $k=code_cb($i,$a);
	if($case{$k}) {
	    push @ch,(mesure_case($k,1)>.5 ? 1 : 0);
	    $a++;
	} else {
	    $fin=1;
	}
    } while(!$fin);
    return(decimal(@ch));
}

sub get_id_binaire {
    $id_page="+".get_nb_binaire(1)."/".get_nb_binaire(2)."/".get_nb_binaire(3)."+";
    print "Page : $id_page\n";
    debug("Found binary ID: $id_page");
}

if($modele) {

    # c'est le modele : on repere la localisation des cases (par leur
    # couleur RGB) et on met ca dans le XML

    print "Searching for boxes...\n";
    
    for($traitement->commande("magick")) {
	debug "$_";
	if(/magick=([0-9]+)\s+exo=([0-9]+)\s+quest=([0-9]+)\s+\(([0-9]+),([0-9]+)\)-\(([0-9]+),([0-9]+)\)/) {
	    my $k='';
	    my $mag=$1;
	    my $e=$2;
	    my $q=$3;
	    my @xy=($4,$5,$6,$7);
	    if($mag==200) {
		$k="$e.$q";
	    }
	    if($mag==201) {
		if($e >=1 && $e <=3) {
		    $k=code_cb($e,$q);
		} elsif($e==255 && $q==255) {
		    $k="nom";
		}
	    }
	    $case{$k}=AMC::Boite::new_MN(@xy) if($k);

	}
    }

    debug "Boxes: ".join(" ",sort { $a cmp $b } (keys %case));

    if($binaire) {
	get_id_binaire();
    }

    valide_id_page();

    if(-d $xml_layout) {
	$xml_layout="$xml_layout/mep-$id_page_f.xml";
    }

    if($xml_layout) {
	open(XML,">$xml_layout");
	print XML "<?xml version='1.0' standalone='yes'?>\n";
	print XML "<mep image=\"$scan\" id=\"$id_page\" src=\"$pdf_source\" page=\"$n_page\" dpi=\"$dpi\" tx=\"$tiff_x\" ty=\"$tiff_y\" diametremarque=\"$diametre_marque\">\n";
	print XML $cadre_general->xml(2);
	for my $k (keys %case) {
	    if($k =~ /([0-9]+)\.([0-9]+)/) {
		print XML "  <case question=\"$1\" reponse=\"$2\" "
		    .$case{$k}->etendue_xy('xml')
		    ."/>\n"; 
	    } elsif(($n,$i)=detecte_cb($k)) {
		print XML "  <chiffre n=\"$n\" i=\"$i\" "
		    .$case{$k}->etendue_xy('xml')
		    ."/>\n"; 
	    } elsif($k eq 'nom') {
		print XML "  <nom "
		    .$case{$k}->etendue_xy('xml')
		    ."/>\n"; 
	    }
	}
	print XML "</mep>\n";
	close(XML);
    }
} else {

    # ce n'est pas un modele

    erreur("No layout instructions...") if(!($mep_saved || $xml_layout));
    
    # perl -e 'use XML::Simple;use Data::Dumper;$lay=XMLin("test-layout/mep-103-1-993.xml",ForceArray => 1,KeepRoot => 1);print Dumper($lay);'

    if($mep_saved || -d $xml_layout) {
	#####
	# calage sur une MEP au hasard pour recuperer l'ID binaire

	if($binaire) {
	    # caler sur une mise en page quelconque :
	    print "Positionning to read ID...\n";
	    debug "Positionning to read ID...\n";
	    
	    calage_reperes();

	    for my $c (@{$lay->{'chiffre'}}) {
		$case{code_cb($c->{'n'},$c->{'i'})}=
		    AMC::Boite::new_xml($c)->transforme($cale);
	    }

	    get_id_binaire();
	} else {
	    # on a deja l'ID
	}

	valide_id_page();

	# reconaissance manuelle de l'ID de page
	if($manuel) {
	}

    } else {
	valide_id_page();
    }

    calage_reperes($id_page);

    erreur("No XML for ID $id_page") if(! $lay);
    
    # On cherche a caler les marques.

    ############ recuperation des positions des cases sur le modele

    for my $c (@{$lay->{'case'}}) {
	$case{$c->{'question'}.".".$c->{'reponse'}}=
	    AMC::Boite::new_xml($c)->transforme($cale);
    }
    for my $c (@{$lay->{'nom'}}) {
	$case{'nom'}=
	    AMC::Boite::new_xml($c)->transforme($cale);
    }

}

if(!$modele) {
    # on localise les cases recuperees depuis le modele dans le scan, et
    # on mesure la quantite de noir dedans
    
    for my $k (keys %case) {
	mesure_case($k) if($k =~ /^[0-9]+\.[0-9]+$/);
    }

    if($analyse_file) {
	open(ANF,">$analyse_file");
	print ANF "<?xml version='1.0' standalone='yes'?>\n";

	my $sf=$scan;
	if($rep_projet) {
	    $sf=abs2proj({'%PROJET',$rep_projet,
			  '%HOME'=>$ENV{'HOME'},
			  ''=>'%PROJET',
		      },
			 $sf);
	}

	print ANF "<analyse version=\"$anf_version\" src=\"".$sf."\" id=\"$id_page\">\n";
	print ANF $cale->xml(2);
	print ANF "  <cadre>\n";
	print ANF $cadre_general->xml(4);
	print ANF "  </cadre>\n";
	for my $k (keys %case) {
	    my $e="";
	    my $q="";
	    if($k =~ /^([0-9]+)\.([0-9]+)$/) {
		$e=$1;$q=$2;
		print ANF "  <casetest id=\"$k\">\n";
		print ANF $coins_test{$k}->xml(4);
		print ANF "  </casetest>\n";
		print ANF "  <case id=\"$k\" question=\"$e\" reponse=\"$q\" ";
		$close="  </case>\n";
	    } elsif(($n,$i)=detecte_cb($k)) {
		print ANF "  <chiffre n=\"$n\" i=\"$i\" ";
		$close="  </chiffre>\n";
	    } else {
		print ANF "  <$k ";
		$close="  </$k>\n";
	    }
	    print ANF $score_data{$k};
	    print ANF ">\n";
	    print ANF $case{$k}->xml(4);
	    print ANF $close;
	}
	print ANF "</analyse>\n";
	close(ANF);
    }
}

$traitement->ferme_commande();

# traces sur le scan pour localiser les cases et le cadre

my $page_entiere;

if($out_cadre || $nom_file) {
    debug "Reading scan $scan for extractions...";
    $page_entiere=Graphics::Magick::new();
    $page_entiere->Read($scan);
}

if($nom_file && $case{'nom'}) {
    debug "Name zone extraction to $nom_file...";
    debug "Name box : ".$case{'nom'}->txt();
    my $e=$page_entiere->Clone(); 	 
    $e->Crop(geometry=>$case{'nom'}->etendue_xy('geometry',$zoom_plus));
    $e->Write($nom_file);
}

if($out_cadre) {

    print "Annotating image...\n";

    # transcription de l'identifiant lu

    $page_entiere->Annotate(text=>$id_page,
			    geometry=>"+0+96",
			    pointsize=>96,
			    font=>"Courier",
			    fill=>"blue",stroke=>'blue');

    ###############################################
    # cases du modele $cale->transformees, avec annotation
    for my $k (keys %coins_test) {

	# case
	$page_entiere->Draw(primitive=>'polygon',
			    fill=>'none',stroke=>'blue',strokewidth=>1,
			    points=>$case{$k}->draw_points());

	# part de la case testee
	$page_entiere->Draw(primitive=>'polygon',
			    fill=>'none',stroke=>'magenta',strokewidth=>1,
			    points=>$coins_test{$k}->draw_points());

    }

    ###############################################
    # trace des cadres

    $page_entiere->Draw(primitive=>'polygon',
			fill=>'none',stroke=>'red',strokewidth=>1,
			points=>$cadre_general->draw_points());
    
    $cadre_origine->transforme($cale);
    $page_entiere->Draw(primitive=>'polygon',
			fill=>'none',stroke=>'blue',strokewidth=>1,
			points=>$cadre_origine->draw_points());
    
    $page_entiere->Write($out_cadre);
    
    debug "-> $out_cadre\n";
}

if($zoom_file) {

    print "Making zooms...\n";

    my $commandes=AMC::Exec::new("AMC-calepage");
    $commandes->signalise();

    $commandes->execute(with_prog("AMC-zoom.pl"),
			"--seuil",$seuil_coche,
			"--analyse",$analyse_file,
			"--scan",$scan,
			"--output",$zoom_file,
			);
}

$avance->fin();


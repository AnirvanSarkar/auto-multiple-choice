#! /usr/bin/perl
#
# Copyright (C) 2008-2011 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 2 of
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
use File::Spec::Functions qw/tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use Data::Dumper;
use Getopt::Long;

use AMC::Basic;
use AMC::Exec;
use AMC::Data;
use AMC::Calage;
use AMC::Image;
use AMC::Boite qw/min max/;
use AMC::Gui::Avancement;
use AMC::DataModule::capture qw/:zone :position/;

my $anf_version=1;

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
my $zoom_dir="";
my $zoom_plus=10;
my $nom_file="";
my $seuil_coche=0.1;

my $tol_marque='';
my $tol_marque_plus=1/5;
my $tol_marque_moins=1/5;

# amelioration du scan :
my $blur='defaut';
my $threshold='defaut';
my $dust_size=10;
my $dust_size_id=3;

my $prop=0.8;

my $id_sep="/";

my $id_page_fourni="";

my $rep_projet='';
my $repertoire_cr="";

my $debug='';
my $progress=0;
my $progress_id='';
my $progress_debut=0;

my $debug_image='';

my $multiple='';

my @stud_page;

GetOptions("page=s"=>\$out_cadre,
	   "multiple!"=>\$multiple,
	   "data=s"=>\$data_dir,
	   "transfo=s"=>\$t_type,
	   "zooms=s"=>\$zoom_file,
	   "id-page=s"=>\$id_page_fourni,
	   "seuil-coche=s"=>\$seuil_coche,
	   "dust-size=s"=>\$dust_size,
	   "dust-size-id=s"=>\$dust_size_id,
	   "projet=s"=>\$rep_projet,
	   "cr=s"=>\$repertoire_cr,
	   "debug=s"=>\$debug,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "progression-debut=s"=>\$progress_debut,
	   "tol-marque=s"=>\$tol_marque,
	   "debug-image=s"=>\$debug_image,
	   );

set_debug($debug);

my $traitement;
my $upside_down;

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

$blur = "1x1" if($blur eq 'defaut');
$threshold = "60%" if($threshold eq 'defaut');

$scan=$ARGV[0];

my $sf=$scan;
if($rep_projet) {
  $sf=abs2proj({'%PROJET',$rep_projet,
		'%HOME'=>$ENV{'HOME'},
		''=>'%PROJET',
	       },
	       $sf);
}

sub erreur {
    my ($e,$silent)=shift;
    if($debug_image &&
       $traitement->mode() eq 'opencv') {
	$traitement->commande("output ".$debug_image);
	$traitement->ferme_commande;
    }
    if($silent) {
	debug $e;
    } else {
	debug "ERROR($scan)($id_page) : $e\n";
	print "ERROR($scan)($id_page) : $e\n";
    }
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

$traitement=AMC::Image::new($ppm);

debug "Mode: ".$traitement->mode();

if($traitement->mode() eq 'opencv') {
    $ppm=$scan;
} else{

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
}

##########################################################
# Initiation des utilitaires

my $layout=AMC::Data->new($data_dir)->module('layout');

my $cale;
my $cadre_general;
my $cadre_origine;

my @epc;

sub commande_transfo {
    my @r=$traitement->commande(@_);
    for(@r) {
	$cale->{'t_'.$1}=$2 if(/([a-f])=(-?[0-9.]+)/);
	$cale->{'MSE'}=$1 if(/MSE=([0-9.]+)/);
    }
}

sub calage_reperes {
  my ($id,$dont_create)=@_;

  @epc=get_epc($id) if($id);

  $layout->begin_read_transaction('cREP');

  @epc=($layout->random_studentPage,-1) if(!@epc && !$dont_create) ;
  if(!($epc[2]<0 || $layout->exists(@epc))) {
    $layout->end_transaction('cREP');
    return;
  }

  $cadre_origine=AMC::Boite::new_complete($layout->all_marks(@epc[0,1]));
  $layout->end_transaction('cREP');

  debug "Origine : ".$cadre_origine->txt()."\n";

  if($traitement->mode() eq 'opencv') {

    $cale=AMC::Calage::new('type'=>'lineaire');
    commande_transfo(join(' ',"optim",
			  $cadre_origine->draw_points()));

  } else {

    my @cx=map { $cadre_origine->coordonnees($_,'x') } (0..3);
    my @cy=map { $cadre_origine->coordonnees($_,'y') } (0..3);
    my @cxp=map { $cadre_general->coordonnees($_,'x') } (0..3);
    my @cyp=map { $cadre_general->coordonnees($_,'y') } (0..3);

    $cale->calage(\@cx,\@cy,\@cxp,\@cyp);

  }

  debug "MSE=".$cale->mse();
}

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

# chargement d'une MEP au hasard pour recuperer la taille

$layout->begin_read_transaction('cDIM');

if($layout->pages_count()==0) {
  $layout->end_transaction('cDIM');
  erreur("No layout");
}
debug "".$layout->pages_count()." layouts\n";

my @ran=$layout->random_studentPage;
my ($width,$height,$markdiameter)=
    $layout->dims(@ran);
$layout->end_transaction('cDIM');

$cale=AMC::Calage::new('type'=>$t_type);

if($traitement->mode() eq 'opencv') {

    my @r;
    my @args=('-x',$width,
	      '-y',$height,
	      '-d',$markdiameter,
	      '-p',$tol_marque_plus,'-m',$tol_marque_moins,
	      '-o',($debug_image ? $debug_image : 1)
	);

    push @args,'-P' if($debug_image);

    $traitement->set('args',\@args);

    @r=$traitement->commande("load ".$ppm);
    my @c=();
    for(@r) {
	if(/Frame\[([0-9]+)\]:\s*(-?[0-9.]+)\s*[,;]\s*(-?[0-9.]+)/) {
	    push @c,$2,$3;
	}
    }
    $cadre_general=AMC::Boite::new_complete(@c);

} else {

    $rx=$tiff_x / $width;
    $ry=$tiff_y / $height;

    $taille=$markdiameter*($rx+$ry)/2;
    $taille_max=$taille*(1+$tol_marque_plus);
    $taille_min=$taille*(1-$tol_marque_moins);

    debug "rx = $rx   ry = $ry\n";
    debug(sprintf("Target sign size : %.2f (%.2f to %.2f)",
		  $taille,
		  $taille_min,$taille_max));

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

    print "".($#box+1)." boxes.\n";

    debug join("\n",map { $_->txt(); } @box);

    print "Searching signs...\n";

    @okbox=grep { $_->bonne_etendue($taille_min,$taille_max) } @box;

    if($#okbox < 3) {
	erreur("Only ".(1+$#okbox)." signs detected / needs at least 4");
    }

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
# identification du numero de page

$avance->progres((1-$progress_debut)/3);

my $id_page_f,$id_page_f0;

sub valide_id_page {

    @stud_page=get_epo($id_page);

    # ID fourni en ligne de commande
    if($id_page_fourni) {
	print "Page (option) : $id_page_fourni\n";
	$id_page=$id_page_fourni;
    }

    attention("WARNING: No page ID!") if(!$id_page);

    $id_page_f=id2idf($id_page);
    $id_page_f0=id2idf($id_page,'simple'=>1);

    if($repertoire_cr) {
	$zoom_file="$repertoire_cr/zoom-$id_page_f.jpg";
	$zoom_dir="$repertoire_cr/zooms/$id_page_f0";
	$analyse_file="$repertoire_cr/analyse-$id_page_f.xml";

	# clear old analysis results files

	clear_old('analysis result',
		  $out_cadre,$zoom_file,$zoom_dir);
    }
}

sub une_ligne {
    my ($ax,$ay,$bx,$by)=(@_);
    return("-draw",sprintf("line %.2f,%.2f %.2f,%.2f",$ax,$ay,$bx,$by));
}

###################################################
# gestion des cases

my %case=();

my %zoom_file,%score_data,%coins_test;

sub mesure_case {
    my ($k)=(@_);
    my $r=0;

    $coins_test{$k}=AMC::Boite::new();

    if($traitement->mode() eq 'opencv' && @stud_page) {
	if($k =~ /^([0-9]+)\.([0-9]+)$/) {
	    $traitement->commande(join(' ',"id",@stud_page,$1,$2))
	}
    }

    for($traitement->commande($case{$k}->commande_mesure($prop))) {

	if(/^COIN\s+(-?[0-9\.]+),(-?[0-9\.]+)$/) {
	    $coins_test{$k}->def_point_suivant($1,$2);
	}
	if(/^PIX\s+([0-9]+)\s+([0-9]+)$/) {
	    $r=($2==0 ? 0 : $1/$2);
	    debug sprintf("Binary box $k: %d/%d = %.4f\n",$1,$2,$r);
	    $score_data{$k}=[$2,$1];
	}
	if(/^ZOOM\s+(.*)/) {
	  $zoom_file{$k}=$1;
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
    @epc=map { get_nb_binaire($_) } (1,2,3);
    $id_page="+".join('/',@epc)."+";
    print "Page : $id_page\n";
    debug("Found binary ID: $id_page");
}

erreur("No data directory...") if(! -d $data_dir);

sub read_id {
    print "Positionning to read ID...\n";
    debug "Positionning to read ID...\n";

    # first, use the layout info from a random page (they should be
    # the same for all pages) to get the transformation layout->scan

    calage_reperes();

    # prepares digit-boxes reading

    my $c;
    $layout->begin_read_transaction('cDIG');
    my $sth=$layout->statement('digitInfo');
    $sth->execute(@epc[0,1]);
    while($c=$sth->fetchrow_hashref) {
	my $k=code_cb($c->{'numberid'},$c->{'digitid'});
	my $c0=AMC::Boite::new_MN(map { $c->{$_} }
				  (qw/xmin ymin xmax ymax/));
	$case{$k}=$c0->transforme($cale);
    }
    $layout->end_transaction('cDIG');

    # reads the ID from the binary boxes

    get_id_binaire();

    # computes again the transformation from the layout info of the
    # right page

    calage_reperes($id_page,1);
}

#####

read_id();
$upside_down=0;

if($traitement->mode() eq 'opencv') {
  $layout->begin_read_transaction('cUSD');
  my $ok=$layout->exists(@epc);
  $layout->end_transaction('cUSD');

  if(!$ok) {
    # Unknown ID: tries again upside down

    $traitement->commande("rotate180");

    read_id();
    $upside_down=1;
  }
}

$layout->begin_read_transaction('cFLY');
my $ok=$layout->exists(@epc);
$layout->end_transaction('cFLY');

if(! $ok) {

  # Page ID has not been found: report it in the database.
  my $capture=AMC::Data->new($data_dir)->module('capture');
  $capture->begin_transaction('CFLD');
  $capture->failed($sf);
  $capture->end_transaction('CFLD');

  erreur("No layout for ID $id_page") ;
}

if($traitement->mode() eq 'opencv') {
    commande_transfo("rotateOK");
}

valide_id_page();

if($repertoire_cr && ($traitement->mode() eq 'opencv')) {
    $traitement->commande("zooms $repertoire_cr/zooms");
    $traitement->commande("createzd ".join(" ",@stud_page));
}

# On cherche a caler les marques.

############ recuperation des positions des cases sur le modele

my $c;
$layout->begin_read_transaction('cBOX');
my $sth=$layout->statement('boxInfo');
$sth->execute(@epc[0,1]);
while($c=$sth->fetchrow_hashref) {
    $case{$c->{'question'}.".".$c->{'answer'}}=
	AMC::Boite::new_MN(map { $c->{$_} }
			   (qw/xmin ymin xmax ymax/))->transforme($cale);
}
$sth=$layout->statement('namefieldInfo');
$sth->execute(@epc[0,1]);
while($c=$sth->fetchrow_hashref) {
    $case{'nom'}=
	AMC::Boite::new_MN(map { $c->{$_} }
			   (qw/xmin ymin xmax ymax/))->transforme($cale);
}
$layout->end_transaction('cBOX');

# on localise les cases recuperees depuis le modele dans le scan, et
# on mesure la quantite de noir dedans

for my $k (keys %case) {
    mesure_case($k) if($k =~ /^[0-9]+\.[0-9]+$/);
}

if($out_cadre && ($traitement->mode() eq 'opencv')) {
    $traitement->commande("annote $id_page");
}

erreur("End of diagnostic",1) if($debug_image);

my $capture=AMC::Data->new($data_dir)->module('capture');

$capture->begin_transaction('CRSL');
@stid=@epc[0,1];
if($multiple) {
  push @stid,$capture->new_page_copy(@epc[0,1]);
} else {
  push @stid,0;
}

$layout_file="page-".pageids_string(@stid,'path'=>1).".jpg";
$out_cadre="$repertoire_cr/$layout_file"
  if($repertoire_cr && !$out_cadre);

if($out_cadre && ($traitement->mode() eq 'opencv')) {
    $traitement->commande("output ".$out_cadre);
}

$nom_file="name-".studentids_string(@stid[0,2]).".jpg";

$capture->set_page_auto($sf,@stid,time(),
			$cale->params);

$capture->set_layout_image(@stid,$layout_file);

$cadre_general->to_data($capture,
			$capture->get_zoneid(@stid,ZONE_FRAME,0,0,1),
			POSITION_BOX);

for my $k (keys %case) {
  my $zoneid;
  if($k =~ /^([0-9]+)\.([0-9]+)$/) {
    my $question=$1;
    my $answer=$2;
    $zoneid=$capture->get_zoneid(@stid,ZONE_BOX,$question,$answer,1);
    $coins_test{$k}->to_data($capture,$zoneid,POSITION_MEASURE);
  } elsif(($n,$i)=detecte_cb($k)) {
    $zoneid=$capture->get_zoneid(@stid,ZONE_DIGIT,$n,$i,1);
  } elsif($k eq 'nom') {
    $zoneid=$capture->get_zoneid(@stid,ZONE_NAME,0,0,1);
    $capture->statement('setZoneAuto')
      ->execute(-1,-1,$nom_file,$zoneid);
  }

  if($zoneid) {
    if($k ne 'nom') {
      if($score_data{$k}) {
	$capture->statement('setZoneAuto')
	  ->execute(@{$score_data{$k}},$zoom_file{$k},$zoneid);
      } else {
	debug "No darkness data for box $k";
      }
    }
    $case{$k}->to_data($capture,$zoneid,POSITION_BOX);
  }
}

$capture->end_transaction('CRSL');

$traitement->ferme_commande();

# traces sur le scan pour localiser les cases et le cadre

my $page_entiere;

if($out_cadre || $nom_file) {
    debug "Reading scan $scan for extractions...";
    $page_entiere=magick_perl_module()->new();
    $page_entiere->Read($scan);
}

if($nom_file && $case{'nom'}) {
  clear_old('name image file',"$repertoire_cr/$nom_file");

  debug "Name box : ".$case{'nom'}->txt();
  my $e=$page_entiere->Clone();
  $e->Crop(geometry=>$case{'nom'}->etendue_xy('geometry',$zoom_plus));
  debug "Writing to $repertoire_cr/$nom_file...";
  $e->Write("$repertoire_cr/$nom_file");
}

if($out_cadre && ($traitement->mode ne 'opencv')) {

    print "Annotating image...\n";
    debug "Annotating image...\n";

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

if($upside_down) {
    # Rotates the scan file
    print "Rotating...\n";

    $commandes->execute(magick_module("convert"),
			"-rotate","180",$scan,$scan);
}

$avance->fin();


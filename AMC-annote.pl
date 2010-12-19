#! /usr/bin/perl
#
# Copyright (C) 2009-2010 Alexis Bienvenue <paamc@passoire.fr>
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
use Getopt::Long;
use Data::Dumper;

use AMC::Basic;
use AMC::Exec;
use AMC::ANList;
use AMC::Gui::Avancement;

use Graphics::Magick;

use encoding 'utf8';

$VERSION_BAREME=2;

my $cr_dir="";
my $rep_projet='';
my $rep_projets='';
my $fichnotes='';
my $fich_bareme='';

my $seuil=0.1;

my $an_saved='';

my $taille_max="1000x1500";
my $qualite_jpg="65";

my $debug='';

my $progress=1;
my $progress_id='';

my $line_width=2;
my @o_symbols=();
my $annote_indicatives='';
my $position='marge';
my $ecart=5.5;
my $ecart_marge=1.5;
my $pointsize_rel=60;

my $chiffres_significatifs=4;

# cle : "a_cocher-cochee"
my %symboles=(
    '0-0'=>{qw/type none/},
    '0-1'=>{qw/type circle color red/},
    '1-0'=>{qw/type mark color red/},
    '1-1'=>{qw/type mark color blue/},
);

GetOptions("cr=s"=>\$cr_dir,
	   "projet=s",\$rep_projet,
	   "projets=s",\$rep_projets,
	   "an-saved=s"=>\$an_saved,
	   "bareme=s"=>\$fich_bareme,
	   "notes=s"=>\$fichnotes,
	   "debug=s"=>\$debug,
	   "taille-max=s"=>\$taille_max,
	   "qualite=s"=>\$qualite_jpg,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "line-width=s"=>\$line_width,
	   "symbols=s"=>\@o_symbols,
	   "indicatives=s"=>\$annote_indicatives,
	   "position=s"=>\$position,
	   "pointsize-nl=s"=>\$pointsize_rel,
	   "ecart=s"=>\$ecart,
	   "ecart-marge=s"=>\$ecart_marge,
	   "ch-sign=s"=>\$chiffres_significatifs,
	   );

set_debug($debug);

debug_pm_version("Graphics::Magick");

for(split(/,/,join(',',@o_symbols))) {
    if(/^([01]-[01]):(none|circle|mark|box)(?:\/([\#a-z0-9]+))?$/) {
	$symboles{$1}={type=>$2,color=>$3};
    } else {
	die "Bad symbol syntax: $_";
    }
}

my $commandes=AMC::Exec::new("AMC-annote");
$commandes->signalise();

if(! -d $cr_dir) {
    attention("No CR directory: $cr_dir");
    die "No CR directory: $cr_dir";
}
if(! -f $fichnotes) {
    attention("No marks file: $fichnotes");
    die "No marks file: $fichnotes";
}
if(! -f $fich_bareme) {
    attention("No marking scale file: $fich_bareme");
    die "No marking scale file: $fich_bareme";
}

sub format_note {
    my $x=shift;
    if($chiffres_significatifs>0) {
	$x=sprintf("%.*g",$chiffres_significatifs,$x);
    }
    return($x);
}

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

opendir(DIR, $cr_dir) || die "can't opendir $cr_dir: $!";
my @xmls = grep { /\.xml$/ && -f "$cr_dir/$_" } readdir(DIR);
closedir DIR;

my $anl;

if($an_saved) {
    $anl=AMC::ANList::new($cr_dir,
			  'saved'=>$an_saved,
			  );
} else {
    debug "Making analysis list...";
    $anl=AMC::ANList::new($cr_dir,
			  'saved'=>'',
			  );
}

print "Sources :\n";
for my $id ($anl->ids()) {
    print "ID=$id : ".$anl->filename($id)
    .($anl->attribut($id,'manuel') ? " (manuel)" : "")."\n";
}
print "\n";

my $bar=XMLin($fich_bareme,ForceArray => 1,KeyAttr=> [ 'id' ]);

if($VERSION_BAREME ne $bar->{'version'}) {
    attention("Marking scale file version (".$bar->{'version'}.")",
	      "is old (here $VERSIN_BAREME) :",
	      "please make marking scale file again...");
    die("Marking scale file version mismatch : $VERSION_BAREME / ".$bar->{'version'});
}


# fichier des notes :

my $notes=eval { XMLin($fichnotes,
		       'ForceArray'=>1,
		       'KeyAttr'=>['id'],
		       ) };

if(!$notes) {
    debug "Error analysing marks file ".$fichnotes."\n";
    return($self);
}

$seuil=$notes->{'seuil'} if($notes->{'seuil'});

#################################

sub milieu_cercle {
    my $c=shift;
    my $x=0;
    my $y=0;
    for my $i (1..4) {
	$x+=$c->{$i}->{'x'};
	$y+=$c->{$i}->{'y'};
    }
    $x/=4;$y/=4;
    return($x,$y);
}

sub cercle_coors {
    my ($im,$c,$color)=@_;
    my ($x,$y)=milieu_cercle($c);
    $im->Draw(qw/primitive circle fill none/,
	      'strokewidth'=>$line_width,
	      'stroke'=>$color,
	      'points'=>sprintf("%.2f,%.2f %.2f,%.2f",
				$x,$y,
				$c->{1}->{'x'},$c->{1}->{'y'}),
	      );
}
    
sub croix_coors {
    my ($im,$c,$color)=@_;
    for my $i (1,2) {
	$im->Draw(qw/primitive line fill none/,
		  'strokewidth'=>$line_width,
		  'stroke'=>$color,
		  'points'=>sprintf("%.2f,%.2f %.2f,%.2f",
				    $c->{$i}->{'x'},$c->{$i}->{'y'},
				    $c->{$i+2}->{'x'},$c->{$i+2}->{'y'},
				    ),
		  );
    }
}

sub boite_coors {
    my ($im,$c,$color)=@_;
    my @pts="";
    for my $i (1..4) {
	push @pts,sprintf("%.2f,%.2f",
			  $c->{$i}->{'x'},$c->{$i}->{'y'},
			  );
    }
    $im->Draw(qw/primitive polygon fill none/,
	      'strokewidth'=>$line_width,
	      'stroke'=>$color,
	      'points'=>join(' ',@pts),
	      );
    
}

my $delta=1;

my @ids=$anl->ids();  

$delta=1/$#ids if($#ids>0);

 XMLFB: for my $id (@ids) {
     my $x=$anl->analyse($id,'scan'=>1);
     my $x_coche=$anl->analyse($id);
     print "Analyse $id...\n";

     my $scan=$x->{'src'};

     if($rep_projet) {
	 $scan=proj2abs({'%PROJET',$rep_projet,
			 '%PROJETS',$rep_projets,
			 '%HOME'=>$ENV{'HOME'},
		     },
			$scan);
     }
	 
     my $scan_f=$scan;

     $scan_f =~ s/\[[0-9]+\]$//;

     if(-f $scan_f) {

	 my $im=Graphics::Magick->new();

	 my ($x_ppem, $y_ppem, $ascender, $descender, $width, $height, $max_advance);

	 debug "Reading $scan";

	 $im->Read($scan);

	 $im->Set('pointsize'=>$im->Get('height')/$pointsize_rel);
	 $im->Set('quality',$qualite_jpg) if($qualite_jpg);

	 debug "Size Y : ".$im->Get('height');
	 debug "Pointsize : ".$im->Get('height')/$pointsize_rel;

	 print "Annotating $scan...\n";

	 my $idf=id2idf($id);
	 
	 my ($etud,$n_page)=get_ep($id);
	 
	 my %question=();

	 my $ne=$notes->{'copie'}->{$etud};

	 if(!$ne) {
	     print "*** no information for sheet $etud ***\n";
	     next XMLFB;
	 }
	 
	 # note finale sur la page avec le nom
	 
	 ($x_ppem, $y_ppem, $ascender, $descender, $width, $height, $max_advance) =
	     $im->QueryFontMetrics(text=>'TOTAL');
	 
	 if($n_page==1 || $x->{'nom'}) {
	     my $t=$ne->{'total'}->[0];
	     $im->Draw(qw/primitive text stroke red fill red strokewidth 1/,
		       'points'=>sprintf("%.1f,%.1f \'%s\'",
					 $x_ppem,0.7*$y_ppem+$ascender,
					 "TOTAL : "
					 .format_note($t->{'total'})."/".format_note($t->{'max'})
					 ." => ".$t->{'note'}." / ".$notes->{'notemax'}
					 ),
		       'antialias'=>'true',
		      ); 
	 }
	 
	 #########################################
	 # signalisation autour de chaque case :
	 
	 my $page=$x->{'case'};
	 my $page_coche=$x_coche->{'case'};
	 
       CASE: for my $k (keys %$page) {
	   my ($q,$r)=get_qr($k);
	   my $indic=$bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'indicative'};

	   next CASE if($indic && !$annote_indicatives);
	   
	   # a cocher ?
	   my $bonne=($bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'reponse'}->{$r}->{'bonne'} ? 1 : 0);

	   # cochee ?
	   my $cochee=($page_coche->{$k}->{'r'} > $seuil ? 1 :0);

	   my $sy=$symboles{"$bonne-$cochee"};
	   
	   if($sy->{type} eq 'circle') {
	       cercle_coors($im,$page->{$k}->{'coin'},$sy->{color});
	   } elsif($sy->{type} eq 'mark') {
	       croix_coors($im,$page->{$k}->{'coin'},$sy->{color});
	   } elsif($sy->{type} eq 'box') {
	       boite_coors($im,$page->{$k}->{'coin'},$sy->{color});
	   } elsif($sy->{type} eq 'none') {
	   } else {
	       debug "Unknown symbol type ($k): $sy->{type}";
	   }

	   # pour avoir la moyenne des coors pour marquer la note de
	   # la question

	   $question{$q}={} if(!$question{$q});
	   my @mil=milieu_cercle($page->{$k}->{'coin'});
	   $question{$q}->{'n'}++;
	   $question{$q}->{'x'}=$mil[0] 
	       if((!$question{$q}->{'x'}) || ($mil[0]<$question{$q}->{'x'}));
	   $question{$q}->{'y'}+=$mil[1];
	   
       }
	 
	 #########################################
	 # notes aux questions
	 
	 if($position ne 'none') {
	   QUEST: for my $q (keys %question) {
	       next QUEST if($bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'indicative'});
	       my $x;

	       my $nq=$ne->{'question'}->{$bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'titre'}};
	       
	       my $text=format_note($nq->{'note'})."/".format_note($nq->{'max'});
	       
	       ($x_ppem, $y_ppem, $ascender, $descender, $width, $height, $max_advance) =
		   $im->QueryFontMetrics(text=>$text);


	       if($position eq 'marge') {
		   $x=$ecart_marge*$x_ppem;
	       } elsif($position eq 'case') {
		   $x=$question{$q}->{'x'} - $ecart*$x_ppem - $width;
	       } else {
		   debug "Annotation : position invalide : $position";
		   $x=$ecart;
	       }
	       
	       # moyenne des y des cases de la question
	       my $y=$question{$q}->{'y'}/$question{$q}->{'n'} + $ascender - $height/2;
	       
	       $im->Draw(qw/primitive text stroke red fill red strokewidth 1/,
			 'points'=>sprintf("%.2f,%.2f \'%s\'",
					   $x,$y,$text),
			 );
	   }
	 }

	 # taille...
	 
	 $im->Resize('geometry'=>$taille_max) if($taille_max);

	 # fin
	 
	 $im->Write("$cr_dir/corrections/jpg/page-$idf.jpg");

     } else {
	 print "*** no scan $scan ***\n";
     }

     $avance->progres($delta);
 }

$avance->fin();


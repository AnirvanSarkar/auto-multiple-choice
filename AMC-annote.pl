#! /usr/bin/perl
#
# Copyright (C) 2009 Alexis Bienvenue <paamc@passoire.fr>
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

use encoding 'utf8';

$VERSION_BAREME=2;

my $cr_dir="";
my $rep_projet='';
my $fichnotes='';
my $fich_bareme='';

my $seuil=0.1;

my $an_saved='';

my $taille_max="1000x1500";
my $qualite_jpg="65";

my $debug='';

my $progress=1;
my $progress_id='';

GetOptions("cr=s"=>\$cr_dir,
	   "projet=s",\$rep_projet,
	   "an-saved=s"=>\$an_saved,
	   "bareme=s"=>\$fich_bareme,
	   "notes=s"=>\$fichnotes,
	   "debug=s"=>\$debug,
	   "taille-max=s"=>\$taille_max,
	   "qualite=s"=>\$qualite_jpg,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   );

set_debug($debug);

my $commandes=AMC::Exec::new("AMC-annote");
$commandes->signalise();

if(! -d $cr_dir) {
    attention("Repertoire de compte-rendus inexistant : $cr_dir");
    die "Repertoire inexistant : $cr_dir";
}
if(! -f $fichnotes) {
    attention("Fichier notes inexistant : $fichnotes");
    die "Fichier inexistant : $fichnotes";
}
if(! -f $fich_bareme) {
    attention("Fichier bareme inexistant : $fich_bareme");
    die "Fichier inexistant : $fich_bareme";
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
    debug "Reconstruction de la liste des analyses...";
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
    attention("La version du fichier bareme (".$bar->{'version'}.")",
	      "est differente de la version utilisee pour la notation ($VERSIN_BAREME) :",
	      "veuillez refabriquer le fichier bareme...");
    die("Version du fichier bareme differente : $VERSION_BAREME / ".$bar->{'version'});
}


# fichier des notes :

my $notes=eval { XMLin($fichnotes,
		       'ForceArray'=>1,
		       'KeyAttr'=>['id'],
		       ) };

if(!$notes) {
    debug "Erreur a l'analyse du fichier de notes ".$fichnotes."\n";
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
    my $c=shift;
    my ($x,$y)=milieu_cercle($c);
    return("-draw",sprintf("circle %.2f,%.2f %.2f,%.2f",
		   $x,$y,
		   $c->{1}->{'x'},$c->{1}->{'y'}));
}
    
sub croix_coors {
    my $c=shift;
    my @r=();
    for my $i (1,2) {
	push @r,"-draw",sprintf("line %.2f,%.2f %.2f,%.2f",
		    $c->{$i}->{'x'},$c->{$i}->{'y'},
		    $c->{$i+2}->{'x'},$c->{$i+2}->{'y'},
		    );
    }
    return(@r);
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
			 '%HOME'=>$ENV{'HOME'},
		     },
			$scan);
     }
	 
     if(-f $scan) {
	 
	 my @cmd=("convert",$scan,"-pointsize",60);
	 
	 print "Annotation de $scan...\n";

	 my $idf=$id;
	 $idf =~ s/[\+\/]+/-/g;
	 $idf =~ s/^-+//;
	 $idf =~ s/-+$//;
	 
	 my ($etud,$n_page)=get_ep($id);
	 
	 my %question=();

	 my $ne=$notes->{'copie'}->{$etud};

	 if(!$ne) {
	     print "*** pas d'informations pour copie $etud ***\n";
	     next XMLFB;
	 }
	 
	 # note finale sur la premiere page
	 
	 if($n_page==1) {
	     my $t=$ne->{'total'}->[0];
	     push @cmd,"-stroke","red",
	     "-fill","red","-draw","text 100,100 \'TOTAL : "
		 .$t->{'total'}."/".$t->{'max'}." => ".$t->{'note'}." / ".$notes->{'notemax'}
	     ."\'";
	 }
	 
	 #########################################
	 # signalisation autour de chaque case :
	 
	 my $page=$x->{'case'};
	 my $page_coche=$x_coche->{'case'};
	 
       CASE: for my $k (keys %$page) {
	   my ($q,$r)=get_qr($k);
	   next CASE if($bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'indicative'});
	   
	   # a cocher ?
	   my $bonne=$bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'reponse'}->{$r}->{'bonne'};

	   # cochee ?
	   my $cochee=($page_coche->{$k}->{'r'} > $seuil);
	   
	   if($bonne) {
	       push @cmd,"-strokewidth",2,"-stroke",($cochee ? "blue" : "red"),
	       croix_coors($page->{$k}->{'coin'});
	   } else {
	       if($cochee) {
		   push @cmd,"-fill","none","-strokewidth",2,"-stroke","red";
		   push @cmd,cercle_coors($page->{$k}->{'coin'});
	       }
	   }

	   # pour avoir la moyenne des coors pour marquer la note de
	   # la question

	   $question{$q}={} if(!$question{$q});
	   my @mil=milieu_cercle($page->{$k}->{'coin'});
	   $question{$q}->{'n'}++;
	   $question{$q}->{'x'}+=$mil[0];
	   $question{$q}->{'y'}+=$mil[1];
	   
       }
	 
	 #########################################
	 # notes aux questions
	 
       QUEST: for my $q (keys %question) {
	   next QUEST if($bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'indicative'});
	   my $x=60;
	   my $y=$question{$q}->{'y'}/$question{$q}->{'n'};
	   my $nq=$ne->{'question'}->{$bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'titre'}};

	   push @cmd,"-stroke","red","-fill","red",
	   "-strokewidth",1,"-draw",sprintf("text %.2f,%.2f \'%s\'",
					    $x,$y,$nq->{'note'}."/".$nq->{'max'});
       }

	 # taille et qualite...
	 
	 push @cmd,"-resize",$taille_max if($taille_max);
	 push @cmd,"-quality",$qualite_jpg if($qualite_jpg);

	 # fin
	 
	 push @cmd,"$cr_dir/corrections/jpg/page-$idf.jpg";

	 #print "Fabrication de page-$idf.jpg...\n";
	 $commandes->execute(@cmd);
     } else {
	 print "*** scan $scan introuvable ***\n";
     }

     $avance->progres($delta);
 }

$avance->fin();


__END__

./AMC-annote.pl --cr ~/Projets-QCM/p1-2008-12-02.bak/cr --bareme ~/Projets-QCM/p1-2008-12-02.bak/bareme.xml --notes ~/Projets-QCM/p1-2008-12-02.bak/notes.dat --an-saved ~/Projets-QCM/p1-2008-12-02.bak/an.storable --seuil 0.1

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

use XML::Simple;
use IO::File;
use XML::Writer;
use Getopt::Long;
use POSIX qw(ceil floor);
use AMC::Basic;
use AMC::ANList;
use AMC::Gui::Avancement;

use encoding 'utf8';

$VERSION_BAREME=2;

my $cmd_pid='';

sub catch_signal {
    my $signame = shift;
    print "*** AMC-note : signal $signame, je tue $cmd_pid...\n";
    kill 9,$cmd_pid if($cmd_pid);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

my $cr_dir="";
my $bareme="";
my $association="-";
my $seuil=0.1;
my $fichnotes='-';
my $annotation_copies='';

my $notemax=20;
my $grain='0.5';
my $arrondi='';
my $delimiteur=',';
my $encodage_interne='UTF-8';
my $an_saved='';

my $taille_max="1000x1500";
my $qualite_jpg="65";

my $progres=1;
my $progres_id='';

my $debug='';

GetOptions("cr=s"=>\$cr_dir,
	   "an-saved=s"=>\$an_saved,
	   "bareme=s"=>\$bareme,
	   "seuil=s"=>\$seuil,
	   "debug!"=>\$debug,
	   "copies!"=>\$annotation_copies,
	   "o=s"=>\$fichnotes,
	   "grain=s"=>\$grain,
	   "arrondi=s"=>\$type_arrondi,
	   "notemax=s"=>\$notemax,
	   "encodage-interne=s"=>\$encodage_interne,
	   "progression-id=s"=>\$progres_id,
	   "progression=s"=>\$progres,
	   );

$grain =~ s/,/./;

sub arrondi_inf {
    my $x=shift;
    return(floor($x));
}

sub arrondi_central {
    my $x=shift;
    return(floor($x+0.5));
}

sub arrondi_sup {
    my $x=shift;
    return(ceil($x));
}

my %fonction_arrondi=(-1=>\&arrondi_inf,0=>\&arrondi_central,1=>\&arrondi_sup,
		      i=>\&arrondi_inf,n=>\&arrondi_central,s=>\&arrondi_sup);

if($type_arrondi) {
    for my $k (keys %fonction_arrondi) {
	if($type_arrondi =~ /^$k/i) {
	    $arrondi=$fonction_arrondi{$k};
	}
    }
}

sub commande_externe {
    my @c=@_;

    print "Commande : ".join(' ',@c)."\n" if($debug);

    $cmd_pid=fork();
    if($cmd_pid) {
	waitpid($cmd_pid,0);
    } else {
	exec(@c);
    }

}

if(! -d $cr_dir) {
    attention("Repertoire de compte-rendus inexistant : $cr_dir");
    die "Repertoire inexistant : $cr_dir";
}
if(! -f $bareme) {
    attention("Fichier bareme inexistant : $bareme");
    die "Fichier inexistant : $bareme";
}
if($grain<=0) {
    attention("Le grain doit etre strictement positif (grain=$grain)");
    die "Grain $grain<=0";
}

my $avance=AMC::Gui::Avancement::new($progres,'id'=>$progres_id);

my $bar=XMLin($bareme,ForceArray => 1,KeyAttr=> [ 'id' ]);

if($VERSION_BAREME ne $bar->{'version'}) {
    attention("La version du fichier bareme (".$bar->{'version'}.")",
	      "est differente de la version utilisee pour la notation ($VERSIN_BAREME) :",
	      "veuillez refabriquer le fichier bareme...");
    die("Version du fichier bareme differente : $VERSION_BAREME / ".$bar->{'version'});
}

opendir(DIR, $cr_dir) || die "can't opendir $cr_dir: $!";
my @xmls = grep { /\.xml$/ && -f "$cr_dir/$_" } readdir(DIR);
closedir DIR;

sub degroupe {
    my ($s,%r)=(@_);
    for my $i (split(/,+/,$s)) {
	if($i =~ /^([^=]+)=(-?[0-9\.]+)$/) {
	    $r{$1}=$2;
	} else {
	    die "Erreur de syntaxe pour le bareme : $s";
	}
    }
    return(%r);
}

my %bons=();
my %qidsh=();

for my $etu (keys %{$bar->{'etudiant'}}) {
    my $baretu=$bar->{'etudiant'}->{$etu};
    $bons{'max'.$etu}={};
    my $bonsetu=$bons{'max'.$etu};
    for my $q (keys %{$baretu->{'question'}}) {
	$bonsetu->{$q}={};
	for my $r (keys %{$baretu->{'question'}->{$q}->{'reponse'}}) {
	    $bonsetu->{$q}->{$r}=[$baretu->{'question'}->{$q}->{'reponse'}->{$r}->{'bonne'},1];
	}
    }
}

# perl -e 'use XML::Simple;use Data::Dumper;$lay=XMLin("test-bareme.xml",ForceArray => 1,KeyAttr=> [ "id" ]);print Dumper($lay);'

%page_lue=();

# perl -e 'use XML::Simple;use Data::Dumper;$lay=XMLin("points-cr/analyse-manuelle-100-1-31.xml",ForceArray => 1,KeepRoot=>1,KeyAttr=> [ "id" ]);print Dumper($lay);'

sub action {
    my ($id,$aa,$pbons,$bar)=(@_);
    my $page=$aa->{'case'};
    my ($etud,undef)=get_ep($id);

    $pbons->{$etud}={} if(!$pbons->{$etud});

    for my $k (sort { $a <=> $b } (keys %$page)) {
	my ($q,$r)=get_qr($k);
	$qidsh{$q}=1;
	
	my $coche=($page->{$k}->{'r'}>$seuil ? 1 : 0);
	my $ok=($coche == $bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'reponse'}->{$r}->{'bonne'} ? 1 : 0);
	print "Question $q reponse $r : ".($coche ? "X" : "O")." -> $ok\n" if($debug);
	$pbons->{$etud}->{$q}={} if(!$pbons->{$etud}->{$q});
	$pbons->{$etud}->{$q}->{$r}=[$coche,$ok];
    }
}

$avance->progres(0.05);

my $anl;

if($an_saved) {
    #print "CR=$cr_dir\nSAVED=$an_saved\n";
    $anl=AMC::ANList::new($cr_dir,
			  'saved'=>$an_saved,
			  'action'=>'',
			  );
    my @ids=$anl->ids();
    my $delta=0.75;
    $delta/=(1+$#ids) if($#ids>=0);
    for my $id (@ids) {
	action($id,$anl->analyse($id),\%bons,$bar);
	$avance->progres($delta);
    }
} else {
    $anl=AMC::ANList::new($cr_dir,
			  'saved'=>'',
			  'action'=>[\&action,\%bons,$bar]
			  );
}

#print Dumper(\%bons)."\n";

print "Sources :\n";
for my $id ($anl->ids()) {
    print "ID=$id : ".$anl->filename($id)
    .($anl->attribut($id,'manuel') ? " (manuel)" : "")."\n";
}
print "\n";

#print Dumper(\%bons);

my %note_question=();

my @qids=sort { $a <=> $b } (keys %qidsh);

my $un_etud=(keys %{$bar->{'etudiant'}})[0];

sub titre_q {
    return($bar->{'etudiant'}->{$un_etud}->{'question'}->{shift()}->{'titre'});
}

my $output=new IO::File($fichnotes,
			">:encoding($encodage_interne)");
if(! $output) {
    die "Impossible d'ouvrir $fichnotes : $!";
}

my $writer = new XML::Writer(OUTPUT=>$output,
			     ENCODING=>$encodage_interne,
			     DATA_MODE=>1,
			     DATA_INDENT=>2);

$writer->xmlDecl($encodage_interne);
$writer->startTag('notes',
		  'seuil'=>$seuil,
		  'notemax'=>$notemax,
		  'arrondi'=>$type_arrondi,
		  'grain'=>$grain);

my $somme_notes=0;
my $n_notes=0;
my %les_codes=();

my @a_calculer=((grep { /^max/ } (keys %bons)),
		sort { $a <=> $b } (grep { ! /^max/ } (keys %bons)));

my $delta=0.19;
$delta/=(1+$#a_calculer) if($#a_calculer>=0);

for my $etud (@a_calculer) {

    my $refetud=$etud;
    $refetud =~ s/^max//;

    $vrai=$etud !~ /^max/;

    if($vrai) {
	$writer->startTag('copie',
			  'id'=>$etud);
    }

    $note_question{$etud}={};

    my $total=0;
    my $n_col=3;
    my %codes=();

    for my $q (@qids) {

	$n_col++;

	if($bons{$etud}->{$q}) {

	    $barq=$bar->{'etudiant'}->{$refetud}->{'question'}->{$q};

	    $xx='';
	    $raison='';
	    
	    $n_ok=0;
	    $n_coche=0;
	    $id_coche=-1;
	    $n_tous=0;
	    
	    for (keys %{$bons{$etud}->{$q}}) {
		$n_ok+=$bons{$etud}->{$q}->{$_}->[1];
		$n_coche+=$bons{$etud}->{$q}->{$_}->[0];
		$id_coche=$_ if($bons{$etud}->{$q}->{$_}->[0]);
		$n_tous++;
	    }

	    print "{$n_ok/$n_tous,$n_coche,$id_coche}" if($debug);
		
	    # baremes :

	    # e=erreur logique dans les réponses
	    # b=bonne réponse
	    # m=mauvaise réponse
	    # v=pas de réponse sur toute la question
	    # p=note plancher
	    # d=décalage ajouté avant plancher
	    # haut=on met le max a cette valeur et on enleve 1 pt par faute (MULT)
	    
	    if($barq->{'multiple'}) {
		# QUESTION MULTIPLE

		my @rep=(keys %{$bons{$etud}->{$q}});

		$xx=0;
		
		%b_q=degroupe($barq->{'bareme'},
			      'e'=>0,'b'=>1,'m'=>0,'v'=>0,'d'=>0);

		if($b_q{'haut'}) {
		    my @rep_pleine=grep { $_ !=0 } @rep; # on enleve " aucune "
		    $b_q{'d'}=$b_q{'haut'}-(1+$#rep_pleine);
		    $b_q{'p'}=0 if(!defined($b_q{'p'}));
		    print "Q=$q REPS=".join(',',@rep)." HAUT=$b_q{'haut'} D=$b_q{'d'} P=$b_q{'p'}\n" if($debug);
		} else {
		    $b_q{'p'}=-100 if(!defined($b_q{'p'}));
		}
		
		if($n_coche !=1 && $bons{$etud}->{$q}->{0}->[0]) {
		    # coche deux dont "aucune des precedentes"
		    $xx=$b_q{'e'};
		    $raison='E';
		} elsif($n_coche==0) {
		    # aucune cochee
		    $xx=$b_q{'v'};
		    $raison='V';
		} else {
		    for(@rep) {
			if($_ != 0) {
			    $code=($bons{$etud}->{$q}->{$_}->[1] ? "b" : "m");
			    my %b_qspec=degroupe($barq->{'reponse'}->{$_}->{'bareme'},%b_q);
			    print "[$b_qspec{$code}]" if($debug);
			    $xx+=$b_qspec{$code};
			}
		    }
		}

		# decalage
		$xx+=$b_q{'d'} if($raison !~ /^[VE]/i);

		# note plancher
		if($xx<$b_q{'p'}) {
		    $xx=$b_q{'p'};
		    $raison='P';
		}
	    } else {
		# QUESTION SIMPLE
		%b_q=degroupe($barq->{'bareme'},
			      'e'=>0,'b'=>1,'m'=>0,'v'=>0,'auto'=>-1);

		if($n_coche==0) {
		    $xx=$b_q{'v'};
		    $raison='V';
		} elsif($n_coche>1) {
		    $xx=$b_q{'e'};
		    $raison='E';
		} else {
		    $sb=$barq->{'reponse'}->{$id_coche}->{'bareme'};
		    if($sb ne '') {
			$xx=$sb; 
		    } else {
			$xx=($b_q{'auto'}>-1
			     ? $id_coche+$b_q{'auto'}-1
			     : ($n_ok==$n_tous ? $b_q{'b'} : $b_q{'m'}));
		    }
		}

	    }

	    if($barq->{'indicative'} && !$vrai) {
		$xx=1;
	    }

	    $note_question{$etud}->{$q}=$xx;

	    if(!$barq->{'indicative'}) {
		$total+=$xx;
	    }
	    
	    print $raison if($debug);
	    
	    if($vrai) {
		my $tit=titre_q($q);
		if($tit =~ /^(.*)\.([0-9]+)$/) {
		    $codes{$1}->{$2}=$xx;
		}

		$writer->emptyTag('question',
				  'id'=>$tit,
				  'note'=>$xx,
				  'raison'=>$raison,
				  'indicative'=>$barq->{'indicative'},
				  'max'=>$note_question{'max'.$etud}->{$q},
				  );
		$note_question{'somme'}->{$q}+=$xx;
		$note_question{'nb.somme'}->{$q}++;
		$note_question{'max.somme'}->{$q}+=$note_question{'max'.$etud}->{$q};
	    }
	}
    }
    $note_question{$etud}->{'total'}=$total;
    if($vrai) {
	my $x=$notemax/$grain*$total/$note_question{'max'.$etud}->{'total'};
	$x=&$arrondi($x) if($arrondi);
	$x*=$grain;

	$n_notes++;
	$somme_notes+=$x;

	$writer->emptyTag('total',
			  'total'=>$total,
			  'max'=>$note_question{'max'.$etud}->{'total'},
			  'note'=>$x,
			  );

	for my $k (keys %codes) {
	    my @i=(keys %{$codes{$k}});
	    if($#i>0) {
		my $v=join('',map { $codes{$k}->{$_} }
			   sort { $b <=> $a } (@i));
		$les_codes{$k}->{$v}++;
		$writer->dataElement('code',
				     $v,
				     'id'=>$k);
	    }
	}

	$writer->endTag('copie');
    }

    $avance->progres($delta);
}

# ligne du maximum

$writer->startTag('copie',id=>'max');

my %maximums=();
my $total=0;
for my $q (@qids) {
    my $max=0;
    for my $etud (grep { ! /^max/ } (keys %bons)) {
	$max=$note_question{'max'.$etud}->{$q} 
	if($note_question{'max'.$etud}->{$q}>$max);
    }
    $writer->emptyTag('question',
		      'id'=>titre_q($q),
		      'note'=>$max);
    $total+=$max;
}

$writer->emptyTag('total',
		  'total'=>$total,
		  'max'=>$total,
		  'note'=>$notemax,
		  );
$writer->endTag('copie');

# ligne des moyennes

$writer->startTag('copie',id=>'moyenne');

my %maximums=();
for my $q (@qids) {
    $writer->emptyTag('question',
		      'id'=>titre_q($q),
		      'n'=>$note_question{'nb.somme'}->{$q},
		      'note'=>$note_question{'somme'}->{$q}/$note_question{'nb.somme'}->{$q},
		      'max'=>$note_question{'max.somme'}->{$q}/$note_question{'nb.somme'}->{$q},
		      );
}

$writer->emptyTag('total',
		  'total'=>$somme_notes,
		  'max'=>$notemax,
		  'note'=>$somme_notes/$n_notes,
		  );
$writer->endTag('copie');

# les codes rencontres

for my $k (keys %les_codes) {
    $writer->startTag('code','id'=>$k);
    for (keys %{$les_codes{$k}}) {
	$writer->dataElement('valeur',$_,
			     'nombre'=>$les_codes{$k}->{$_});
    }
    $writer->endTag('code');
}

# moyenne

$writer->dataElement('moyenne',$somme_notes/$n_notes);

# fin

$writer->endTag('notes');
    
$writer->end();
$output->close();

$avance->fin();

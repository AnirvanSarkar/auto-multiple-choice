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
use IO::File;
use XML::Writer;
use Getopt::Long;
use POSIX qw(ceil floor);
use AMC::Basic;
use AMC::ANList;
use AMC::Gui::Avancement;

use encoding 'utf8';

$VERSION_BAREME=2;
$VERSION_NOTES=2;

my $cr_dir="";
my $bareme="";
my $association="-";
my $seuil=0.1;
my $fichnotes='-';
my $annotation_copies='';

my $note_plancher='';
my $note_parfaite=20;
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
	   "debug=s"=>\$debug,
	   "copies!"=>\$annotation_copies,
	   "o=s"=>\$fichnotes,
	   "grain=s"=>\$grain,
	   "arrondi=s"=>\$type_arrondi,
	   "notemax=s"=>\$note_parfaite,
	   "notemin=s"=>\$note_plancher,
	   "encodage-interne=s"=>\$encodage_interne,
	   "progression-id=s"=>\$progres_id,
	   "progression=s"=>\$progres,
	   );

set_debug($debug);

$grain =~ s/,/./;
$note_plancher =~ s/,/./;
$note_parfaite =~ s/,/./;

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

my %fonction_arrondi=('i'=>\&arrondi_inf,'n'=>\&arrondi_central,'s'=>\&arrondi_sup);

if($type_arrondi) {
    for my $k (keys %fonction_arrondi) {
	if($type_arrondi =~ /^$k/i) {
	    $arrondi=$fonction_arrondi{$k};
	}
    }
}

if(! -d $cr_dir) {
    attention("No CR directory: $cr_dir");
    die "No CR directory: $cr_dir";
}
if(! -f $bareme) {
    attention("No marking scale file: $bareme");
    die "No marking scale file: $bareme";
}

if($grain<=0) {
    $grain=1;
    $arrondi='';
    $type_arrondi='';
    debug("Nonpositive grain: rounding off");
}

my $avance=AMC::Gui::Avancement::new($progres,'id'=>$progres_id);

my $bar=XMLin($bareme,ForceArray => 1,KeyAttr=> [ 'id' ]);

if($VERSION_BAREME ne $bar->{'version'}) {
    attention("Marking scale file version (".$bar->{'version'}.")",
	      "is too old (here $VERSIN_BAREME):",
	      "please make marking scale file again...");
    die("Marking scale file version mismatch: $VERSION_BAREME / ".$bar->{'version'});
}

opendir(DIR, $cr_dir) || die "can't opendir $cr_dir: $!";
my @xmls = grep { /\.xml$/ && -f "$cr_dir/$_" } readdir(DIR);
closedir DIR;

sub degroupe {
    my ($s,$defaut,$vars)=(@_);
    my %r=(%$defaut);
    for my $i (split(/,+/,$s)) {
	$i =~ s/^\s+//;
	$i =~ s/\s+$//;
	if($i =~ /^([^=]+)=([-+*\/0-9a-zA-Z\.\(\)?:|&=<>!\s]+)$/) {
	    $r{$1}=$2;
	} else {
	    die "Marking scale syntax error: $i within $s" if($i);
	}
    }
    # remplacement des variables et evaluation :
    for my $k (keys %r) {
	my $v=$r{$k};
	for my $vv (keys %$vars) {
	    $v=~ s/\b$vv\b/$vars->{$vv}/g;
	}
	die "Syntax error (unknown variable): $v" if($v =~ /[a-z]/i);
	my $calc=eval($v);
	die "Syntax error (operation) : $v" if(!defined($calc));
	debug "Evaluation : $r{$k} => $calc" if($r{$k} ne $calc);
	$r{$k}=$calc;
    }
    #
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
	    $bonsetu->{$q}->{$r}=[$baretu->{'question'}->{$q}->{'reponse'}->{$r}->{'bonne'},1,$baretu->{'question'}->{$q}->{'reponse'}->{$r}->{'bonne'}];
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
	my $bonne=($bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'reponse'}->{$r}->{'bonne'} ? 1 : 0);
	my $ok=($coche == $bonne ? 1 : 0);
	debug "Student $etud Q $q A $r : ".($bonne ? "G" : "B")." "
	    .($coche ? "X" : "O")." -> ".($ok ? "OK" : "NO");
	$pbons->{$etud}->{$q}={} if(!$pbons->{$etud}->{$q});
	$pbons->{$etud}->{$q}->{$r}=[$coche,$ok,$bonne];
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

#debug Dumper(\%bons)."\n";

print "Sources :\n";
for my $id ($anl->ids()) {
    print "ID=$id : ".$anl->filename($id)
    .($anl->attribut($id,'manuel') ? " (manual)" : "")."\n";
}
print "\n";

my %note_question=();

my @qids=sort { $a <=> $b } (keys %qidsh);

my $un_etud=(keys %{$bar->{'etudiant'}})[0];

sub titre_q {
    return($bar->{'etudiant'}->{$un_etud}->{'question'}->{shift()}->{'titre'});
}

my $output=new IO::File($fichnotes,
			">:encoding($encodage_interne)");
if(! $output) {
    die "Error opening $fichnotes: $!";
}

my $writer = new XML::Writer(OUTPUT=>$output,
			     ENCODING=>$encodage_interne,
			     DATA_MODE=>1,
			     DATA_INDENT=>2);

$writer->xmlDecl($encodage_interne);
$writer->startTag('notes',
		  'version'=>$VERSION_NOTES,
		  'seuil'=>$seuil,
		  'notemin'=>$note_plancher,
		  'notemax'=>$note_parfaite,
		  'arrondi'=>$type_arrondi,
		  'grain'=>$grain);

my $somme_notes=0;
my $n_notes=0;
my %les_codes=();
my %indicatives=();

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

    my $bar_def=$bar->{'etudiant'}->{'defaut'}->{'question'};

    for my $q (@qids) {

	$n_col++;

	if($bons{$etud}->{$q}) {

	    my $vars={'NB'=>0,'NM'=>0,'NBC'=>0,'NMC'=>0};

	    $barq=$bar->{'etudiant'}->{$refetud}->{'question'}->{$q};

	    $xx='';
	    $raison='';
	    
	    $n_ok=0;
	    $n_coche=0;
	    $id_coche=-1;
	    $n_tous=0;
	    
	    my @rep=(keys %{$bons{$etud}->{$q}});
	    my @rep_pleine=grep { $_ !=0 } @rep; # on enleve " aucune "

	    my $cochees=join(";",map { $bons{$etud}->{$q}->{$_}->[0] }
			     sort { ($a==0 || $b==0 ? $b <=> $a : $a <=> $b) } (@rep));

	    for (@rep) {
		$n_ok+=$bons{$etud}->{$q}->{$_}->[1];
		$n_coche+=$bons{$etud}->{$q}->{$_}->[0];
		$id_coche=$_ if($bons{$etud}->{$q}->{$_}->[0]);
		$n_tous++;
	    }

	    for(@rep_pleine) {
		debug "REP[$_]<=".join(',',@{$bons{$etud}->{$q}->{$_}});
		my $bn=($bons{$etud}->{$q}->{$_}->[2] ? 'B' : 'M');
		my $co=($bons{$etud}->{$q}->{$_}->[0] ? 'C' : '');
		$vars->{'N'.$bn}++;
		$vars->{'N'.$bn.$co}++ if($co);
	    }

	    # baremes :

	    # e=erreur logique dans les reponses
	    # b=bonne reponse
	    # m=mauvaise reponse
	    # v=pas de reponse sur toute la question
	    # p=note plancher
	    # d=decalage ajoute avant plancher
	    # haut=on met le max a cette valeur et on enleve 1 pt par faute (MULT)
	    
	    # variables possibles dans la specification du bareme
	    $vars->{'N'}=(1+$#rep_pleine);
	    $vars->{'IMULT'}=($barq->{'multiple'} ? 1 : 0);
	    $vars->{'IS'}=($barq->{'multiple'} ? 0 : 1);

	    if($barq->{'multiple'}) {
		# QUESTION MULTIPLE

		$xx=0;
		
		%b_q=degroupe($bar_def->{'M'}->{'bareme'}
			      .",".$barq->{'bareme'},
			      {'e'=>0,'b'=>1,'m'=>0,'v'=>0,'d'=>0},
			      $vars);

		if($b_q{'haut'}) {
		    $b_q{'d'}=$b_q{'haut'}-(1+$#rep_pleine);
		    $b_q{'p'}=0 if(!defined($b_q{'p'}));
		    debug "Q=$q REPS=".join(',',@rep)." HAUT=$b_q{'haut'} D=$b_q{'d'} P=$b_q{'p'}";
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
			    my %b_qspec=degroupe($barq->{'reponse'}->{$_}->{'bareme'},
						 \%b_q,$vars);
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
		%b_q=degroupe($bar_def->{'S'}->{'bareme'}
			      .",".$barq->{'bareme'},
			      {'e'=>0,'b'=>1,'m'=>0,'v'=>0,'auto'=>-1},
			      $vars);

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

	    if(exists($b_q{'MAX'}) && !$vrai) {
		$xx=$b_q{'MAX'};
	    }

	    $note_question{$etud}->{$q}=$xx;
	    
	    if($barq->{'indicative'}) {
		$indicatives{$q}=1;
	    } else {
		$total+=$xx;
	    }
	    
	    if($vrai) {
		my $tit=titre_q($q);
		if($tit =~ /^(.*)\.([0-9]+)$/) {
		    $codes{$1}->{$2}=$xx;
		}
		
		my $notemax=$note_question{'max'.$etud}->{$q};
		$writer->emptyTag('question',
				  'id'=>$tit,
				  'cochees'=>$cochees,
				  'note'=>$xx,
				  'raison'=>$raison,
				  'indicative'=>$barq->{'indicative'},
				  'max'=>$notemax,
				  );
		$note_question{'somme'}->{$q}+=$xx;
		$note_question{'nb.somme'}->{$q}++;
		$note_question{'max.somme'}->{$q}+=$notemax;
	    }
	}
    }
    $note_question{$etud}->{'total'}=$total;
    if($vrai) {
	# calcul de la note finale --

	# application du grain et de la note max
	my $x;
	if($note_parfaite>0) {
	    $x=$note_parfaite/$grain*$total/$note_question{'max'.$etud}->{'total'};
	} else {
	    $x=$total/$grain;
	}
	$x=&$arrondi($x) if($arrondi);
	$x*=$grain;

	# plancher

	if($note_plancher ne '' && $note_plancher !~ /[a-z]/i) {
	    $x=$note_plancher if($x<$note_plancher);
	} 

	#--

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
		      'note'=>$max,
		      'indicative'=>$indicatives{$q},
		      );
    $total+=$max;
}

$writer->emptyTag('total',
		  'total'=>$total,
		  'max'=>$total,
		  'note'=>$note_parfaite,
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
		  'max'=>$note_parfaite,
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

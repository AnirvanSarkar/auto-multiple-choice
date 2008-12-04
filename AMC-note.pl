#! /usr/bin/perl
#
# Copyright (C) 2008 Alexis Bienvenue <paamc@passoire.fr>
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
use AMC::ANList;

use encoding 'utf8';

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
my $grain='0,5';
my $arrondi='.INF';
my $delimiteur=',';
my $encoding='UTF-8';

my $debug='';

GetOptions("cr=s"=>\$cr_dir,
	   "bareme=s"=>\$bareme,
	   "association=s"=>\$association,
	   "seuil=s"=>\$seuil,
	   "debug!"=>\$debug,
	   "copies!"=>\$annotation_copies,
	   "o=s"=>\$fichnotes,
	   "grain=s"=>\$grain,
	   "arrondi=s"=>\$type_arrondi,
	   "notemax=s"=>\$notemax,
	   "delimiteur=s"=>\$delimiteur,
	   "encoding=s"=>\$encoding,
	   );

my %fonction_arrondi=(-1=>'.INF',0=>'',1=>'.SUP',
		      i=>'.INF',n=>0,s=>'.SUP');

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

sub office_nombre {
    my $n=shift;
    if($n =~ /^-?[0-9]+[.,][0-9]+$/) {
	$n =~ s/[.,]/$delimiteur/;
    }
    return($n);
}

my $bar=XMLin($bareme,ForceArray => 1,KeyAttr=> [ 'id' ]);

die "Repertoire inexistant : $cr_dir" if(! -d $cr_dir);
die "Fichier inexistant : $bareme" if(! -f $bareme);

$association="$cr_dir/association.xml" if($association eq '-');

if(! -f $association) {
    print "Fichier association inexistant : $f\n";
    $association='';
}

my $ass='';

if($association) {
    $ass=XMLin($association,KeyAttr=> [ 'id' ],ForceArray=>['etudiant']);
    my @k=keys %{$ass->{'etudiant'}};
    print "Associations : ".(1+$#k). " etudiants\n";
    #print Dumper($ass);
}

opendir(DIR, $cr_dir) || die "can't opendir $cr_dir: $!";
my @xmls = grep { /\.xml$/ && -f "$cr_dir/$_" } readdir(DIR);
closedir DIR;

sub get_qr {
    my $k=shift;
    if($k =~ /([0-9]+)\.([0-9]+)/) {
	return($1,$2);
    } else {
	die "Format de cle inconnu : $k";
    }
}

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

my %bons=('max'=>{});
my %qidsh=();

for my $q (keys %{$bar->{'question'}}) {
    $bons{'max'}->{$q}={};
    for my $r (keys %{$bar->{'question'}->{$q}->{'reponse'}}) {
	$bons{'max'}->{$q}->{$r}=[$bar->{'question'}->{$q}->{'reponse'}->{$r}->{'bonne'},1];
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
	my $ok=($coche == $bar->{'question'}->{$q}->{'reponse'}->{$r}->{'bonne'} ? 1 : 0);
	print "Question $q reponse $r : ".($coche ? "X" : "O")." -> $ok\n" if($debug);
	$pbons->{$etud}->{$q}={} if(!$pbons->{$etud}->{$q});
	$pbons->{$etud}->{$q}->{$r}=[$coche,$ok];
    }
}

my $anl=AMC::ANList::new($cr_dir,'action'=>[\&action,\%bons,$bar]);

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

my $un_etud=(keys %{$ass->{'etudiant'}})[0];
my @heads=grep { ! /^(content|id)$/ } (keys %{$ass->{'etudiant'}->{$un_etud}});

print "entetes supplementaires : ".join(' ',@heads)."\n";

print ("-" x 40);
print "\n";

open(NOTES,">:encoding($encoding)",$fichnotes) || die "Probleme a l'ecriture de $fichnotes : $!";

print NOTES "NOM\tNOTE\t";
print NOTES "ID\t".join("\t",map { $bar->{'question'}->{$_}->{'titre'} } @qids)."TOTAL\tMAX\t";
for (@heads) { print NOTES "\t$_"; }
print NOTES "\n";

%lesnoms=();

if($ass) {
    for my $etud (keys %bons) {
	$lesnoms{$etud}=$ass->{'etudiant'}->{$etud}->{'content'};
    }
}
for my $id ($anl->ids()) {
    if($id =~ /\+([0-9]+)\//) {
	my $etud=$1;
	$lesnoms{$etud}=$anl->attribut($id,'nometudiant')
	    if($anl->attribut($id,'nometudiant'));
    }
}

sub office_cle {
    my ($n,$y)=@_;
    my $c='';
    my $d=int(($n-1)/26);
    $n=($n-1) % 26;
    $c.=chr(ord("A")+$d-1) if($d>0);
    $c.=chr(ord("A")+$n);
    $c.=$y;
    return($c);
}

$n_ligne=1;
$cle_max=office_cle(3+$#qids+1+2);
$cle_total=office_cle(3+$#qids+1+1);
$cle_debut=office_cle(3+1);
$cle_fin=office_cle(3+$#qids+1);

for my $etud (sort { $lesnoms{$a} cmp $lesnoms{$b} ||
		     $a <=> $b } (keys %bons)) {
    $n_ligne++;

    print NOTES $lesnoms{$etud}."\t";
    print NOTES "=ARRONDI$arrondi($notemax*$cle_total$n_ligne/$cle_max$n_ligne/$grain)*$grain\t";
    print NOTES $etud."\t";

    $note_question{$etud}={};

    my $total=0;

    for my $q (@qids) {

	if($bons{$etud}->{$q}) {

	    $barq=$bar->{'question'}->{$q};

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
	    
	    if($barq->{'multiple'}) {
		# QUESTION MULTIPLE

		$xx=0;
		
		%b_q=degroupe($barq->{'bareme'},e=>0,b=>1,m=>0,v=>0,p=>-100,d=>0);
		
		if($n_coche !=1 && $bons{$etud}->{$q}->{0}->[0]) {
		    # coche deux dont "aucune des precedentes"
		    $xx=$b_q{'e'};
		    $raison='E';
		} elsif($n_coche==0) {
		    # aucune cochee
		    $xx=$b_q{'v'};
		    $raison='V';
		} else {
		    for(keys %{$bons{$etud}->{$q}}) {
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
		%b_q=degroupe($barq->{'bareme'},e=>0,b=>1,m=>0,v=>0);

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
			$xx=($n_ok==$n_tous ? $b_q{'b'} : $b_q{'m'});
		    }
		}
	    }

	    $note_question{$etud}->{$q}=$xx;
	    $note_question{$etud}->{'tmax'}+=$note_question{'max'}->{$q};
	    $total+=$xx;
	    
	    print NOTES office_nombre($xx);
	    
	    print $raison if($debug);
	    print NOTES "\t";
	} else {
	    print NOTES "-\t";
	}
    }
    $note_question{$etud}->{'total'}=$total;
    print NOTES "=SOMME($cle_debut$n_ligne:$cle_fin$n_ligne)\t";
#    print NOTES office_nombre($total)."\t";
    print NOTES office_nombre($note_question{$etud}->{'tmax'});
    for(@heads) { print NOTES "\t".$ass->{'etudiant'}->{$etud}->{$_}; }
    print NOTES "\n";
}

# ligne des moyennes :

print NOTES "Moyenne\t";
print NOTES "=MOYENNE(".office_cle(2,3).":".office_cle(2,$n_ligne).")\t"; # note
print NOTES "moy\t";
print NOTES join("\t",map { "=MOYENNE(".office_cle(4+$_,3).":".office_cle(4+$_,$n_ligne).")/".office_cle(4+$_,2) } (0..$#qids))."\t";
print NOTES "\t"; # total
for(@heads) { print NOTES "\t"; }
print NOTES "\n"; # max

##########################################################################

# annotation des copies...

##########################################################################

if(!$annotation_copies) {
    print "Pas d'annotation demandee...\n";
    exit(0);
}

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
    

 XMLFB: for my $id ($anl->ids()) {
     my $x=$anl->analyse($id);
     print "Analyse $id...\n";

     my $scan=$x->{'src'};
	 
     if(-f $scan) {
	 
	 my @cmd=("convert",$scan,"-pointsize",60);
	 
	 print "Annotation de $scan...\n";
	 
	 my $idf=$id;
	 $idf =~ s/[\+\/]+/-/g;
	 $idf =~ s/^-+//;
	 $idf =~ s/-+$//;
	 
	 my ($etud,$n_page)=get_ep($id);
	 
	 my %question=();
	 
	 # note finale
	 
	 if($n_page==1) {
	     push @cmd,"-stroke","red",
	     "-fill","red","-draw","text 100,100 \'TOTAL : "
		 .$note_question{$etud}->{'total'}."/".$note_question{$etud}->{'tmax'}
	     ."\'";
	 }
	 
	 # cercles autour des mauvaises reponses
	 
	 my $page=$x->{'case'};
	 for my $k (keys %$page) {
	     my ($q,$r)=get_qr($k);
	     
	     #print "Case $q.$r\n";
	     
	     if($bar->{'question'}->{$q}->{'reponse'}->{$r}->{'bonne'}) {
		 push @cmd,"-strokewidth",2,"-stroke","blue",
		 croix_coors($page->{$k}->{'coin'});
	     }
	     
	     $question{$q}={} if(!$question{$q});
	     my @mil=milieu_cercle($page->{$k}->{'coin'});
	     $question{$q}->{'n'}++;
	     $question{$q}->{'x'}+=$mil[0];
	     $question{$q}->{'y'}+=$mil[1];
	     
	     my @bb=@{$bons{$etud}->{$q}->{$r}};
	     
	     if(!$bb[1]) {
		 # mauvaise reponse
		 if($bar->{'question'}->{$q}->{'multiple'} ||
		    $bb[0]) {
		     push @cmd,"-fill","none","-strokewidth",2,"-stroke","red";
		     #.($bb[0] ? "red" : "green");
		     push @cmd,cercle_coors($page->{$k}->{'coin'});
		 }
	     }
	 }
	 
	 # notes aux questions
	 
	 for my $q (keys %question) {
	     my $x=60;
	     my $y=$question{$q}->{'y'}/$question{$q}->{'n'};
	     #print "MARQUE : ($x,$y) ".$note_question{$etud}->{$q}."\n";
	     push @cmd,"-stroke","red","-fill","red",
	     "-strokewidth",1,"-draw",sprintf("text %.2f,%.2f \'%s\'",
					      $x,$y,$note_question{$etud}->{$q}."/".$note_question{'max'}->{$q});
	 }
	 
	 push @cmd,"$cr_dir/corrections/jpg/page-$idf.jpg";

	 #print "Fabrication de page-$idf.jpg...\n";
	 commande_externe(@cmd);
     }
 }

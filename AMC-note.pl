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
use IO::File;
use XML::Writer;
use Getopt::Long;
use POSIX qw(ceil floor);
use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::Scoring;
use AMC::Data;

use encoding 'utf8';

$VERSION_BAREME=2;
$VERSION_NOTES=2;

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
my $data_dir='';

my $postcorrect='';

my $progres=1;
my $plafond=1;
my $progres_id='';

my $debug='';

GetOptions("data=s"=>\$data_dir,
	   "bareme=s"=>\$bareme,
	   "seuil=s"=>\$seuil,
	   "debug=s"=>\$debug,
	   "copies!"=>\$annotation_copies,
	   "o=s"=>\$fichnotes,
	   "grain=s"=>\$grain,
	   "arrondi=s"=>\$type_arrondi,
	   "notemax=s"=>\$note_parfaite,
	   "plafond!"=>\$plafond,
	   "notemin=s"=>\$note_plancher,
	   "postcorrect=s"=>\$postcorrect,
	   "encodage-interne=s"=>\$encodage_interne,
	   "progression-id=s"=>\$progres_id,
	   "progression=s"=>\$progres,
	   );

set_debug($debug);

# fixes decimal separator ',' potential problem, replacing it with a
# dot.
for my $x (\$grain,\$note_plancher,\$note_parfaite) {
    $$x =~ s/,/./;
    $$x =~ s/\s+//;
}

# Implements the different possible rounding schemes.

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

if(! -d $data_dir) {
    attention("No DATA directory: $data_dir");
    die "No DATA directory: $data_dir";
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

my $data=AMC::Data->new($data_dir);
my $capture=$data->module('capture');

my $bar=AMC::Scoring::new('file'=>$bareme,'onerror'=>'die',
			  'data'=>$data,
			  'seuil'=>$seuil);

if($VERSION_BAREME ne $bar->version) {
    attention("Marking scale file version (".$bar->version.")",
	      "is too old (here $VERSIN_BAREME):",
	      "please make marking scale file again...");
    die("Marking scale file version mismatch: $VERSION_BAREME / ".$bar->version);
}

$avance->progres(0.05);

# Prepares output file with marks...

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
		  'plafond'=>$plafond,
		  'arrondi'=>$type_arrondi,
		  'grain'=>$grain);

# Computes and outputs marks...

$data->begin_read_transaction;

my $somme_notes=0;
my $n_notes=0;

my %les_codes=();

my %qt_indicative=();
my %qt_max=();
my %qt_n=();
my %qt_sum=();
my %qt_summax=();

my @a_calculer=@{$capture->dbh
		   ->selectall_arrayref($capture->statement('studentCopies'),{})};

my $delta=0.19;
$delta/=(1+$#a_calculer) if($#a_calculer>=0);

# postcorrect mode?
if($postcorrect) {
    $bar->postcorrect($postcorrect);
    $bar->write();
}

for my $sc (@a_calculer) {
  my $etud=$sc->[0];

  debug "MARK: --- SHEET ".studentids_string(@$sc);

    $writer->startTag('copie',
		      'id'=>studentids_string(@$sc));

    my $total=0;
    my $max_i=0;
    my %codes=();

    for my $q ($bar->questions($etud)) {
	
	($xx,$raison,$keys)=$bar->score_question(@$sc,$q);
	($notemax)=$bar->score_max_question($etud,$q);

	my $tit=$bar->question_title($etud,$q);

	debug "MARK: QUESTION $q TITLE $tit";

	if($tit =~ /^(.*)\.([0-9]+)$/) {
	    $codes{$1}->{$2}=$xx;
	} 

	if($bar->question_is_indicative($etud,$q)) {
	    $qt_indicative{$tit}=1;
	    $notemax=1;
	} else {
	    $total+=$xx;
	    $max_i+=$notemax;
	}
	    
	if(!defined($qt_max{$tit}) || $qt_max{$tit}<$notemax) {
	    $qt_max{$tit}=$notemax;
	}
	$qt_n{$tit}++;
	$qt_sum{$tit}+=$xx;
	$qt_summax{$tit}+=$notemax;
		
	$writer->emptyTag('question',
			  'id'=>$tit,
			  'cochees'=>join(';',$capture->ticked_list(@$sc,$q,$seuil)),
			  'note'=>$xx,
			  'raison'=>$raison,
			  'indicative'=>$bar->question_is_indicative($etud,$q),
			  'max'=>$notemax,
	    );
	
    }

    # Final mark --
    
    # total qui faut pour avoir le max
    $max_i=$bar->main_tag('SUF',$max_i,$etud);
    if($max_i<=0) {
	debug "Warning: Nonpositive value for MAX.";
	$max_i=1;
    }
    
    # application du grain et de la note max
    my $x;

    if($note_parfaite>0) {
	$x=$note_parfaite/$grain*$total/$max_i;
    } else {
	$x=$total/$grain;
    }
    $x=&$arrondi($x) if($arrondi);
    $x*=$grain;
    
    $x=$note_parfaite if($note_parfaite>0 && $plafond && $x>$note_parfaite);
    
    # plancher
    
    if($note_plancher ne '' && $note_plancher !~ /[a-z]/i) {
	$x=$note_plancher if($x<$note_plancher);
    } 
    
    #--
    
    $n_notes++;
    $somme_notes+=$x;
    
    $writer->emptyTag('total',
		      'total'=>$total,
		      'max'=>$max_i,
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

    $avance->progres($delta);
}

# Special: maxima

$writer->startTag('copie',id=>'max');

my $total=0;
for my $t (keys %qt_max) {
    $writer->emptyTag('question',
		      'id'=>$t,
		      'note'=>$qt_max{$t},
		      'indicative'=>$qt_indicative{$t},
		      );
    $total+=$qt_max{$t};
}

$writer->emptyTag('total',
		  'total'=>$total,
		  'max'=>$total,
		  'note'=>$note_parfaite,
		  );
$writer->endTag('copie');

# Special: means

$writer->startTag('copie',id=>'moyenne');

for my $t (keys %qt_n) {
    $writer->emptyTag('question',
		      'id'=>$t,
		      'n'=>$qt_n{$t},
		      'note'=>$qt_sum{$t}/$qt_n{$t},
		      'max'=>$qt_summax{$t}/$qt_n{$t},
		      )
	if($qt_n{$t} > 0);
}

$writer->emptyTag('total',
		  'total'=>$somme_notes,
		  'max'=>$note_parfaite,
		  'note'=>($n_notes>0 ? $somme_notes/$n_notes : 0),
		  );
$writer->endTag('copie');

# Special: codes that has been read.

for my $k (keys %les_codes) {
    $writer->startTag('code','id'=>$k);
    for (keys %{$les_codes{$k}}) {
	$writer->dataElement('valeur',$_,
			     'nombre'=>$les_codes{$k}->{$_});
    }
    $writer->endTag('code');
}

# Global mean

$writer->dataElement('moyenne',$somme_notes/$n_notes)
    if($n_notes>0);

# Closes output...

$writer->endTag('notes');
    
$writer->end();
$output->close();

$data->end_transaction;

$avance->fin();

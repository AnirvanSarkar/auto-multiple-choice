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

package AMC::Export::ods;

use AMC::Export;

use OpenOffice::OODoc;

@ISA=("AMC::Export");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    $self->{'out.nom'}="";
    $self->{'out.code'}="";
    bless ($self, $class);
    return $self;
}

sub parse_num {
    my ($self,$n)=@_;
    if($self->{'out.decimal'} ne '.') {
	$n =~ s/\./$self->{'out.decimal'}/;
    }
    return($self->parse_string($n));
}

sub parse_string {
    my ($self,$s)=@_;
    if($self->{'out.entoure'}) {
	$s =~ s/$self->{'out.entoure'}/$self->{'out.entoure'}$self->{'out.entoure'}/g;
	$s=$self->{'out.entoure'}.$s.$self->{'out.entoure'};
    }
    return($s);
}

sub yx2ooo {
    my ($y,$x,$fy,$fx)=@_;
    my $c=($fx ? '$' : '');
    my $d=int($x/26);
    $x=$x % 26;
    $c.=chr(ord("A")+$d-1) if($d>0);
    $c.=chr(ord("A")+$x);
    $c.=($fy ? '$' : '').($y+1);
    return($c);
}

my %largeurs=(qw/note 1.5cm
	      nom 5cm
	      copie 1.75cm
	      total 1.2cm
	      max 1cm/);

my %style_col=(qw/NOM Tableau
	       NOTE NoteF
	       ID NumCopie
	       TOTAL NoteQ
	       MAX NoteQ
	       /);

my %fonction_arrondi=(qw/i ROUNDDOWN
		      n ROUND
		      s ROUNDUP
		      /);

sub export {
    my ($self,$fichier)=@_;

    $self->pre_process();

    my $grain=$self->{'calcul'}->{'grain'};
    my $ndg=0;
    if($grain =~ /[.,]([0-9]*[1-9])/) {
	$ndg=length($1);
    }

    my $arrondi='ROUND';
    if($self->{'calcul'}->{'arrondi'} =~ /^([ins])/i) {
	$arrondi=$fonction_arrondi{$1};
    }

    my $la_date = odfLocaltime();

    my $archive = odfContainer($fichier, 
			       create => 'spreadsheet');

    my $doc=odfConnector(container	=> $archive,
			 part		=> 'content',
			 );
    my $styles=odfConnector(container	=> $archive,
			    part		=> 'styles',
			    );

    $doc->createStyle('col.notes',
		      family=>'table-column',
		      properties=>{
			  -area=>'table-column',
			  'column-width' => "1cm", 
		      },
		      );
   
    for(keys %largeurs) {
	$doc->createStyle('col.'.$_,
			  family=>'table-column',
			  properties=>{
			      -area=>'table-column',
			      'column-width' => $largeurs{$_}, 
			  },
			  );
    }

    $styles->createStyle('DeuxDecimales',
			 namespace=>'number',
			 type=>'number-style',
			 properties=>{
			     'number:decimal-places'=>"2",
			     'number:min-integer-digits'=>"1",
			     'number:grouping'=>'true', # espace tous les 3 chiffres
			     'number:decimal-replacement'=>"", # n'ecrit pas les decimales nulles
			 },
			 );

    $styles->createStyle('num.Note',
			 namespace=>'number',
			 type=>'number-style',
			 properties=>{
			     'number:decimal-places'=>$ndg,
			     'number:min-integer-digits'=>"1",
			     'number:grouping'=>'true', # espace tous les 3 chiffres
			 },
			 );

    $styles->createStyle('Tableau',
			 parent=>'Default',
			 family=>'table-cell',
			 properties=>{
			     -area => 'table-cell',
			     'fo:border'=>"0.039cm solid \#000000", # epaisseur trait / solid|double / couleur
			 },
			 );
    
    $styles->createStyle('NoteQ',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "center",
			 },
			 'references'=>{'style:data-style-name' => 'DeuxDecimales'},		     
			 );

    $styles->createStyle('CodeV',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "center",
			 },
			 );

    $styles->updateStyle('CodeV',
			 properties=>{
			     -area=>'table-cell',
			     'fo:background-color'=>"#e6e6ff",
			 },
			 );

    $styles->createStyle('NoteF',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "right",
			 },
			 'references'=>{'style:data-style-name' => 'num.Note'},		     
			 );

    $styles->updateStyle('NoteF',
			 properties=>{
			     -area=>'table-cell',
			     'fo:padding-right'=>"0.2cm",
			 },
			 );

    $styles->createStyle('Titre',
			 parent=>'Default',
			 family=>'table-cell',
			 properties=>{
			     -area => 'text',
			     'fo:font-weight'=>'bold',
			     'fo:font-size'=>"16pt",
			 },
			 );

    $styles->createStyle('NumCopie',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "center",
			 },
			 );

    $styles->createStyle('Entete',
			 parent=>'Default',
			 family=>'table-cell',
			 properties=>{
			     -area => 'table-cell',
			     'vertical-align'=>"bottom",
			     'horizontal-align' => "middle",
			     'fo:padding'=>'1mm', # espace entourant le contenu
			     'fo:border'=>"0.039cm solid \#000000", # epaisseur trait / solid|double / couleur
			 },
			 );
    
    $styles->updateStyle('Entete',
			 properties=>{
			     -area => 'text',
			     'fo:font-weight'=>'bold',
			 },
			 );
    
    $styles->updateStyle('Entete',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align'=>"center",
			 },
			 );

    $styles->createStyle('EnteteVertical',
			 parent=>'Entete',
			 family=>'table-cell',
			 properties=>{
			     -area => 'table-cell',
			     'style:rotation-angle'=>"90",
			 },
			 );
			     

    my @keys=(sort { $a cmp $b } @{$self->{'keys'}}),
    my @codes=(sort { $a cmp $b } @{$self->{'codes'}});

    my $nkeys=$#{$self->{'keys'}}+1;

    my $dimx=7+$#keys+$#codes;
    my $dimy=6+$#{$self->{'copies'}};

    my $feuille=$doc->getTable(0,$dimy,$dimx);
    $doc->expandTable($feuille, $dimy, $dimx);
    $doc->renameTable($feuille,$self->{'out.code'})
	if($self->{'out.code'});

    if($self->{'out.nom'}) {
	$doc->cellStyle($feuille,0,0,'Titre');
	$doc->cellValue($feuille,0,0,$self->{'out.nom'});
    }

    my $x0=0;
    my $x1=0;
    my $y0=2;
    my $y1=0;
    my $y2=0;
    my $ii;
    my %code_col=();
    my %code_row=();

    # premiere ligne
    
    $ii=$x0;
    for(qw/nom note copie total max/) {
	$doc->columnStyle($feuille,$ii,"col.$_");
	$doc->cellStyle($feuille,$y0,$ii,'Entete');
	$doc->cellValue($feuille,$y0,$ii,$_);
	$code_col{$_}=$ii;
	$ii++;
    }

    $x1=$ii;

    for(@keys) {
	$doc->columnStyle($feuille,$ii,'col.notes');
	$doc->cellStyle($feuille,$y0,$ii,'EnteteVertical');
	$doc->cellValue($feuille,$y0,$ii++,$_);
    }
    for(@codes) {
	$doc->cellStyle($feuille,$y0,$ii,'EnteteVertical');
	$doc->cellValue($feuille,$y0,$ii++,$_);
    }

    # lignes suivantes

    my $notemax;

    my $jj=$y0;
    for my $etu (@{$self->{'copies'}}) {
	my $e=$self->{'c'}->{$etu};
	$jj++;

	$code_row{$e->{_ID_}}=$jj;

	if($e->{_ID_} !~ /^(max|moyenne)$/) {
	    $y1=$jj if(!$y1);
	    $y2=$jj;
	}

	$ii=$x0;
	for(qw/NOM NOTE ID TOTAL MAX/) {
	    $doc->cellValueType($feuille,$jj,$ii,'float')
		if(/^(NOTE|TOTAL|MAX)$/);
	    $doc->cellStyle($feuille,$jj,$ii,$style_col{$_});
	    if($_ eq 'TOTAL') {
		$doc->cellFormula($feuille,$jj,$ii,
				  "oooc:=SUM([.".yx2ooo($jj,$x1).":.".yx2ooo($jj,$x1+$nkeys-1)."])");
	    } elsif($_ eq 'NOTE') {
		if($e->{_ID_} eq 'max') {
		    $notemax='[.'.yx2ooo($jj,$ii,1,1).']';
		    $doc->cellValue($feuille,$jj,$ii,$e->{'_'.$_.'_'});
		} elsif($e->{_ID_} eq 'moyenne') {
		} else {
		    $doc->cellFormula($feuille,$jj,$ii,
				      "oooc:=$arrondi([."
				      .yx2ooo($jj,$code_col{'total'})
				      ."]/[."
				      .yx2ooo($jj,$code_col{'max'})
				      ."]*$notemax/$grain)*$grain");
		}
	    } else {
		$doc->cellValue($feuille,$jj,$ii,$e->{'_'.$_.'_'});
	    }
	    $ii++;
	}
	
	for(@keys) {
	    $doc->cellValueType($feuille,$jj,$ii,'float');
	    $doc->cellStyle($feuille,$jj,$ii,'NoteQ');
	    $doc->cellValue($feuille,$jj,$ii++,$e->{$_});
	}
	for(@codes) {
	    $doc->cellValueType($feuille,$jj,$ii,'float');
	    $doc->cellStyle($feuille,$jj,$ii,'CodeV');
	    $doc->cellValue($feuille,$jj,$ii++,$e->{$_});
	}
    }

    $doc->cellFormula($feuille,$code_row{'moyenne'},$code_col{'note'},
		      "oooc:=AVERAGE([."
		      .yx2ooo($y1,$code_col{'note'})
		      .":."
		      .yx2ooo($y2,$code_col{'note'})."])");


    # meta-donnees et ecriture...
    
    my $meta = odfMeta(container => $archive);

    $meta->title($self->{'out.nom'});
    $meta->creator($ENV{'USER'});
    $meta->initial_creator($ENV{'USER'});
    $meta->creation_date($la_date);
    $meta->date($la_date);

    $archive->save;

}

1;

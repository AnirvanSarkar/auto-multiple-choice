#
# Copyright (C) 2009-2011 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Export;

use AMC::Basic;
use AMC::NamesFile;
use AMC::AssocFile;

use Data::Dumper;
use XML::Simple;

use_gettext;

sub new {
    my $class = shift;
    my $self  = {
	'fich.notes'=>'',
	'fich.association'=>'',
	'fich.noms'=>'',

	'notes'=>'',
	'assoc'=>'',
	'noms'=>'',

	'assoc.encodage'=>'',
	'assoc.liste_key'=>'', # ou relu dans fichier
	'assoc.notes_id'=>'', # ou relu dans fichier

	'noms.encodage'=>'',
	'noms.separateur'=>'',
	'noms.identifiant'=>'',
	'noms.useall'=>1,
	'noms.abs'=>'ABS',

	'out.rtl'=>'',

	'sort.keys'=>['s:_NOM_','n:_ID_'],

	'c'=>{},
	'calcul'=>{},
    };
    bless ($self, $class);
    return $self;
}

sub set_options {
    my ($self,$domaine,%f)=@_;
    for(keys %f) {
	my $k=$domaine.'.'.$_;
	if(defined($self->{$k})) {
	    debug "Option $k = $f{$_}";
	    $self->{$k}=$f{$_};
	} else {
	    debug "Unusable option <$domaine.$_>\n";
	}
    }
}

sub opts_spec {
    my ($self,$domaine)=@_;
    my @o=();
    for my $k (grep { /^$domaine/ } (keys %{$self})) {
	my $kk=$k;
	$kk =~ s/^$domaine\.//;
	push @o,$kk,$self->{$k} if($self->{$k});
    }
    return(@o);
}

sub load {
    my ($self)=@_;
    if($self->{'fich.notes'} && ! $self->{'notes'}) {
	$self->{'notes'}=eval { XMLin($self->{'fich.notes'},
				      'ForceArray'=>1,
				      'KeyAttr'=>['id'],
				      ) };
	if($self->{'notes'}) {
	    for(qw/seuil notemin notemax plafond arrondi grain/) {
		$self->{'calcul'}->{$_}=
		    $self->{'notes'}->{$_};
	    }
	} else {
	    debug "Marks file analysis error: ".$self->{'fich.notes'}."\n";
	}
    }
    if($self->{'fich.association'} && ! $self->{'assoc'}) {
	$self->{'assoc'}=AMC::AssocFile::new($self->{'fich.association'},
					     $self->opts_spec('assoc'));
	$self->{'assoc'}->load();
    }
    if($self->{'fich.noms'} && ! $self->{'noms'}) {
	$self->{'noms'}=AMC::NamesFile::new($self->{'fich.noms'},
					    $self->opts_spec('noms'));
    }
}

sub pre_process {
    my ($self)=@_;

    $self->load();

    my @copies=(keys %{$self->{'notes'}->{'copie'}});

    my @codes=(keys %{$self->{'notes'}->{'code'}});
    my @keys=();

    push @keys,(grep { if(s/\.[0-9]+$//) { !$self->{'notes'}->{'code'}->{$_} } else { 1; } } (keys %{$self->{'notes'}->{'copie'}->{'max'}->{'question'}}));

    $self->{'indicative'}={};
    for my $k (@keys) {
	$self->{'indicative'}->{$k}=1 if($self->{'notes'}->{'copie'}->{'max'}->{'question'}->{$k}->{'indicative'});
    }

    @keys=sort { $self->{'indicative'}->{$a} <=> $self->{'indicative'}->{$b}
		  || $a cmp $b } @keys;
    @codes=sort { $a cmp $b } @codes;
 
    for my $etu (@copies) {
	$self->{'c'}->{$etu}={'_ID_'=>$etu};

	my $c=$self->{'notes'}->{'copie'}->{$etu};
      
	$self->{'c'}->{$etu}->{'_NOTE_'}=$c->{'total'}->[0]->{'note'};
	$self->{'c'}->{$etu}->{'_TOTAL_'}=$c->{'total'}->[0]->{'total'};
	$self->{'c'}->{$etu}->{'_MAX_'}=$c->{'total'}->[0]->{'max'};
	
	for my $k (@keys) {
	    $self->{'c'}->{$etu}->{$k}=$c->{'question'}->{$k}->{'note'};
	    $self->{'c'}->{$etu}->{"TICKED:".$k}=$c->{'question'}->{$k}->{'cochees'};
	}
	for my $k (@codes) {
	    $self->{'c'}->{$etu}->{$k}=$c->{'code'}->{$k}->{'content'};
	}
    }

    if($self->{'assoc'} && $self->{'noms'}) {
	my $lk=$self->{'assoc'}->get_param('liste_key');
	my %is=();
	$self->{'liste_key'}=$lk;
	for my $etu (@copies) {
	    if($etu =~ /^(max|moyenne)$/) {
		$self->{'c'}->{$etu}->{'_NOM_'}='';
		$self->{'c'}->{$etu}->{'_SPECIAL_'}=1;
	    } else {
		my $i=$self->{'assoc'}->effectif($etu);
		if($i) {
		    $self->{'c'}->{$etu}->{'_ASSOC_'}=$i;
		    $is{$i}=1;
		    my ($n)=$self->{'noms'}->data($lk,$i);
		    if($n) {
			$self->{'c'}->{$etu}->{'_NOM_'}=
			    $n->{'_ID_'};
			$self->{'c'}->{$etu}->{'_LINE_'}=
			    $n->{'_LINE_'};
		    } else {
			for(qw/NOM LINE/) {
			    $self->{'c'}->{$etu}->{'_'.$_.'_'}='?';
			}
		    }
		} else {
		    for(qw/NOM LINE/) {
			$self->{'c'}->{$etu}->{'_'.$_.'_'}='??';
		    }
		}	
	    }
	}
	if($self->{'noms.useall'}) {
	    my $n=0;
	    for my $i ($self->{'noms'}->liste($lk)) {
		if(!$is{$i}) {
		    $n++;
		    my $e=sprintf("none.%04d",$n);
		    my ($name)=$self->{'noms'}->data($lk,$i);
		    $self->{'c'}->{$e}={
			'_ID_'=>'','_ASSOC_'=>$i,
			'_ABS_'=>1,
			'_NOTE_'=>$self->{'noms.abs'},
			'_NOM_'=>$name->{'_ID_'},
			'_LINE_'=>$name->{'_LINE_'},
		    };
		}
	    }
	}
    } else {
	$self->{'liste_key'}='';
	debug "No association\n";
    }

    $self->{'keys'}=\@keys;
    $self->{'codes'}=\@codes;

    debug "Sorting with keys ".join(", ",@{$self->{'sort.keys'}});
    $self->{'copies'}=[sort { $self->compare($a,$b); }
		       (keys %{$self->{'c'}})];

}

sub compare {
    my ($self,$a,$b)=@_;
    my $r=0;

    if($a =~ /[^0-9]$/) {
	if($b =~ /[^0-9]$/) {
	    return($a cmp $b);
	} else {
	    return(-1);
	}
    } elsif($b =~ /[^0-9]$/) {
	return(1);
    }

    for my $k (@{$self->{'sort.keys'}}) {
	my $key=$k;
	my $mode='s';

	if($k =~ /^([ns]):(.*)/) {
	    $mode=$1;
	    $key=$2;
	}
	if($mode eq 'n') {
	    $r=$r || ( $self->{'c'}->{$a}->{$key} <=> 
		       $self->{'c'}->{$b}->{$key} );
	} else {
	    $r=$r || ( $self->{'c'}->{$a}->{$key} cmp
		       $self->{'c'}->{$b}->{$key} );
	}
    }
    return($r);
}

sub export {
    my ($self,$fichier)=@_;

    debug "WARNING: Base class export to $fichier\n";
}

1;


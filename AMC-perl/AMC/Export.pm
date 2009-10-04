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

package AMC::Export;

use AMC::Basic;
use AMC::NamesFile;
use AMC::AssocFile;

use Data::Dumper;
use XML::Simple;

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
	    $self->{$k}=$f{$_};
	} else {
	    print STDERR "Option <$domaine.$_> inutilisable\n";
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
	    for(qw/seuil notemax arrondi grain/) {
		$self->{'calcul'}->{$_}=
		    $self->{'notes'}->{$_};
	    }
	} else {
	    print STDERR "Erreur a l'analyse du fichier de notes ".$self->{'fich.notes'}."\n";
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

    for(grep { if(s/\.[0-9]+$//) { !$self->{'notes'}->{'code'}->{$_} } else { 1; } } (keys %{$self->{'notes'}->{'copie'}->{'max'}->{'question'}})) {
	if($self->{'notes'}->{'copie'}->{'max'}->{'question'}->{$_}->{'indicative'}) {
	    push @codes,$_;
	} else {
	    push @keys,$_;
	}
    }

    @keys=sort { $a cmp $b } @keys;
    @codes=sort { $a cmp $b } @codes;
 
    for my $etu (@copies) {
	$self->{'c'}->{$etu}={'_ID_'=>$etu};

	my $c=$self->{'notes'}->{'copie'}->{$etu};
      
	$self->{'c'}->{$etu}->{'_NOTE_'}=$c->{'total'}->[0]->{'note'};
	$self->{'c'}->{$etu}->{'_TOTAL_'}=$c->{'total'}->[0]->{'total'};
	$self->{'c'}->{$etu}->{'_MAX_'}=$c->{'total'}->[0]->{'max'};
	
	for my $k (@keys) {
	    $self->{'c'}->{$etu}->{$k}=$c->{'question'}->{$k}->{'note'};
	}
	for my $k (@codes) {
	    $self->{'c'}->{$etu}->{$k}=$c->{'code'}->{$k}->{'content'};
	}
    }

    my $k_id='_ID_';

    if($self->{'assoc'} && $self->{'noms'}) {
	my $lk=$self->{'assoc'}->get_param('liste_key');
	for my $etu (@copies) {
	    if($etu =~ /^(max|moyenne)$/) {
		$self->{'c'}->{$etu}->{'_NOM_'}='';
	    } else {
		my $i=$self->{'assoc'}->effectif($etu);
		if($i) {
		    my ($n)=$self->{'noms'}->data($lk,$i);
		    if($n) {
			$self->{'c'}->{$etu}->{'_NOM_'}=
			    $n->{'_ID_'};
		    } else {
			$self->{'c'}->{$etu}->{'_NOM_'}='?';
		    }
		} else {
		    $self->{'c'}->{$etu}->{'_NOM_'}='??';
		}	
	    }
	}

	$k_id='_NOM_';
    } else {
	print STDERR "Pas d'association utilisable\n";
    }

    $self->{'keys'}=\@keys;
    $self->{'codes'}=\@codes;

    $self->{'copies'}=[sort { $self->{'c'}->{$a}->{$k_id}
			      cmp $self->{'c'}->{$b}->{$k_id} }
		       (keys %{$self->{'c'}})];

    #print Dumper($self->{'c'});
}

sub export {
    my ($self,$fichier)=@_;

    print STDERR "Export dans la classe de base : $fichier\n";
}

1;


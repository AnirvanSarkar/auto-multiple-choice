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

package AMC::NamesFile;

use AMC::Basic;

sub new {
    my ($f,%o)=@_;
    my $self={'fichier'=>$f,
	      'encodage'=>'utf-8',
	      'separateur'=>'',
	      'identifiant'=>'(nom) (prenom)',

	      'heads'=>[],
	      'err'=>[0,0],
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    $self->{'separateur'}=":;\t" if(!$self->{'separateur'});

    bless $self;

    @{$self->{'err'}}=($self->load());

    return($self);
}    

sub reduit {
    my $s=shift;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return($s);
}

sub errors {
    my ($self)=@_;
    return(@{$self->{'err'}});
}

sub load {
    my ($self)=@_;
    my @heads=();
    my %data=();
    my $err=0;
    my $errlig=0;
    my $sep=$self->{'separateur'};

    $self->{'noms'}=[];

    debug "Lecture du fichier de noms $self->{'fichier'}";

    if(open(LISTE,"<:encoding(".$self->{'encodage'}.")",$self->{'fichier'})) {
      NOM: while(<LISTE>) {
	  chomp;
	  s/\#.*//;
	  next NOM if(/^\s*$/);
	  if(!@heads) {
	      if($sep) {

		  my $entetes=$_;

		  if(length($self->{'separateur'})>1) {
		      my $nn=-1;
		      for my $s (split(//,$self->{'separateur'})) {
			  my $k=0;
			  while($entetes =~ /$s/g) { $k++; }
			  if($k>$nn) {
			      $nn=$k;
			      $sep=$s;
			  }
		      }
		      debug "Separateur detecte : ".($sep eq "\t" ? "<TAB>" : "<".$sep.">");
		  }

		  @heads=map { reduit($_) } split(/$sep/,$entetes);
		  debug "ENTETES : ".join(", ",@heads);
		  next NOM;
	      } else {
		  @heads='nom';
	      }
	  }
	  s/^\s+//;
	  s/\s+$//;
	  my @l=();
	  if($#heads>0) {
	      @l=map { reduit($_) } split(/$sep/,$_);
	  } else {
	      @l=(reduit($_));
	  }
	  if($#l!=$#heads) {
	      print STDERR "Mauvais nombre de champs (".(1+$#l)." au lieu de ".(1+$#heads).") fichier ".$self->{'fichier'}." ligne $.\n";
	      $errlig=$. if(!$errlig);
	      $err++;
	  } else {
	      my $nom={};
	      for(0..$#l) {
		  $nom->{$heads[$_]}=$l[$_];
		  $data{$heads[$_]}->{$l[$_]}++;
	      }
	      push @{$self->{'noms'}},$nom;
	  }
      }
	close LISTE;
	# entetes et cles
	$self->{'heads'}=\@heads;
	$self->{'keys'}=[grep { my @lk=(keys %{$data{$_}}); 
				$#lk==$#{$self->{'noms'}}; } @heads];
	# rajout identifiant
	$self->calc_identifiants();
	$self->tri('_ID_');

	return($err,$errlig);
    } else {
	return(-1,0);
    }
}

sub calc_identifiants {
    my ($self)=@_;
    for my $n (@{$self->{'noms'}}) {
	my $id=$self->{'identifiant'};
	$id =~ s/\(([^\)]+)\)/(defined($n->{$1}) ? $n->{$1} : '')/gei;
	$id =~ s/^\s+//;
	$id =~ s/\s+$//;
	$n->{'_ID_'}=$id;
    }
}

sub tri {
    my ($self,$cle)=@_;
    $self->{'noms'}=[sort { $a->{$cle} cmp $b->{$cle} } @{$self->{'noms'}}];
}

sub taille {
    my ($self)=@_;
    return(1+$#{$self->{'noms'}});
}

sub heads { # entetes
    my ($self)=@_;
    return(@{$self->{'heads'}});
}

sub keys { # entetes qui peuvent servir de cle unique
    my ($self)=@_;
    return(@{$self->{'keys'}});
}

sub liste {
    my ($self,$head)=@_;
    return(map { $_->{$head} } @{$self->{'noms'}} );
}

sub data {
    my ($self,$head,$c,%oo)=@_;
    my @k=grep { defined($self->{'noms'}->[$_]->{$head}) 
		     && ($self->{'noms'}->[$_]->{$head} eq $c) }
    (0..$#{$self->{'noms'}});
    if(!$oo{'all'}) {
	if($#k!=0) {
	    print STDERR "Erreur : nom non unique (".(1+$#k)." exemplaires)\n";
	    return();
	}
    }
    if($oo{'i'}) {
	return(@k);
    } else {
	return(map { $self->{'noms'}->[$_] } @k);
    }
}

sub data_n {
    my ($self,$n,$cle)=@_;
    return($self->{'noms'}->[$n]->{$cle});
}

1;

__END__


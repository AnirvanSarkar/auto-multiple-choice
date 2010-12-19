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

package AMC::NamesFile;

use AMC::Basic;

sub new {
    my ($f,%o)=@_;
    my $self={'fichier'=>$f,
	      'encodage'=>'utf-8',
	      'separateur'=>'',
	      'identifiant'=>'',

	      'heads'=>[],
	      'problems'=>{},
	      'err'=>[0,0],
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    $self->{'separateur'}=":,;\t" if(!$self->{'separateur'});
    $self->{'identifiant'}='(nom|surname) (prenom|name)'
	if(!$self->{'identifiant'});

    bless $self;

    @{$self->{'err'}}=($self->load());

    return($self);
}    

sub reduit {
    my ($s)=@_;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    $s=$1 if($s =~ /^\"(.*)\"$/);
    $s=$1 if($s =~ /^\'(.*)\'$/);

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

    debug "Reading names file $self->{'fichier'}";

    if(-f $self->{'fichier'} && ! -z $self->{'fichier'}) {

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
			  debug "Detected separator: ".($sep eq "\t" ? "<TAB>" : "<".$sep.">");
		      }

		      @heads=map { reduit($_) } split(/$sep/,$entetes,-1);
		      debug "KEYS: ".join(", ",@heads);
		      next NOM;
		  } else {
		      @heads='nom';
		  }
	      }
	      s/^\s+//;
	      s/\s+$//;
	      my @l=();
	      if($#heads>0) {
		  @l=map { reduit($_) } split(/$sep/,$_,-1);
	      } else {
		  @l=(reduit($_));
	      }
	      if($#l!=$#heads) {
		  print STDERR "Bad number of fields (".(1+$#l)." instead of ".(1+$#heads).") file ".$self->{'fichier'}." line $.\n";
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
    } else {
	debug("Inexistant or empty names list file");
	$self->{'heads'}=[];
	$self->{'keys'}=[];
	return(0,0);
    }
}

sub get_value {
    my ($self,$key,$vals)=@_;
    my $r='';
  KEY: for my $k (split(/\|+/,$key)) {
      for my $h ($self->heads()) {
	  if($k =~ /^$h:([0-9]+)$/i) {
	      if(defined($vals->{$h})) {
		  $r=sprintf("%0".$1."d",$vals->{$h});
	      }
	  } elsif((lc($h) eq lc($k)) && defined($vals->{$h})) {
	      $r=$vals->{$h};
	  }
      }
      last KEY if($r ne '');
  }
    return($r);
}

sub calc_identifiants {
    my ($self)=@_;
    my %ids=();

    $self->{'problems'}={'ID.dup'=>[],'ID.empty'=>0};

    for my $n (@{$self->{'noms'}}) {
	my $i=$self->substitute($n,$self->{'identifiant'});
	$n->{'_ID_'}=$i;
	if($i) {
	    if($ids{$i}) {
		push @{$self->{'problems'}->{'ID.dup'}},$i;
	    } else {
		$ids{$i}=1;
	    }
	} else {
	    $self->{'problems'}->{'ID.empty'}++;
	}
    }
}

sub problem {
    my ($self,$k)=@_;
    return($self->{'problems'}->{$k});
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

# use names fields from $n to subsitute (HEADER) substrings in $s
sub substitute {
    my ($self,$n,$s)=@_;

    if(defined($n->{'_ID_'})) {
	my $nom=$n->{'_ID_'};
	$nom =~ s/^\s+//;
	$nom =~ s/\s+$//;
	$nom =~ s/\s+/_/g;
	
	$s =~ s/\(ID\)/$nom/g;
    }

    $s =~ s/\(([^\)]+)\)/get_value($self,$1,$n)/gei;

    $s =~ s/^\s+//;
    $s =~ s/\s+$//;

    return($s);
}

sub data {
    my ($self,$head,$c,%oo)=@_;
    my @k=grep { defined($self->{'noms'}->[$_]->{$head}) 
		     && ($self->{'noms'}->[$_]->{$head} eq $c) }
    (0..$#{$self->{'noms'}});
    if(!$oo{'all'}) {
	if($#k!=0) {
	    print STDERR "Error: non-unique name (".(1+$#k)." records)\n";
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


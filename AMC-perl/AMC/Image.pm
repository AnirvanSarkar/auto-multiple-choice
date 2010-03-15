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

package AMC::Image;

use AMC::Basic;
use IPC::Open2;

sub new {
    my ($fichier,%o)=(@_);
    my $self={'fichier'=>$fichier,
	      'ipc_in'=>'',
	      'ipc_out'=>'',
	      'ipc'=>'',
	      'traitement'=>$amc_libdir.'/AMC-traitement-image',
	  };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    bless $self;

    return($self);
}


sub commande {
    my ($self,@cmd)=(@_);
    my @r=();

    if(!$self->{'ipc'}) {
	debug "Exec traitement-image..."; 
	$self->{'ipc'}=open2($self->{'ipc_out'},$self->{'ipc_in'},
			     $self->{'traitement'},$self->{'fichier'});
	debug "PID=".$self->{'ipc'}." : ".$self->{'ipc_in'}." --> ".$self->{'ipc_out'};
    }

    debug "CMD : ".join(' ',@cmd);

    print { $self->{'ipc_in'} } join(' ',@cmd)."\n";

  GETREPONSE: while($_=readline($self->{'ipc_out'})) {
      chomp;
      debug "|> $_";
      last GETREPONSE if(/_{2}END_{2}/);
      push @r,$_;
  }

    return(@r);
}

sub ferme_commande {
    my ($self)=(@_);
    if($self->{'ipc'}) {
	print { $self->{'ipc_in'} } "quit\n";
	waitpid $self->{'ipc'},0;
	$self->{'ipc'}='';
	$self->{'ipc_in'}='';
	$self->{'ipc_out'}='';
    }
}

sub DESTROY {
    my ($self)=(@_);
    $self->ferme_commande();
}

1;

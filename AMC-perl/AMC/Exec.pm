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

package AMC::Exec;

use AMC::Basic;

sub new {
    my ($nom)=@_;
    my $self={'pid'=>'',
	      'nom'=>$nom || 'AMC',
	  };
    bless($self);
    return($self);
}

sub catch_signal {
    my ($self,$signame)=@_;
    if($self->{'pid'}) {
	debug "*** $self->{'nom'} : signal $signame, je tue $self->{'pid'}...\n";
	kill 9,$self->{'pid'};
    }
    die "$self->{'nom'} killed";
}

sub signalise {
    my ($self)=@_;
    $SIG{INT} = sub { my $s=shift;$self->catch_signal($s); };
}

sub execute {
    my ($self,@c)=@_;

    my $prg=$c[0];
    
    if($prg) {

	if(!commande_accessible($prg)) {
	    debug "*** ATTENTION : programme \"$prg\" introuvable dans le PATH !";
	}
	
	my $cmd_pid=fork();
	if($cmd_pid) {
	    $self->{'pid'}=$cmd_pid;
	    debug "Commande [$cmd_pid] : ".join(' ',@c);
	    waitpid($cmd_pid,0);
	    debug "Cmd PID=$cmd_pid retourne $?"; 
	} else {
	    exec(@c);
	}

    } else {
	debug "Commande : pas de programme ! ".join(' ',@c);
    }

}

1;


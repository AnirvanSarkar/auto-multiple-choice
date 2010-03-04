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

package AMC::Queue;

use AMC::Basic;
use Sys::CPU;

sub new {
    my (%o)=@_;

    my $self={'pids'=>[],
	      'queue'=>[],
	      'max.procs'=>0,
	  };
    
    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    if($self->{'max.procs'}<1) {
	$self->{'max.procs'}=Sys::CPU::cpu_count();
	debug "Max number of processes: ".$self->{'max.procs'};
    }

    bless $self;
    
    return($self);
}

sub add_process {
    my ($self,@o)=@_;
    push @{$self->{'queue'}},[@o];
}

sub maj {
    my ($self)=@_;
    my @p=();
    for my $pid (@{$self->{'pids'}}) {
	push @p,$pid if(kill(0,$pid));
    }
    @{$self->{'pids'}}=@p;
    debug "MAJ : ".join(' ',@p);
    return(1+$#{$self->{'pids'}});
}

sub killall {
    my ($self)=@_;
    $self->{'queue'}=[];
    print "Queue interruption\n";
    for my $p (@{$self->{'pids'}}) {
	print "Queue: killing $p\n";
	kill 9,$p;
    }
}

sub run {
    my ($self,$subsys)=@_;
    debug "Queue RUN";
    while(@{$self->{'queue'}}) {
	while($self->maj() < $self->{'max.procs'}) {
	    my $cs=shift(@{$self->{'queue'}});
	    if($cs) {
		my $p=fork();
		if($p) {
		    debug "Fork : $p";
		    push @{$self->{'pids'}},$p;
		} else {
		    if(ref($cs->[0]) eq 'ARRAY') { 
			for my $c (@$cs) {
			    debug "Command [$$] : ".join(' ',@$c);
			    if(system(@$c)==0) {
				debug "Command [$$] OK";
			    } else {
				debug "Error [$$] : $?\n";
			    }
			}
			exit(0);
		    } else {
			debug "Command [$$] : ".join(' ',@$cs);
			exec(@$cs);
			debug "Bad exec $$ [".$cs->[0]."] unknown command";
			die "Unknown command";
		    }
		}
	    } else {
		debug "Queue ends";
	    }
	}
	waitpid(-1,0);
    }
    waitpid(-1,0);
}

1;

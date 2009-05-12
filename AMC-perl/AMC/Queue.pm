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

package AMC::Queue;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw();
}

sub new {
    my (%o)=@_;

    my $self={'pids'=>[],
	      'queue'=>[],
	      'max.procs'=>1,
	      'debug'=>1,
	  };
    
    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
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
    print "MAJ : ".join(' ',@p)."\n" if($self->{'debug'});
    return(1+$#{$self->{'pids'}});
}

sub run {
    my ($self,$subsys)=@_;
    while(@{$self->{'queue'}}) {
	while($self->maj() < $self->{'max.procs'}) {
	    my $cs=shift(@{$self->{'queue'}});
	    if($cs) {
		my $p=fork();
		if($p) {
		    print "Fork : $p\n" if($self->{'debug'});
		    push @{$self->{'pids'}},$p;
		} else {
		    if(ref($cs->[0]) eq 'ARRAY') { 
			for my $c (@$cs) {
			    print STDERR "Command [$$] : ".join(' ',@$c)."\n" if($self->{'debug'});
			    if(system(@$c)==0) {
				print "Command [$$] OK\n" if($self->{'debug'});
			    } else {
				print STDERR "Erreur [$$] : $?\n";
			    }
			}
			exit(0);
		    } else {
			exec(@$cs);
		    }
		}
	    } else {
		print "Fin de queue\n" if($self->{'debug'});
	    }
	}
	waitpid(-1,0);
    }
    waitpid(-1,0);
}

1;

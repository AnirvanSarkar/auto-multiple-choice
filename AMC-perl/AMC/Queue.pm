#
# Copyright (C) 2008-2021 Alexis Bienvenüe <paamc@passoire.fr>
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

use warnings;
use 5.012;

package AMC::Queue;

use AMC::Basic;
use Module::Load;
use Module::Load::Conditional qw/check_install/;
use File::Temp qw/ tempdir /;
use Storable;

# recupere le nombre de CPU, avec Sys::CPU si ce module est installe
sub get_ncpu {
    my $n = 0;
    if ( check_install( module => "Sys::CPU" ) ) {
        load("Sys::CPU");
        debug_pm_version("Sys::CPU");
        $n = Sys::CPU::cpu_count();
    } else {
        open( CI, "/proc/cpuinfo" );
        while (<CI>) {
            $n++ if (/^processor\s*:/);
        }
        close(CI);
    }
    $n = 1 if ( $n <= 0 );
    return ($n);
}

sub new {
    my (%o) = @_;

    my $self = {
        pids                => [],
        queue               => [],
        pidof               => {},
        get_returned_values => 0,
        'max.procs'         => 0,
    };

    for my $k ( keys %o ) {
        $self->{$k} = $o{$k} if ( defined( $self->{$k} ) );
    }

    if ( $self->{'max.procs'} < 1 ) {
        $self->{'max.procs'} = get_ncpu();
        debug "Max number of processes: " . $self->{'max.procs'};
    }

    if ( $self->{get_returned_values} ) {
        $self->{returned} = [];
        $self->{tmpdir}   = tempdir( );
        debug "Queue tmp dir: " . $self->{tmpdir};
    }

    bless $self;

    return ($self);
}

sub add_process {
    my ( $self, @o ) = @_;
    push @{ $self->{queue} }, [@o];
}

sub maj {
    my ($self) = @_;
    my @p = ();
    my %alive=();
    for my $pid ( @{ $self->{pids} } ) {
        if ( kill( 0, $pid ) ) {
            push @p, $pid;
            $alive{$pid} = 1;
        }
    }
    @{ $self->{pids} } = @p;
    debug "MAJ : " . join( ' ', @p );
    if ( $self->{get_returned_values} ) {
        opendir( my $dh, $self->{tmpdir} )
          || debug "Can't open $self->{tmpdir}: $!";
        while ( readdir $dh ) {
            if (/^[0-9]+$/ && !$alive{$self->{pidof}->{$_}}) {
                my $f = $self->{tmpdir} . "/" . $_;
                debug "Retrieving from $f";
                $self->{returned}->[$_] = retrieve($f);
                unlink($f);
            }
        }
        closedir $dh;
    }
    return ( 1 + $#{ $self->{pids} } );
}

sub killall {
    my ($self) = @_;
    $self->{queue} = [];
    debug_and_stderr "Queue interruption\n";
    for my $p ( @{ $self->{pids} } ) {
        debug_and_stderr "Queue: killing $p\n";
        kill 9, $p;
    }
}

sub run {
    my ( $self, $subsys ) = @_;
    debug "Queue RUN";
    my $i = 0;
    while ( @{ $self->{queue} } ) {
        while ( $self->maj() < $self->{'max.procs'}
            && @{ $self->{queue} } )
        {
            my $cs = shift( @{ $self->{queue} } );
            if ($cs) {
                my $p = fork();
                if ($p) {
                    debug "Fork : $p";
                    push @{ $self->{pids} }, $p;
                    $self->{pidof}->{$i} = $p;
                } else {
                    if ( ref( $cs->[0] ) eq 'ARRAY' ) {
                        for my $c (@$cs) {
                            debug "Command [$$] : " . join( ' ', @$c );
                            if ( system(@$c) == 0 ) {
                                debug "Command [$$] OK";
                            } else {
                                debug "Error [$$] : $?\n";
                            }
                        }
                        exit(0);
                    } elsif ( ref( $cs->[0] ) eq 'CODE' ) {
                        my $c = shift @$cs;
                        my $ret = &$c(@$cs);
                        if($self->{get_returned_values}) {
                            store($ret, $self->{tmpdir} . "/" . $i);
                        }
                        exit(0);
                    } else {
                        no warnings 'exec';
                        debug "Command [$$] : " . join( ' ', @$cs );
                        exec(@$cs);
                        debug "Bad exec $$ [" . $cs->[0] . "] unknown command";
                        die "Unknown command";
                    }
                }
                $i++;
            } else {
                debug "Queue empty";
            }
        }
        waitpid( -1, 0 );
    }
    while ( $self->maj() ) {
        debug("Waiting for all childs to end...");
        waitpid( -1, 0 );
    }
    debug("Leaving queue.");
    rmdir $self->{tmpdir} if ( $self->{tmpdir} );
}

sub returned_values {
    my ($self) = @_;
    return ( $self->{returned} );
}

1;

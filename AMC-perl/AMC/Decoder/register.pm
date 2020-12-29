#
# Copyright (C) 2019-2021 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::Decoder::register;

use AMC::Basic;

use Module::Load;
use Module::Load::Conditional qw/check_install/;

use_gettext;

#####################################################################
# These methods should be overwritten for derivated classes (that
# describe decoders that AMC can handle)
#####################################################################

sub new {
    my ( $class, %o ) = @_;
    my $self = { dependencies => 'all' };

    for my $k ( keys %o ) {
        $self->{$k} = $o{$k} if ( defined( $self->{$k} ) );
    }

    bless( $self, $class );
    return $self;
}

# short name of the file format
sub name {
    return ("empty");
}

# weight in the list of all available formats. 0 is at the top, 1 is
# at the bottom line
sub weight {
    return (1);
}

# description of the format, that will be display in the window
# showing details about file formats
sub description {
    return ( __ "No description available." );
}

# list of required perl modules
sub needs_perl_module {
    return ();
}

# list of required commands
sub needs_command {
    return ();
}

#####################################################################
# The following methods should NOT be overwritten
#####################################################################

sub missing_perl_modules {
    my ($self) = @_;

    return ( grep { !check_install( module => $_ ) }
          ( $self->needs_perl_module() ) );
}

sub missing_commands {
    my ($self) = @_;
    my @mc = ();
    for my $c ( $self->needs_command() ) {
        push @mc, $c if ( !commande_accessible($c) );
    }
    return (@mc);
}

sub check_dependencies {
    my ($self) = @_;
    my %miss = (
        perl_modules => [ $self->missing_perl_modules() ],
        commands     => [ $self->missing_commands() ],
    );
    my $ok;
    if ( $self->{dependencies} eq 'all' ) {
        $ok = 1;
        for my $k ( keys %miss ) {
            $ok = 0 if ( @{ $miss{$k} } );
        }
    } elsif ( $self->{dependencies} eq 'one_kind' ) {
        $ok = 0;
        for my $k ( keys %miss ) {
            $ok = 1 if ( !@{ $miss{$k} } );
        }
    }
    $miss{ok} = $ok;
    return ( \%miss );
}

1;

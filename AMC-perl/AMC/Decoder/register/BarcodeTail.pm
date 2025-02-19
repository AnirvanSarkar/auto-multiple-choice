#
# Copyright (C) 2019-2022 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::Decoder::register::BarcodeTail;

use AMC::Decoder::register;
use AMC::Basic;

our @ISA = ("AMC::Decoder::register");

use_gettext;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    bless( $self, $class );
    return $self;
}

sub name {
    return ("Barcode tail");
}

sub weight {
    return (0.6);
}

sub description {
    return ( __ "Barcode last alphanumeric characters" );
}

sub needs_perl_module {
    return ();
}

sub needs_command {
    return ('zbarimg');
}

1;

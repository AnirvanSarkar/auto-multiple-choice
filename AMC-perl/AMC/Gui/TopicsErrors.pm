# -*- perl -*-
#
# Copyright (C) 2025 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::Gui::TopicsErrors;

use parent 'AMC::Gui';

use AMC::Basic;


sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            result       => '',
        },
        %oo
    );

    return $self;
}

sub dialog {
    my ( $self ) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade( $glade_xml, qw/errors_dialog errors_view/, );

    my $buffer = $self->get_ui('errors_view')->get_buffer();
    $buffer->insert_markup( $buffer->get_start_iter(),
        $self->{result}->to_string("pango") );

    my $r = $self->get_ui('errors_dialog')->run;
    $self->get_ui('errors_dialog')->destroy;

    return($r eq 'ok');
}

1;

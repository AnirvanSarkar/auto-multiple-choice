# -*- perl -*-
#
# Copyright (C) 2020-2021 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::Gui::Overwritten;

use parent 'AMC::Gui';

use AMC::Basic;

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            capture       => '',
        },
        %oo
    );

    $self->dialog();

    return $self;
}

sub dialog {
    my ($self) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade(
        $glade_xml,
        qw/overwritten overwritten_list/,
    );

    my $olist =
      Gtk3::ListStore->new( 'Glib::String', 'Glib::String', 'Glib::String' );
    $self->get_ui('overwritten_list')->set_model($olist);

    $self->get_ui('overwritten_list')->append_column(
        Gtk3::TreeViewColumn->new_with_attributes(
            __(
                # TRANSLATORS: column title for the list of
                # overwritten pages. This refers to the page from the
                # question
                "Page"
            ),
            Gtk3::CellRendererText->new,
            text => 0
        )
    );
    $self->get_ui('overwritten_list')->append_column(
        Gtk3::TreeViewColumn->new_with_attributes(
            __(
                # TRANSLATORS: column title for the list of
                # overwritten pages. This refers to the number of
                # times the page has been overwritten.
                "count"
            ),
            Gtk3::CellRendererText->new,
            text => 1
        )
    );
    $self->get_ui('overwritten_list')->append_column(
        Gtk3::TreeViewColumn->new_with_attributes(
            __(
                # TRANSLATORS: column title for the list of
                # overwritten pages. This refers to the date of the
                # last data capture for the page.
                "Date"
            ),
            Gtk3::CellRendererText->new,
            text => 2
        )
    );
    for my $o ( @{ $self->{capture}->overwritten_pages_transaction() } ) {
        $olist->set(
            $olist->append, 0,
            pageids_string( $o->{student}, $o->{page}, $o->{copy} ), 1,
            $o->{overwritten}, 2,
            format_date( $o->{timestamp_auto} ),
        );
    }

    $self->get_ui('overwritten_list')->get_selection->set_mode('none');

    $self->get_ui('overwritten')->run;
    $self->get_ui('overwritten')->destroy;
    
}

1;

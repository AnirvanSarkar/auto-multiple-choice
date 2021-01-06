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

package AMC::Gui::ChooseColumns;

use parent 'AMC::Gui';

use AMC::Basic;

use_gettext();

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            type=>'',
            students_list=>'',
        },
        %oo
        );

    $self->dialog();

    return $self;
}

sub dialog {
    my ($self) = @_;

    my $l = $self->get( 'export_' . $self->{type} . '_columns' );

    my $i         = 1;
    my %selected  = map { $_ => $i++ } ( split( /,+/, $l ) );
    my %order     = ();
    my @available = (
        'student.copy', 'student.key', 'student.name',
        $self->{students_list}->heads()
    );
    $i = 0;
    for (@available) {
        if ( $selected{$_} ) {
            $i = $selected{$_};
        } else {
            $i .= '1';
        }
        $order{$_} = $i;
    }
    @available = sort { $order{$a} cmp $order{$b} } @available;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade(
        $glade_xml, qw/choose_columns
          columns_list/
    );

    my $columns_store = Gtk3::ListStore->new( 'Glib::String', 'Glib::String' );
    $self->get_ui('columns_list')->set_model($columns_store);
    my $renderer = Gtk3::CellRendererText->new;

    my $column = Gtk3::TreeViewColumn->new_with_attributes(
        __
        # TRANSLATORS: This is the title of a column containing all columns
        # names from the students list file, when choosing which columns has
        # to be exported to the spreadsheets.
        "column",
        $renderer,
        text => 0
    );
    $self->get_ui('columns_list')->append_column($column);

    my @selected_iters = ();
    for my $c (@available) {
        my $name = $c;
        $name = __("<full name>")          if ( $c eq 'student.name' );
        $name = __("<student identifier>") if ( $c eq 'student.key' );
        $name = __("<student copy>")       if ( $c eq 'student.copy' );
        my $iter = $columns_store->append;
        $columns_store->set( $iter, 0, $name, 1, $c );
        push @selected_iters, $iter if ( $selected{$c} );
    }
    $self->get_ui('columns_list')->set_reorderable(1);
    $self->get_ui('columns_list')->get_selection->set_mode('multiple');
    for (@selected_iters) {
        $self->get_ui('columns_list')->get_selection->select_iter($_);
    }

    my $resp = $self->get_ui('choose_columns')->run;
    if ( $resp == 1 ) {
        my @k = ();
        my @s = $self->get_ui('columns_list')->get_selection->get_selected_rows;
        for my $i ( @{ $s[0] } ) {
            push @k, $columns_store->get( $columns_store->get_iter($i), 1 )
              if ($i);
        }
        $self->{config}
          ->set( 'export_' . $self->{type} . '_columns', join( ',', @k ) );
    }

    $self->get_ui('choose_columns')->destroy;
}

1;

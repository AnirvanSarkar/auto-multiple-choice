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

package AMC::Gui::SelectStudents;

use parent 'AMC::Gui';

use AMC::Basic;

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            capture       => '',
            association   => '',
            students_list => '',
            id_file       => '',
        },
        %oo
    );

    $self->dialog();

    return $self;
}

sub dialog {
    my ($self) = @_;

    # restore last setting
    my %ids = ();
    if ( open( IDS, $self->{id_file} ) ) {
        while (<IDS>) {
            chomp;
            $ids{$_} = 1 if (/^[0-9]+(:[0-9]+)?$/);
        }
        close(IDS);
    }

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade(
        $glade_xml,
        qw/choose_students
          choose_students_area
          students_select_list students_list_search/
    );

    my $lk = $self->get('liste_key');

    my $students_store = Gtk3::ListStore->new(
        'Glib::String', 'Glib::String',  'Glib::String', 'Glib::String',
        'Glib::String', 'Glib::Boolean', 'Glib::Boolean'
    );

    my $filtered = Gtk3::TreeModelFilter->new($students_store);
    $filtered->set_visible_column(5);
    my $filtered_sorted = Gtk3::TreeModelSort->new_with_model($filtered);

    $filtered_sorted->set_sort_func( 0, \&sort_num,    0 );
    $filtered_sorted->set_sort_func( 1, \&sort_string, 1 );

    $self->{students_list_store}           = $students_store;
    $self->{students_list_filtered}        = $filtered;
    $self->{students_list_filtered_sorted} = $filtered_sorted;

    $self->get_ui('students_select_list')->set_model($filtered_sorted);
    my $renderer = Gtk3::CellRendererText->new;
    my $column   = Gtk3::TreeViewColumn->new_with_attributes(
        __ "exam ID",
        $renderer,
        text => 0
    );
    $column->set_sort_column_id(0);
    $self->get_ui('students_select_list')->append_column($column);

    if ($lk) {
        $column = Gtk3::TreeViewColumn->new_with_attributes( $lk, $renderer,
            text => 4 );
        $column->set_sort_column_id(4);
        $filtered_sorted->set_sort_func( 4, \&sort_string, 4 );
        $self->get_ui('students_select_list')->append_column($column);
    }

    $column = Gtk3::TreeViewColumn->new_with_attributes(
        __ "student",
        $renderer,
        text => 1
    );
    $column->set_sort_column_id(1);
    $self->get_ui('students_select_list')->append_column($column);

    $self->{capture}->begin_read_transaction('gSLi');
    my $key            = $self->{association}->variable('key_in_list');
    my @selected_iters = ();
    my $i              = 0;
    for my $sc ( $self->{capture}->student_copies ) {
        my $id = $self->{association}->get_real(@$sc);
        my ($name) =
          $self->{students_list}->data( $key, $id, test_numeric => 1 );
        my $iter = $students_store->insert_with_values(
            $i++,
            0 => studentids_string(@$sc),
            1 => $name->{_ID_},
            2 => $sc->[0],
            3 => $sc->[1],
            5 => 1,
            4 => ( $lk ? $name->{$lk} : '' ),
        );
        push @selected_iters, $iter if ( $ids{ studentids_string(@$sc) } );
    }
    $self->{capture}->end_transaction('gSLi');

    $self->get_ui('students_select_list')->get_selection->set_mode('multiple');
    for (@selected_iters) {
        $self->get_ui('students_select_list')->get_selection->select_iter(
            $filtered_sorted->convert_child_iter_to_iter(
                $filtered->convert_child_iter_to_iter($_)
            )
        );
    }

    my $resp = $self->get_ui('choose_students')->run;

    $self->save_selected_state();

    my @k = ();

    if ( $resp == 1 ) {
        $students_store->foreach(
            sub {
                my ( $model, $path, $iter, $user ) = @_;
                push @k, [ $students_store->get( $iter, 2, 3 ) ]
                  if ( $students_store->get( $iter, 6 ) );
                return (0);
            }
        );
    }

    $self->get_ui('choose_students')->destroy;

    if ( $resp == 1 ) {
        open( IDS, ">", $self->{id_file} );
        for (@k) {
            print IDS studentids_string(@$_) . "\n";
        }
        close(IDS);
    } else {
        return ();
    }

    return (1);

}

sub save_selected_state {
    my ($self) = @_;

    my $sel    = $self->get_ui('students_select_list')->get_selection;
    my $fs     = $self->{students_list_filtered_sorted};
    my $f      = $self->{students_list_filtered};
    my $s      = $self->{students_list_store};
    my @states = ();
    $fs->foreach(
        sub {
            my ( $model, $path, $iter, $user ) = @_;
            push @states,
              [
                $f->convert_iter_to_child_iter(
                    $fs->convert_iter_to_child_iter($iter)
                ),
                $sel->iter_is_selected($iter)
              ];
            return (0);
        }
    );
    for my $row (@states) {
        $s->set( $row->[0], 6 => $row->[1] );
    }
}

sub recover_selected_state {
    my ($self) = @_;

    my $sel = $self->get_ui('students_select_list')->get_selection;
    my $f   = $self->{students_list_filtered};
    my $fs  = $self->{students_list_filtered_sorted};
    my $s   = $self->{students_list_store};
    $fs->foreach(
        sub {
            my ( $model, $path, $iter, $user ) = @_;
            if (
                $s->get(
                    $f->convert_iter_to_child_iter(
                        $fs->convert_iter_to_child_iter($iter)
                    ),
                    6
                )
              )
            {
                $sel->select_iter($iter);
            } else {
                $sel->unselect_iter($iter);
            }
            return (0);
        }
    );
}

sub search {
    my ($self) = @_;

    $self->save_selected_state();
    my $pattern = $self->get_ui('students_list_search')->get_text;
    my $s       = $self->{students_list_store};
    $s->foreach(
        sub {
            my ( $model, $path, $iter, $user ) = @_;
            my ( $id, $n, $nb ) = $s->get( $iter, 0, 1, 4 );
            $s->set(
                $iter,
                5 => (
                         ( !$pattern )
                      || $id =~ /$pattern/i
                      || ( defined($n)  && $n  =~ /$pattern/i )
                      || ( defined($nb) && $nb =~ /$pattern/i ) ? 1 : 0
                )
            );
            return (0);
        }
    );
    $self->recover_selected_state();
}

sub all {
    my ($self) = @_;

    $self->get_ui('students_list_search')->set_text('');
}

1;

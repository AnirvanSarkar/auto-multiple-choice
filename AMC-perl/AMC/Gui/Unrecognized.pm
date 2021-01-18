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

package AMC::Gui::Unrecognized;

use parent 'AMC::Gui';

use AMC::Basic;

use File::Spec::Functions qw/splitpath/;

use Gtk3;

use constant {
    INCONNU_FILE    => 0,
    INCONNU_SCAN    => 1,
    INCONNU_TIME    => 2,
    INCONNU_TIME_N  => 3,
    INCONNU_PREPROC => 4,
};

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            capture => '',
            callback_self => '',
            update_analysis_callback =>
              sub { debug "Missing update_analysis_callback"; },
            analysis_callback => sub { debug "Missing analysis_callback"; },
        },
        %oo
    );

    $self->open_window();

    return $self;
}

sub open_window {
    my ($self) = @_;
    
    my $store = Gtk3::ListStore->new(
        'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String',
        'Glib::String'
        );
    $self->{store} = $store;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade(
        $glade_xml,
        qw/unrecognized
          inconnu_tree scan_area preprocessed_area
          inconnu_hpaned inconnu_vpaned
          state_scanrecog state_scanrecog_label
          unrecog_process_button
          unrecog_delete_button
          unrecog_next_button unrecog_previous_button
          ur_frame_scan/
    );

    for (qw/scan preprocessed/) {
        AMC::Gui::PageArea::add_feuille( $self->get_ui( $_ . '_area' ) );
    }

    my $tree = $self->get_ui('inconnu_tree');
    
    $store->set_sort_column_id( INCONNU_TIME_N, 'ascending' );

    $tree->set_model($store);

    my $renderer;
    my $column;

    $renderer = Gtk3::CellRendererText->new;
    $column   = Gtk3::TreeViewColumn->new_with_attributes( "scan", $renderer,
        text => INCONNU_SCAN );
    $tree->append_column($column);
    $column->set_sort_column_id(INCONNU_SCAN);

    $renderer = Gtk3::CellRendererText->new;
    $column   = Gtk3::TreeViewColumn->new_with_attributes( "date", $renderer,
        text => INCONNU_TIME );
    $tree->append_column($column);
    $column->set_sort_column_id(INCONNU_TIME_N);

    $self->update();

    $tree->get_selection->set_mode('multiple');
    $tree->get_selection->signal_connect( "changed", \&line, $self );

    $self->get_ui('unrecognized')->show();

    $tree->get_selection->select_iter( $store->get_iter_first );
}

sub update {
    my ($self) = @_;

    $self->{capture}->begin_read_transaction('UNRC');
    my $failed =
      $self->{capture}
      ->dbh->selectall_arrayref( $self->{capture}->statement('failedList'),
        { Slice => {} } );
    $self->{capture}->end_transaction('UNRC');

    $self->{store}->clear;
    for my $ff (@$failed) {
        my $iter = $self->{store}->append;
        my $f    = $ff->{filename};
        $f =~ s:.*/::;
        my ( undef, undef, $scan_n ) =
          splitpath( $self->absolu( $ff->{filename} ) );
        my $preproc_file =
            $self->absolu('%PROJET/cr/diagnostic') . "/"
          . $scan_n . ".png";

        $self->{store}->set(
            $iter,                           INCONNU_SCAN,
            $f,                              INCONNU_FILE,
            $ff->{filename},                 INCONNU_TIME,
            format_date( $ff->{timestamp} ), INCONNU_TIME_N,
            $ff->{timestamp},                INCONNU_PREPROC,
            $preproc_file,
        );
    }
}

sub next {
    my ($self, $widget, @sel) = @_;
    
    @sel = () if ( !defined( $sel[0] ) );
    if ( !@sel ) {
        @sel = $self->get_ui('inconnu_tree')->get_selection->get_selected_rows;
        if ( $sel[0] ) {
            @sel = @{ $sel[0] };
        } else {
            @sel = ();
        }
    }
    my $iter;
    my $ok = 0;
    if ( @sel && defined( $sel[$#sel] ) ) {
        $iter = $self->{store}->get_iter( $sel[$#sel] );
        $ok   = $self->{store}->iter_next($iter);
    }
    $iter = $self->{store}->get_iter_first if ( !$ok );

    $self->get_ui('inconnu_tree')->get_selection->unselect_all;
    $self->get_ui('inconnu_tree')->get_selection->select_iter($iter) if ($iter);
}

sub prev {
    my ($self) = @_;
    
    my @sel = $self->get_ui('inconnu_tree')->get_selection->get_selected_rows;
    my $first_selected = $sel[0]->[0];
    my $iter;
    if ( defined($first_selected) ) {
        my $p =
          $self->{store}->get_path( $self->{store}->get_iter($first_selected) );
        if ( $p->prev ) {
            $iter = $self->{store}->get_iter($p);
        } else {
            $iter = '';
        }
    }
    $iter = $self->{store}->get_iter_first if ( !$iter );

    $self->get_ui('inconnu_tree')->get_selection->unselect_all;
    $self->get_ui('inconnu_tree')->get_selection->select_iter($iter) if ($iter);
}

sub delete {
    my ($self) = @_;
    
    my @iters;
    my @sel = ( $self->get_ui('inconnu_tree')->get_selection->get_selected_rows );
    @sel = @{ $sel[0] };
    return if ( !@sel );

    $self->{capture}->begin_transaction('rmUN');
    for my $s (@sel) {
        my $iter = $self->{store}->get_iter($s);
        my $file = $self->{store}->get( $iter, INCONNU_FILE );
        $self->{capture}->statement('deleteFailed')->execute($file);
        unlink $self->absolu($file);
        push @iters, $iter;
    }
    $self->next( '', @sel );
    for (@iters) { $self->{store}->remove($_); }
    &{$self->{update_analysis_callback}}( $self->{callback_self} );
    $self->{capture}->end_transaction('rmUN');
}

# call AMC-analyse to build the diagnostic image

sub analyse_diagnostic {
    my ($self) = @_;

    my @sel = $self->get_ui('inconnu_tree')->get_selection->get_selected_rows;
    my $first_selected = $sel[0]->[0];
    if ( defined($first_selected) ) {
        my $iter = $self->{store}->get_iter($first_selected);
        my $scan =
          $self->{config}->{shortcuts}
          ->absolu( $self->{store}->get( $iter, INCONNU_FILE ) );
        my $diagnostic_file = $self->{store}->get( $iter, INCONNU_PREPROC );

        if ( !-f $diagnostic_file ) {
            &{ $self->{analysis_callback} }(
                 $self->{callback_self},
                 f          => [$scan],
                 text       => __("Making diagnostic image..."),
                 progres    => 'diagnostic',
                 diagnostic => 1,
                 fin        => sub {
                     $self->line();
                 },
            );
        }
    }
}

sub set_hpaned {
    my ($self, $prop) = @_;

    $self->get_ui('inconnu_hpaned')->set_position($prop * $self->get_ui('inconnu_hpaned')->get_property('max-position'));
}

sub line {
    my ($self, $data) = @_;

    # when used as Gtk signal callback, $self is the second argument
    
    if ( $data && $data->isa("AMC::Gui::Unrecognized") ) {
        $self = $data;
    }

    if ( $self->{store}->get_iter_first ) {
        my @sel =
          $self->get_ui('inconnu_tree')->get_selection->get_selected_rows;
        my $first_selected = $sel[0]->[0];
        my $iter           = '';
        if ( defined($first_selected) ) {
            $iter = $self->{store}->get_iter($first_selected);
        }
        if ($iter) {
            $self->get_ui('inconnu_tree')
              ->scroll_to_cell( $first_selected, undef, 0, 0, 0 );
            my $scan =
              $self->{config}->{shortcuts}
              ->absolu( $self->{store}->get( $iter, INCONNU_FILE ) );
            if ( -f $scan ) {
                $self->get_ui('scan_area')->set_content( image => $scan );
            } else {
                debug_and_stderr "Scan not found: $scan";
                $self->get_ui('scan_area')->set_content();
            }

            my $preproc = $self->{store}->get( $iter, INCONNU_PREPROC );

            if ( -f $preproc ) {
                $self->get_ui('preprocessed_area')
                    ->set_content( image => $preproc );
                $self->set_hpaned(0.5);
            } else {
                $self->get_ui('preprocessed_area')->set_content();
                $self->set_hpaned(1);
            }

            if ( $self->get_ui('scan_area')->get_image ) {
                my $scan_n = $scan;
                $scan_n =~ s:^.*/::;
                $self->set_state( 'question', $scan_n );
            } else {
                $self->set_state( 'error',
                    sprintf( ( __ "Error loading scan %s" ), $scan ) );
            }
            $self->actions( -f $preproc ? 2 : 1 );
        } else {
            $self->get_ui('scan_area')->set_content();
            $self->get_ui('preprocessed_area')->set_content();
            $self->set_state( 'question', __ "No scan selected" );
            $self->actions(0);
        }
    } else {

        # empty list
        $self->set_state( 'info', __ "No more unrecognized scans" );
        $self->get_ui('scan_area')->set_content();
        $self->get_ui('preprocessed_area')->set_content();
        $self->actions(-1);
    }
}

sub actions {
    my ( $self, $available ) = @_;
    my %actions = (
        delete   => $available > 0,
        process  => $available == 1,
        next     => $available >= 0,
        previous => $available >= 0,
    );
    for my $k ( keys %actions ) {
        if ( $actions{$k} > 0 ) {
            $self->get_ui( 'unrecog_' . $k . '_button' )->show;
        } else {
            $self->get_ui( 'unrecog_' . $k . '_button' )->hide;
        }
    }
}
    
sub set_state {
    my ( $self, $type, $message ) = @_;
    my $w     = $self->get_ui('scan_recog');
    my $label = $self->get_ui('scan_recog_label');
    if ( defined($type) && $w ) {
        if ( $type eq 'none' ) {
            $w->hide();
        } else {
            $w->show();
            $w->set_message_type($type);
        }
    }
    $label->set_text($message)
      if ( defined($message) && $label );
}

1;

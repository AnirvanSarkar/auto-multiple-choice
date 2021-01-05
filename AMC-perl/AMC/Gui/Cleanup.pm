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

package AMC::Gui::Cleanup;

use parent 'AMC::Gui';

use AMC::Basic;

use File::Path qw/remove_tree/;

use Glib qw/TRUE FALSE/;
use Gtk3;

use_gettext();

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            capture => '',
        },
        %oo
    );

    $self->dialog();

    return $self;
}

my @cleanup_components = (
    {
        id    => 'zooms',
        short => __("zooms"),
        text  => __(
"boxes images are extracted from the scans while processing automatic data capture. They can be removed if you don't plan to use the zooms dialog to check and correct boxes categorization. They can be recovered processing again automatic data capture from the same scans."
        ),
        size => sub {
            my ($self) = @_;
            return (
                $self->file_size( { recursive => 5 },
                    $self->absolu('%PROJET/cr/zooms') )
                  + $self->{capture}->zooms_total_size_transaction()
            );
        },
        action => sub {
            my ($self) = @_;
            return (
                remove_tree(
                    $self->absolu('%PROJET/cr/zooms'),
                    { verbose => 0, safe => 1, keep_root => 1 } ) +
                  $self->{capture}->zooms_cleanup_transaction()
            );
        },
    },
    {
        id    => 'matching_reports',
        short => __("layout reports"),
        text  => __(
"these images are intended to show how the corner marks have been recognized and positioned on the scans. They can be safely removed once the scans are known to be well-recognized. They can be recovered processing again automatic data capture from the same scans."
        ),
        size => sub {
            my ($self) = @_;
            return (
                $self->file_size(
                    { pattern => '^page-', recursive => 1 },
                    $self->absolu('%PROJET/cr/')
                )
            );
        },
        action => sub {
            my ($self) = @_;
            my $dir = $self->absolu('%PROJET/cr/');
            if ( opendir( CRDIR, $dir ) ) {
                my @files =
                  map { "$dir/$_" } grep { /^page-/ } readdir(CRDIR);
                closedir(CRDIR);
                return ( unlink(@files) );
            } else {
                return (0);
            }
        },
    },
    {
        id    => 'annotated_pages',
        short => __("annotated pages"),
        text  => __(
"jpeg annotated pages are made before beeing assembled to PDF annotated files. They can safely be removed, and will be recovered automatically the next time annotation will be requested."
        ),
        size => sub {
            my ($self) = @_;
            return (
                $self->file_size(
                    { recursive => 5 },
                    $self->{config}->{shortcuts}
                      ->absolu('%PROJET/cr/corrections/jpg')
                )
            );
        },
        action => sub {
            my ($self) = @_;
            return (
                remove_tree(
                    $self->{config}->{shortcuts}
                      ->absolu('%PROJET/cr/corrections/jpg'),
                    { verbose => 0, safe => 1, keep_root => 1 }
                )
            );
        },
    },
);

sub file_size {
    my ( $self, $oo, @files ) = @_;
    my $s = 0;
    $oo->{recursive}--;
  FILE: for my $f (@files) {
        if ( -f $f ) {
            $s += -s $f;
        } elsif ( -d $f ) {
            if ( $oo->{recursive} >= 0 ) {
                if ( opendir( SDIR, $f ) ) {
                    my @dir_files = map { "$f/$_"; }
                      grep { !$oo->{pattern} || /$oo->{pattern}/ }
                      grep { !/^\.{1,2}$/ } readdir(SDIR);
                    closedir(SDIR);
                    $s += $self->file_size( {%$oo}, @dir_files );
                }
            }
        }
    }
    return ($s);
}

my @size_units = ( 'k', 'M', 'G', 'T', 'P' );

sub human_readable_size {
    my ($s) = @_;
    my $i = 0;
    while ( $s >= 1024 ) {
        $s /= 1024;
        $i++;
    }
    if ( $i == 0 ) {
        return ($s);
    } else {
        return ( sprintf( '%.3g%s', $s, $size_units[ $i - 1 ] ) );
    }
}

sub table_sep {
    my ( $t, $y, $x ) = @_;
    my $sep = Gtk3::HSeparator->new();
    $t->attach( $sep, 0, $x, $y, $y + 1, [ "expand", "fill" ], [], 0, 0 );
}

sub dialog {
    my ($self) = @_;
    
    my %files;
    my %cb;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade($glade_xml, qw/cleanup components/);

    my $dialog   = $self->get_ui('cleanup');
    my $notebook = $self->get_ui('components');
    
    for my $c (@cleanup_components) {
        my $t = $c->{text};
        my $s = undef;
        if ( $c->{size} ) {
            $s = &{ $c->{size} }($self);
            $t .= "\n"
              . __("Total size of concerned files:") . " "
              . human_readable_size($s);
        }
        my $label = Gtk3::Label->new($t);
        $label->set_justify('left');
        $label->set_max_width_chars(50);
        $label->set_line_wrap(1);
        $label->set_line_wrap_mode('word');

        my $check = Gtk3::CheckButton->new;
        $c->{check} = $check;
        my $short_label = Gtk3::Label->new( $c->{short} );
        $short_label->set_justify('center');
        $short_label->set_sensitive( !( defined($s) && $s == 0 ) );
        my $hb = Gtk3::HBox->new();
        $hb->pack_start( $check,       FALSE, FALSE, 0 );
        $hb->pack_start( $short_label, TRUE,  TRUE,  0 );
        $hb->show_all;

        $notebook->append_page_menu( $label, $hb, undef );
    }
    $notebook->show_all;

    my $reponse = $dialog->run();

    for my $c (@cleanup_components) {
        $c->{active} = $c->{check}->get_active();
    }

    $dialog->destroy();
    Gtk3::main_iteration while (Gtk3::events_pending);

    debug "RESPONSE=$reponse";

    return () if ( $reponse != 10 );

    my $n = 0;

    for my $c (@cleanup_components) {
        if ( $c->{active} ) {
            debug "Removing " . $c->{id} . " ...";
            $n += &{ $c->{action} }($self);
        }
    }

    $dialog = Gtk3::MessageDialog->new( $self->{parent_window}, 'destroy-with-parent',
        'info', 'ok', __("%s files were removed."), $n );
    $dialog->run;
    $dialog->destroy;
}    

1;

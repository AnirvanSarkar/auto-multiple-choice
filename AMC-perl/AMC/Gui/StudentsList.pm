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

package AMC::Gui::StudentsList;

use parent 'AMC::Gui';

use AMC::Basic;

use File::Spec::Functions qw/splitpath catpath/;

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            callback_self => '',
            callback   => sub { debug "Error: missing StudentsList callback"; },
            main_gui   => '',
            main_prefs => '',
        },
        %oo
    );

    return $self;
}

sub dialog {
    my ($self) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade( $glade_xml, qw/liste_dialog/ );
    my $dial = $self->get_ui('liste_dialog');

    # Choose starting directory from the last students list file (if
    # existing), or the project directory

    my @f;
    if ( $self->get('listeetudiants') ) {
        @f = splitpath( $self->get_absolute('listeetudiants') );
    } else {
        @f = splitpath( $self->absolu('%PROJET/') );
    }
    $f[2] = '';

    $dial->set_current_folder( catpath(@f) );

    my $ret = $dial->run();
    debug("Names list file choice [$ret]");

    my $file = clean_gtk_filenames( $dial->get_filename() );
    $dial->destroy();

    if ( $ret eq '1' ) {

        # file chosen
        debug( "List: " . $file );
        &{ $self->{callback} }( $self->{callback_self}, set => $file );
    } elsif ( $ret eq '2' ) {

        # No list
        &{ $self->{callback} }( $self->{callback_self}, set => '' );
    } else {

        # Cancel
    }

}

# dialog to choose a students list file *and* a primary key

sub dialog_with_key {
    my ($self) = @_;

    $self->set_prefs();

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/Key.glade/i;

    $self->read_glade( $glade_xml, qw/studentslist sl_f_listeetudiants/ );

    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'sl',
        keys   => [ 'listeetudiants' ]
    );
    $self->config_file();
    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'sl',
        keys   => ['liste_key']
    );

    $self->get_ui('studentslist')->run;

    $self->{prefs}->reprend_pref( prefix => 'sl' );
    $self->{main_prefs}->transmet_pref(
        $self->{main_gui},
        prefix => 'pref_assoc',
        keys   => ['project:liste_key']
    );

    $self->get_ui('studentslist')->destroy;

}

sub config_file {
    my ($self) = @_;

    $self->{prefs}->reprend_pref( prefix => 'sl' );

    # Updates main GUI
    &{ $self->{callback} }( $self->{callback_self} );

    # Updates dialog
    &{ $self->{callback} }( $self->{callback_self}, 
        nolabel => 1,
        prefs   => $self->{prefs},
        gui     => $self->{main},
        prefix  => 'sl'
    );
}

1;

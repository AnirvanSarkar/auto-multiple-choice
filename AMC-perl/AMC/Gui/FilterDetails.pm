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

package AMC::Gui::FilterDetails;

use parent 'AMC::Gui';

use AMC::Basic;

use_gettext();

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            main_gui     => '',
            main_prefs   => '',
        },
        %oo
    );

    $self->store_register( filter => $self->{main_prefs}->store_get('filter') );

    $self->dialog();

    return $self;
}

sub dialog {
    my ($self) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade($glade_xml, qw/filter_details filter_text/ );

    debug "Filter details: conf->details GUI";

    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'filter_details',
        root   => "project:"
    );
    
    my $r = $self->get_ui('filter_details')->run();
    if ( $r == 10 ) {
        $self->set_local_keys('filter');
        debug "Filter details: new value->local";
        $self->{prefs}->reprend_pref(
            prefix    => 'filter_details',
            container => 'local'
        );
        $self->get_ui('filter_details')->destroy;
        debug "Filter details: local->main GUI";
        $self->{main_prefs}->transmet_pref(
            $self->{main_gui},
            prefix    => 'pref_prep',
            keys      => ["local:filter"],
            container => 'project'
        );
    } else {
        $self->get_ui('filter_details')->destroy;
    }
}

sub update {
    my ($self) = @_;

    $self->set_local_keys('filter');
    $self->{prefs}
      ->reprend_pref( prefix => 'filter_details', container => 'local' );
    my $b      = $self->get_ui('filter_text')->get_buffer;
    my $filter = $self->get('local:filter');
    if ($filter) {
        $b->set_text( "AMC::Filter::register::$filter"->description );
    } else {
        $b->set_text('');
    }
}

1;

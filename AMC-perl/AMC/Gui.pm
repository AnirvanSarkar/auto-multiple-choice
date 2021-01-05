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

package AMC::Gui;

use AMC::Basic;

sub new {
    my ( $class, %oo ) = @_;

    my $self = {
        config        => '',
        parent_window => '',
        main          => '',
        monitor       => '',
        ui            => {}
    };

    for ( keys %oo ) {
        $self->{$_} = $oo{$_} if ( exists( $self->{$_} ) );
    }

    bless( $self, $class );

    return $self;
}

sub merge_config {
    my ( $self, $default, %oo ) = @_;

    for ( keys %$default ) {
        if ( exists( $oo{$_} ) ) {
            $self->{$_} = $oo{$_};
        } else {
            $self->{$_} = $default->{$_};
        }
    }
}

sub get_ui {
    my ( $self, $key ) = @_;
    return ( $self->{ui}->{$key} );
}

sub read_glade {
    my ( $self, $glade_file, @widgets ) = @_;
    my $g = Gtk3::Builder->new();
    debug "Reading glade file " . $glade_file;
    $g->set_translation_domain('auto-multiple-choice');
    $g->add_from_file($glade_file);
    for my $i (@widgets) {
        $self->{ui}->{$i} = $g->get_object($i);
        if ( ref( $self->{ui}->{$i} ) =~ /::(FileChooser|About)?Dialog$/
            && !$self->{ui}->{$i}->is_visible() )
        {
            debug "Found modal dialog: $i";
            if ( $self->{parent_window} ) {
                $self->{ui}->{$i}->set_transient_for( $self->{parent_window} );
                $self->{ui}->{$i}->set_modal(1);
            }
        }
        if ( $self->{ui}->{$i} ) {
            $self->{ui}->{$i}->set_name($i) if ( $i !~ /^(apropos)$/ );
        } else {
            debug_and_stderr
              "WARNING: Object $i not found in $glade_file glade file.";
        }
    }
    $g->connect_signals( undef, $self );
    $self->{main} = $g;

    my $monitor=$self->{monitor};
    if(!$monitor) {
        $monitor=$glade_file;
        $monitor =~ s/.*\///g;
        $monitor =~ s/\.glade$//gi;
    }

    if ( $monitor ne 'none' && @widgets) {
        my $window = $self->get_ui( $widgets[0] );
        if ( $window && $window->isa("Gtk3::Window") ) {
            AMC::Gui::WindowSize::size_monitor(
                $window,
                {
                    config => $self->{config},
                    key    => "global:" . $monitor . "_window_size"
                }
            );
        }
    }
}

sub absolu {
    my ( $self, @args ) = @_;
    return ( $self->{config}->{shortcuts}->absolu(@args) );
}

sub absolu_base {
    my ( $self, @args ) = @_;
    return ( $self->{config}->{shortcuts}->absolu_base(@args) );
}

sub relatif {
    my ( $self, @args ) = @_;
    return ( $self->{config}->{shortcuts}->relatif(@args) );
}

sub relatif_base {
    my ( $self, @args ) = @_;
    return ( $self->{config}->{shortcuts}->relatif_base(@args) );
}

sub set {
    my ( $self, @args ) = @_;
    return ( $self->{config}->set(@args) );
}

sub set_local_keys {
    my ( $self, @args ) = @_;
    return ( $self->{config}->set_local_keys(@args) );
}

sub set_relatif_os {
    my ( $self, @args ) = @_;
    return ( $self->{config}->set_relatif_os(@args) );
}

sub get {
    my ( $self, @args ) = @_;
    return ( $self->{config}->get(@args) );
}

sub get_absolute {
    my ( $self, @args ) = @_;
    return ( $self->{config}->get_absolute(@args) );
}

sub set_prefs {
    my ($self) = @_;

    $self->{prefs} = AMC::Gui::Prefs::new(
        config      => $self->{config},
        shortcuts   => $self->{config}->{shortcuts},
        alternate_w => $self->{ui},
    ) if ( !$self->{prefs} );
}

sub store_register {
    my ( $self, @args ) = @_;

    $self->set_prefs();
    $self->{prefs}->store_register(@args);
}

# Check that the given project name is OK

sub restricted_check {
    my ( $self, $text, $warning, $chars ) = @_;
    my $nom = $text->get_text();
    if ( !$self->get('nonascii_projectnames') ) {
        if ( $nom =~ s/[^$chars]//g ) {
            $text->set_text($nom);
            $warning->show();

            my $col = Gtk3::Gdk::RGBA::parse('#FFC0C0');
            for (qw/normal active/) {
                $text->override_background_color( $_, $col );
            }
            Glib::Timeout->add(
                500,
                sub {
                    for (qw/normal active/) {
                        $text->override_background_color( $_, undef );
                    }
                    return 0;
                }
            );
        }
    }
}

1;

#
# Copyright (C) 2019-2021 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::Decoder::Barcode;

use AMC::Decoder;
use AMC::Basic;

use XML::Simple;

our @ISA = ("AMC::Decoder");

use_gettext;

#####################################################################
# These methods should be overwritten for derivated classes (that
# describe decoders that AMC can handle)
#####################################################################

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    bless( $self, $class );
    return $self;
}

sub decode_from_path {
    my ( $self, $path, $unlink_when_finished ) = @_;
    my $r;
    my @cmd = ( "zbarimg", "--xml", "-q", $path );
    debug( "Calling: " . join( ' ', @cmd ) );
    my $xml = '';
    if ( open( ZBAR, "-|", @cmd ) ) {
        while (<ZBAR>) {
            $xml .= $_;
        }
        close ZBAR;
        my $result = XMLin( $xml, ForceArray => ['symbol'] );
        my $s      = $result->{source}->{index}->{symbol};
        if ($s) {
            my $best = $s->[0];
            for my $i ( 1 .. $#{$s} ) {
                $best = $s->[$i]
                  if ( $s->[$i]->{quality} > $best->{quality} );
            }
            $r = {
                ok     => 1,
                status => "$best->{type} Q:$best->{quality}",
                value  => $best->{data}
            };
        } else {
            $r = {
                ok     => 0,
                status => "no barcode found",
                value  => ''
            };
        }
    } else {
        $r = {
            ok     => 0,
            status => "failed: $!",
            value  => ''
        };
    }
    unlink($path) if ($unlink_when_finished);
    return ($r);
}

sub decode_image {
    my ( $self, $path, $blob ) = @_;

    if ( -f $path ) {
        return ( $self->decode_from_path($path) );
    } elsif ($blob) {
        return ( $self->decode_from_path( blob_to_file($blob), 1 ) );
    } else {
        return (
            {
                ok     => 0,
                status => 'no image',
                value  => ''
            }
        );
    }
}

1;

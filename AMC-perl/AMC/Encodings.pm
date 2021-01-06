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

package AMC::Encodings;

use AMC::Basic;

BEGIN {
    use Exporter ();
    our ( $VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS );

    @ISA         = qw(Exporter);
    @EXPORT      = qw( &get_enc );
    %EXPORT_TAGS = ();               # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK = qw();
}

use_gettext();

my $encodages = [
    {
        qw/inputenc latin1 iso ISO-8859-1/,

        txt => 'ISO-8859-1 (' . __(
            # TRANSLATORS: one of the available text file encodings
            "Western Europe"
          )
          . ')'
    },

    {
        qw/inputenc latin2 iso ISO-8859-2/,
        txt => 'ISO-8859-2 (' . __(
            # TRANSLATORS: one of the available text file encodings
            "Central Europe"
          )
          . ')'
    },

    {
        qw/inputenc latin3 iso ISO-8859-3/,
        txt => 'ISO-8859-3 (' . __(
            # TRANSLATORS: one of the available text file encodings
            "Southern Europe"
          )
          . ')'
    },

    {
        qw/inputenc latin4 iso ISO-8859-4/,
        txt => 'ISO-8859-4 (' . __(
            # TRANSLATORS: one of the available text file encodings
            "Northern Europe"
          )
          . ')'
    },

    {
        qw/inputenc latin5 iso ISO-8859-5/,
        txt => 'ISO-8859-5 (' . __(
            # TRANSLATORS: one of the available text file encodings
            "Cyrillic"
          )
          . ')'
    },

    {
        qw/inputenc latin9 iso ISO-8859-9/,
        txt => 'ISO-8859-9 (' . __(
            # TRANSLATORS: one of the available text file encodings
            "Turkish"
          )
          . ')'
    },

    {
        qw/inputenc latin10 iso ISO-8859-10/,
        txt => 'ISO-8859-10 (' . __(
            # TRANSLATORS: one of the available text file encodings
            "Northern"
          )
          . ')'
    },

    {
        qw/inputenc utf8x iso UTF-8/,
        txt => 'UTF-8 (' . __(
            # TRANSLATORS: one of the available text file encodings
            "Unicode"
          )
          . ')'
    },
    {
        qw/inputenc cp1252 iso cp1252/,
        txt   => 'Windows-1252',
        alias => [ 'Windows-1252', 'Windows' ]
    },

    {
        qw/inputenc applemac iso MacRoman/,
        txt => 'Macintosh '
          . __
          # TRANSLATORS: one of the available text file encodings
          "Western Europe"
    },

    {
        qw/inputenc macce iso MacCentralEurRoman/,
        txt => 'Macintosh ' . __
    # TRANSLATORS: one of the available text file encodings
            "Central Europe"
    },
];

sub encodings {
    return (@$encodages);
}

sub get_enc {
    my ($txt) = @_;
    for my $e (@$encodages) {
        return ($e)
          if ( $e->{inputenc} =~ /^$txt$/i
            || $e->{iso} =~ /^$txt$/i );
        if ( $e->{alias} ) {
            for my $a ( @{ $e->{alias} } ) {
                return ($e) if ( $a =~ /^$txt$/i );
            }
        }
    }
    return ('');
}

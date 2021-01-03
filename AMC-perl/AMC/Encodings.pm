# -*- perl -*-
#
# Copyright (C) 2020 Alexis Bienvenue <paamc@passoire.fr>
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

        # TRANSLATORS: for encodings
        txt => 'ISO-8859-1 (' . __("Western Europe") . ')'
    },

    # TRANSLATORS: for encodings
    {
        qw/inputenc latin2 iso ISO-8859-2/,
        txt => 'ISO-8859-2 (' . __("Central Europe") . ')'
    },

    # TRANSLATORS: for encodings
    {
        qw/inputenc latin3 iso ISO-8859-3/,
        txt => 'ISO-8859-3 (' . __("Southern Europe") . ')'
    },

    # TRANSLATORS: for encodings
    {
        qw/inputenc latin4 iso ISO-8859-4/,
        txt => 'ISO-8859-4 (' . __("Northern Europe") . ')'
    },

    # TRANSLATORS: for encodings
    {
        qw/inputenc latin5 iso ISO-8859-5/,
        txt => 'ISO-8859-5 (' . __("Cyrillic") . ')'
    },

    # TRANSLATORS: for encodings
    {
        qw/inputenc latin9 iso ISO-8859-9/,
        txt => 'ISO-8859-9 (' . __("Turkish") . ')'
    },

    # TRANSLATORS: for encodings
    {
        qw/inputenc latin10 iso ISO-8859-10/,
        txt => 'ISO-8859-10 (' . __("Northern") . ')'
    },

    # TRANSLATORS: for encodings
    { qw/inputenc utf8x iso UTF-8/, txt => 'UTF-8 (' . __("Unicode") . ')' },
    {
        qw/inputenc cp1252 iso cp1252/,
        txt   => 'Windows-1252',
        alias => [ 'Windows-1252', 'Windows' ]
    },

    # TRANSLATORS: for encodings
    {
        qw/inputenc applemac iso MacRoman/,
        txt => 'Macintosh ' . __ "Western Europe"
    },

    # TRANSLATORS: for encodings
    {
        qw/inputenc macce iso MacCentralEurRoman/,
        txt => 'Macintosh ' . __ "Central Europe"
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

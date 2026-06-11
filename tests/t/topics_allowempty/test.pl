#! /usr/bin/env perl
#
# Copyright (C) 2026 Alexis Bienvenüe <paamc@passoire.fr>
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

use utf8;

require "./AMC/Test.pm";

my $t = AMC::Test->new(
    dir             => __FILE__,
    seuil           => 0.15,
    n_copies        => 10,
    perfect_copy    => [],
    export_full_csv => [
        { -copy => 3, -question => 'hist:score', -score => 2 },
        { -copy => 3, -question => 'hist:max',   -score => 2 },
        { -copy => 3, -question => 'geo:score',  -score => 2 },
        { -copy => 3, -question => 'geo:max',    -score => 2 },

        { -copy => 4, -question => 'hist:score', -score => 1 },
        { -copy => 4, -question => 'hist:max',   -score => 2 },
        { -copy => 4, -question => 'geo:score',  -score => 1 },
        { -copy => 4, -question => 'geo:max',    -score => 4 },

        { -copy => 5, -question => 'hist:score', -score => 1 },
        { -copy => 5, -question => 'hist:max',   -score => 1 },
        { -copy => 5, -question => 'geo:score',  -score => 3 },
        { -copy => 5, -question => 'geo:max',    -score => 4 },

        { -copy => 6, -question => 'hist:score', -score => 1 },
        { -copy => 6, -question => 'hist:max',   -score => 2 },
        { -copy => 6, -question => 'geo:score',  -score => 5 },
        { -copy => 6, -question => 'geo:max',    -score => 6 },

        { -copy => 10, -question => 'hist:score', -score => '' },
        { -copy => 10, -question => 'hist:max',   -score => '' },
        { -copy => 10, -question => 'geo:score',  -score => 4 },
        { -copy => 10, -question => 'geo:max',    -score => 6 },

    ],
    export_full_ods => [
        { -copy => 3, -question => 'hist', -score => '100%' },
        { -copy => 3, -question => 'geo',  -score => '100%' },

        { -copy => 4, -question => 'hist', -score => '50%' },
        { -copy => 4, -question => 'geo',  -score => '25%' },

        { -copy => 5, -question => 'hist', -score => '100%' },
        { -copy => 5, -question => 'geo',  -score => '75%' },

        { -copy => 6, -question => 'hist', -score => '50%' },
        { -copy => 6, -question => 'geo',  -score => '83%' },

        { -copy => 10, -question => 'hist', -score => '' },
        { -copy => 10, -question => 'geo',  -score => '67%' },
    ],
)->default_process;

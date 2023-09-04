#! /usr/bin/env perl
#
# Copyright (C) 2023 Alexis Bienvenüe <paamc@passoire.fr>
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

AMC::Test->new(
    dir             => __FILE__,
    filter          => 'plain',
    tex_engine      => 'xelatex',
    seuil           => 0.5,
    perfect_copy    => '',
    annote          => [3],
    annote_position => 'marges',
    annote_color    => 'grey',
    verdict         => 'TOTAL : %S/%M => %s/%m',
    export_full_csv => [
        { -copy => 1, -question => 'A0:score', -score => 21 },
        { -copy => 1, -question => 'A0:max',   -score => 19 },
        { -copy => 1, -question => 'A0:level', -score => 'X' },
        { -copy => 1, -question => 'A:score',  -score => 30 },
        { -copy => 1, -question => 'A:max',    -score => 28 },
        { -copy => 1, -question => 'A:level',  -score => 'X' },
        { -copy => 1, -question => 'B:score',  -score => 16 },
        { -copy => 1, -question => 'B:max',    -score => 16 },
        { -copy => 1, -question => 'Bi:score', -score => 3 },
        { -copy => 1, -question => 'Bi:max',   -score => 3 },
        { -copy => 1, -question => 'M:score',  -score => 18 },
        { -copy => 1, -question => 'M:max',    -score => 17 },

        { -copy => 2, -question => 'A0:score', -score => -3 },
        { -copy => 2, -question => 'A0:max',   -score => 19 },
        { -copy => 2, -question => 'A0:ratio', -score => 0 },
        { -copy => 2, -question => 'A0:level', -score => 'F' },
        { -copy => 2, -question => 'A:score',  -score => -2 },
        { -copy => 2, -question => 'A:max',    -score => 28 },
        { -copy => 2, -question => 'A:ratio', -score => -2 / 28, -digits => 4 },
        { -copy => 2, -question => 'A:level', -score => 'Z' },
        { -copy => 2, -question => 'B:score', -score => -1 },
        { -copy => 2, -question => 'B:max',   -score => 16 },
        { -copy => 2, -question => 'B:ratio', -score => -1 / 16, -digits => 4 },
        { -copy => 2, -question => 'M:score', -score => 1 },
        { -copy => 2, -question => 'M:max',   -score => 17 },
        { -copy => 2, -question => 'M:ratio', -score => 0.0588, -digits => 4 },

        { -copy => 3, -question => 'A0:score', -score => 5 },
        { -copy => 3, -question => 'A0:max',   -score => 19 },
        { -copy => 3, -question => 'A0:ratio', -score => 5 / 19, -digits => 4 },
        { -copy => 3, -question => 'A0:level', -score => 'C' },
        { -copy => 3, -question => 'A:score',  -score => 9 },
        { -copy => 3, -question => 'A:max',    -score => 28 },
        { -copy => 3, -question => 'A:ratio',  -score => 9 / 28, -digits => 4 },
        { -copy => 3, -question => 'A:level',  -score => 'C' },
        { -copy => 3, -question => 'B:score',  -score => 10 },
        { -copy => 3, -question => 'B:max',    -score => 17 },
        { -copy => 3, -question => 'B:ratio', -score => 10 / 17, -digits => 4 },
        { -copy => 3, -question => 'Bi:score', -score => '' },
        { -copy => 3, -question => 'Bi:max',   -score => '' },
        { -copy => 3, -question => 'Bi:ratio', -score => '' },
        { -copy => 3, -question => 'M:score',  -score => 7 },
        { -copy => 3, -question => 'M:max',    -score => 17 },
        { -copy => 3, -question => 'M:ratio',  -score => 7 / 17, -digits => 4 },
    ],

    export_full_ods => [
        { -copy => 1, -question => 'A0', -score => 21 / 19, -digits => 2 },
        { -copy => 1, -question => 'A',  -score => '107%' },
        { -copy => 1, -question => 'B',  -score => '100%' },
        { -copy => 1, -question => 'Bi', -score => '100%' },
        { -copy => 1, -question => 'M',  -score => '106%' },

        { -copy => 2, -question => 'A0', -score => -3 / 19, -digits => 2 },
        { -copy => 2, -question => 'A',  -score => '-7%' },
        { -copy => 2, -question => 'B',  -score => '-6%' },
        { -copy => 2, -question => 'Bi', -score => '-33%' },
        { -copy => 2, -question => 'M',  -score => '6%' },

        { -copy => 3, -question => 'A0', -score => 5 / 19, -digits => 2 },
        { -copy => 3, -question => 'A',  -score => '32%' },
        { -copy => 3, -question => 'B',  -score => '59%' },
        { -copy => 3, -question => 'Bi', -score => '' },
        { -copy => 3, -question => 'M',  -score => '41%' },
    ],

    check_topics => [
        {
            -id      => 'A0',
            -copy    => 1,
            -message => 'X : acquis avec bonus (21 > 19)'
        },
        {
            -id      => 'A0',
            -copy    => 1,
            -color => '#00b935'
        },
        { -id => 'A0', -copy => 2, -message => 'F : à travailler' },
        { -id => 'A0', -copy => 2, -color => '#ff2d3a' },
        { -id => 'A0', -copy => 3, -message => 'C : à renforcer (0.263)' },
        { -id => 'A0', -copy => 3, -color => '#ff9f2d' },
    ],
)->default_process;


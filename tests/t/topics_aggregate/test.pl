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

require "./AMC/Test.pm";

AMC::Test->new(
    dir             => __FILE__,
    filter          => 'plain',
    perfect_copy    => [1],
    export_full_csv => [
        { -copy => 2, -question => 'ASs:score', -score => 14 },
        { -copy => 2, -question => 'ASs:max',   -score => 19 },
        {
            -copy     => 2,
            -question => 'ASr:score',
            -score    => 3 / 4 + 7 / 10 + 4 / 5,
            -digits   => 4
        },
        { -copy => 2, -question => 'ASr:max',   -score => 3 },
        { -copy => 2, -question => 'AMs:score', -score => 7 },
        { -copy => 2, -question => 'AMs:max',   -score => 10 },
        { -copy => 2, -question => 'Ams:score', -score => 3 },
        { -copy => 2, -question => 'Ams:max',   -score => 4 },
        { -copy => 2, -question => 'AMr:score', -score => 0.8 },
        { -copy => 2, -question => 'AMr:max',   -score => 1 },
        { -copy => 2, -question => 'Amr:score', -score => 0.7 },
        { -copy => 2, -question => 'Amr:max',   -score => 1 },
        { -copy => 2, -question => 'c3:score',  -score => 2 },
        { -copy => 2, -question => 'c3:max',    -score => 4 },
        { -copy => 2, -question => 'c23:score', -score => 3 },
        { -copy => 2, -question => 'c23:max',   -score => 4 },
    ],
    export_full_ods => [
        { -copy => 2, -question => 'ASs', -score => 14 / 19, -digits => 4 },
        {
            -copy     => 2,
            -question => 'ASr',
            -score    => ( 3 / 4 + 7 / 10 + 4 / 5 ) / 3,
            -digits   => 4
        },
        { -copy => 2, -question => 'AMs', -score => 7 },
        { -copy => 2, -question => 'Ams', -score => 3 },
        { -copy => 2, -question => 'AMr', -score => '80%' },
        { -copy => 2, -question => 'Amr', -score => '70%' },
        { -copy => 2, -question => 'c3',  -score => 2 },
        { -copy => 2, -question => 'c23', -score => '75%' },
    ],
)->default_process;

#! /usr/bin/perl
#
# Copyright (C) 2012-2021 Alexis Bienvenüe <paamc@passoire.fr>
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
    tex_engine      => 'pdflatex',
    seuil           => 0.5,
    perfect_copy    => '',
    export_full_csv => [
        { -copy => 1, -question => 'capitalist', -abc   => 'A' },
        { -copy => 1, -question => 'children',   -abc   => 'E' },
        { -copy => 1, -question => 'local',      -abc   => 'B' },
        { -copy => 1, -question => 'existence',  -abc   => 'A' },
        { -copy => 1, -question => 'safety1',    -score => 99 },
        { -copy => 1, -question => 'safety2',    -score => 1 },
        { -copy => 1, -question => 'safety3',    -score => 1 },
        { -copy => 1, -question => 'hyg1',       -score => 4 },
        { -copy => 1, -question => 'hyg2',       -score => 3 },
        { -copy => 1, -question => 'hyg3',       -score => 4 },
        { -copy => 1, -question => 'hyg4',       -score => 5 },
        { -copy => 1, -question => 'hyg5',       -score => 2 },
        { -copy => 1, -question => 'hyg6',       -score => 2 },
        { -copy => 1, -question => 'hyg7',       -score => 1 },
        { -copy => 1, -question => 'hyg8',       -score => 5 },
        { -copy => 1, -question => 'hyg9',       -score => 4 },
    ],
)->default_process;


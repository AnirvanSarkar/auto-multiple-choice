#! /usr/bin/env perl
#
# Copyright (C) 2025 Alexis Bienvenüe <paamc@passoire.fr>
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
    seuil           => 0.5,
    perfect_copy    => [4],
    export_full_csv => [
        { -copy => 1, -question => 'prez',    -score => 1 },
        { -copy => 1, -question => 'nb-ue',   -score => 1 },
        { -copy => 1, -question => 'fx',      -score => 3 },
        { -copy => 1, -question => 'R.ect-a', -score => 3 },
        { -copy => 1, -question => 'R.ect-b', -score => 3 },

        { -copy => 2, -question => 'prez',    -score => 0 },
        { -copy => 2, -question => 'nb-ue',   -score => 0 },
        { -copy => 2, -question => 'fx',      -score => 0 },
        { -copy => 2, -question => 'R.ect-a', -score => 0 },
        { -copy => 2, -question => 'R.ect-b', -score => 1 },

        { -copy => 3, -question => 'prez',    -score => 1 },
        { -copy => 3, -question => 'nb-ue',   -score => 0 },
        { -copy => 3, -question => 'fx',      -score => 1 },
        { -copy => 3, -question => 'R.ect-a', -score => 1 },
        { -copy => 3, -question => 'R.ect-b', -score => 2 },
    ],
)->default_process;

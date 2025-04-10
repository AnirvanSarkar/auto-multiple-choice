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
    perfect_copy    => [4],
    tex_engine      => 'latexmk -r lmk.py -pdf -outdir=_build',
    export_full_csv => [
        { -copy => 1, -question => 'list',      -score => 1 },
        { -copy => 1, -question => 'fonctionf', -score => 1 },
        { -copy => 1, -question => 'racine',    -score => 2 },

        { -copy => 2, -question => 'list',      -score => 0 },
        { -copy => 2, -question => 'fonctionf', -score => 0 },
        { -copy => 2, -question => 'racine',    -score => 1 },
    ],
)->default_process;

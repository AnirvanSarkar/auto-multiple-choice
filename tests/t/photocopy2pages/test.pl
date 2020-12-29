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
    seuil           => 0.2,
    perfect_copy    => '',
    multiple        => 1,
    export_full_csv => [
        { -copy => '2:1', -question => 'prez',   -abc   => 'D' },
        { -copy => '2:1', -question => 'points', -score => 2 },
        { -copy => '2:2', -question => 'prez',   -abc   => 'A' },
        { -copy => '2:2', -question => 'points', -score => 4 },
        { -copy => '2:3', -question => 'prez',   -abc   => 'B' },
        { -copy => '2:3', -question => 'points', -score => 5 },
        { -copy => '2:4', -question => 'prez',   -abc   => 'B' },
        { -copy => '2:4', -question => 'points', -score => 1 },
        { -copy => '2:5', -question => 'prez',   -abc   => 'C' },
        { -copy => '2:5', -question => 'points', -score => 3 },
    ],
)->default_process;


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

AMC::Test->new(
    dir                   => __FILE__,
    src                   => 'source.tex',
    tex_engine            => 'pdflatex',
    check_subject_content => {
        '1/1' => {
            'questions 1, 4 et 5 font'      => 1,
            'histoire : Q. 2 et 3, page 1\.' => 1
        },
        '2/1' =>
          { 'questions 1 à 3 font' => 1, 'histoire : Q. 4 et 5, page 1\.' => 1 },
        '4/1' =>
          { 'questions 2 à 4 font' => 1, 'histoire : Q. 1 et 5, page 1\.' => 1 },
    }
)->default_process;

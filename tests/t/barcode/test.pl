#! /usr/bin/perl
#
# Copyright (C) 2019-2021 Alexis Bienvenüe <paamc@passoire.fr>
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
    dir          => __FILE__,
    tex_engine   => 'pdflatex',
    perfect_copy => '',
    seuil        => 0.15,

    #	       'check_marks'=>{map { $_=>$_ } (1..5)},
    decoder     => 'BarcodeTail',
    check_assoc => { 1 => '0786', 4 => 'org' },
    list        => 'students.txt',
    list_key    => 'code',
    code        => '_namefield',
)->default_process;


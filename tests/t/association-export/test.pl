#! /usr/bin/perl
#
# Copyright (C) 2021 Alexis Bienvenüe <paamc@passoire.fr>
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
    tex_engine      => 'xelatex',
    list            => 'students.csv',
    code            => 'student.number',
    list_key        => 'numero',
    perfect_copy    => [],
    check_assoc     => { 2 => '007', 4 => '123' },
    export_columns  => 'student.name',
    export_full_csv => [
        { -name => 'Boulix Jojo',   -question => 'Q001', -score => 5 },
        { -name => 'Marchand Paul', -question => 'Q001', -score => 4 },
    ],
)->default_process;

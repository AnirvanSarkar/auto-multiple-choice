#! /usr/bin/env perl
#
# Copyright (C) 2021-2022 Alexis Bienvenüe <paamc@passoire.fr>
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

my $t = AMC::Test->new(
    dir             => __FILE__,
    tex_engine      => 'pdflatex',
    multiple        => 1,
    code            => 'id*1',
    list_key        => 'id',
    export_columns  => 'student.name',
    export_full_csv => [
        {
            -name     => 'Xeo',
            -question => 'unit',
            -score    => 1
        },
        {
            -name     => 'Xeo',
            -question => 'ten',
            -score    => 10
        },
        {
            -name     => 'Xeo',
            -question => 'hundred',
            -score    => 100
        },
        {
            -name     => 'Laura',
            -question => 'unit',
            -score    => 2
        },
        {
            -name     => 'Laura',
            -question => 'ten',
            -score    => 20
        },
        {
            -name     => 'Laura',
            -question => 'hundred',
            -score    => 200
        },
        {
            -name     => 'Berndt',
            -question => 'unit',
            -score    => 3
        },
        {
            -name     => 'Berndt',
            -question => 'ten',
            -score    => 30
        },
        {
            -name     => 'Berndt',
            -question => 'hundred',
            -score    => 300
        },
        {
            -name     => 'Alfonso',
            -question => 'unit',
            -score    => 4
        },
        {
            -name     => 'Alfonso',
            -question => 'ten',
            -score    => 40
        },
        {
            -name     => 'Alfonso',
            -question => 'hundred',
            -score    => 400
        },
        {
            -name     => 'King',
            -question => 'unit',
            -score    => 5
        },
        {
            -name     => 'King',
            -question => 'ten',
            -score    => 50
        },
        {
            -name     => 'King',
            -question => 'hundred',
            -score    => 500
        },
    ]
);

$t->prepare;
$t->defects;
$t->analyse( directory => 'rempli1', pre_allocate => 1 );
$t->gather_multicode;
$t->analyse( directory => 'rempli2', pre_allocate => 10 );
$t->gather_multicode;
$t->note;
$t->assoc;
$t->get_marks;
$t->check_export;

$t->ok;

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

require "./AMC/Test.pm";

my $me = __FILE__;
$me =~ s/test\.pl$/project.tgz/;

my $t = AMC::Test->new(
    dir             => $me,
    tex_engine      => 'pdflatex',
    list_key        => 'id',
    code            => 'student.number',
    check_assoc     => { 1 => '12', 2 => '34', 6 => '34', 8 => '34' },
    export_columns  => 'student.copy,student.key,student.name',
    export_full_csv => [
        {
            -copy     => 6,
            -aname    => 'Jojo',
            -question => "copy.version",
            -score    => 1
        },
        {
            -copy     => 8,
            -aname    => 'Jojo',
            -question => "copy.version",
            -score    => 2
        },
        {
            -copy     => 2,
            -aname    => 'Jojo',
            -question => "copy.version",
            -score    => 3
        },
    ],
    model        => '(N)-(ID)',
    annote       => [ 1, 6, 8, 2 ],
    annote_files => [
        '0001-Douze.pdf',   '0006-Jojo.pdf',
        '0008-Jojo-v2.pdf', '0002-Jojo-v3.pdf'
    ],
)->update_sqlite();

$t->assoc();
$t->get_assoc();
$t->check_assoc();
$t->check_export;
$t->annote();

$t->ok();

#! /usr/bin/env perl
#
# Copyright (C) 2013-2022 Alexis Bienvenüe <paamc@passoire.fr>
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

# Use and propagate French LANG to test sorting of accentuated strings

require "./AMC/Test.pm";

AMC::Test->new(
    dir             => __FILE__,
    list            => 'names.csv',
    n_copies        => 1,
    list_key        => 'id',
    code            => '<preassoc>',
    check_assoc     => { 2 => '002' },
    perfect_copy    => [],
    export_columns  => 'student.copy,student.name',
    export_full_csv => [

        # Test sorting…
        { -irow => 1, -aname => 'GÜAC' },
        { -irow => 2, -aname => 'GUÉRIN' },
        { -irow => 3, -aname => 'GUILLEVIC' },

        # Test checked boxes
        { -copy => 2, -question => 'bq1', -abc => 'B' },
        { -copy => 2, -question => 'bq2', -abc => '0B' },

    ],
)->default_process;


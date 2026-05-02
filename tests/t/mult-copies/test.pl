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

my $t = AMC::Test->new( setup => 0, exitonerror => 0 );

my @failed = ();

# --------------------------------------------------------------

$t->set(
    dir          => __FILE__,
    filter       => 'plain',
    n_copies     => 10,
    seuil        => 0.5,
    perfect_copy => '',
    list         => 'students.csv',
    list_key     => 'id',
    code         => 'student.number',
    check_assoc  => { 1 => 12, 2 => 'x', 6 => 'x', 8 => 'x' },
);

$t->setup();
$t->default_process;
if ( $t->{error} ) {
    push @failed, "increasing";
}

# --------------------------------------------------------------

$t->clean();
$t->set(
    dir          => __FILE__,
    filter       => 'plain',
    n_copies     => 10,
    seuil        => 0.5,
    perfect_copy => '',
    list         => 'students.csv',
    list_key     => 'id',
    code         => 'student.number',
    move_files   => [ { from => 'options-multi.xml', to => 'options.xml' } ],
    check_assoc  => {
        1 => 12,
        2 => 34,
        3 => 73,
        5 => 99,
        6 => 34,
        7 => 74,
        8 => 34,
    },
);

$t->setup();
$t->default_process;
if ( $t->{error} ) {
    push @failed, "file";
}

# --------------------------------------------------------------

for my $f (@failed) {
    $t->trace("[F] Failed: $f");
}
exit(1) if (@failed);

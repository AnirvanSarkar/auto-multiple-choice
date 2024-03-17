#! /usr/bin/env perl
#
# Copyright (C) 2024 Alexis Bienvenüe <paamc@passoire.fr>
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
    dir             => __FILE__,
    seuil           => 0.5,
    perfect_copy    => '',
    multiple        => 1,
    move_files      => [ { from => 'options-inc.xml', to => 'options.xml' } ],
    export_full_csv => [
        { -copy => '1:1', -question => 'one', -score => 1 },
        { -copy => '1:1', -question => 'two', -score => 2 },
        { -copy => '1:2', -question => 'one', -score => 2 },
        { -copy => '1:2', -question => 'two', -score => 0 },
        { -copy => '1:3', -question => 'one', -score => 3 },
        { -copy => '1:3', -question => 'two', -score => 3 },
    ],
);

$t->setup();
$t->default_process;
if ( $t->{error} ) {
    push @failed, "increasing";
}

# --------------------------------------------------------------

$t->clean();
$t->set(
    dir             => __FILE__,
    seuil           => 0.5,
    perfect_copy    => '',
    multiple        => 1,
    move_files      => [ { from => 'options-file.xml', to => 'options.xml' } ],
    export_full_csv => [
        { -copy => '1:1', -question => 'one', -score => 1 },
        { -copy => '1:1', -question => 'two', -score => 0 },
        { -copy => '1:2', -question => 'one', -score => 2 },
        { -copy => '1:2', -question => 'two', -score => 2 },
        { -copy => '1:3', -question => 'one', -score => 3 },
        { -copy => '1:3', -question => 'two', -score => 3 },
    ],
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

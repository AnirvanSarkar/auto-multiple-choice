#! /usr/bin/env perl
#
# Copyright (C) 2023-2025 Alexis Bienvenüe <paamc@passoire.fr>
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

$t->set(
    dir             => __FILE__,
    filter          => 'plain',
    tex_engine      => 'xelatex',
    seuil           => 0.5,
    perfect_copy    => '',
    annote          => '',
    export_full_csv => [
        {
            -copy     => 2,
            -question => 'QA:score',
            -score    => 4.54545,
            -digits   => 5
        },
        { -copy => 2, -question => 'QA:max', -score => 13.33333, -digits => 5 },
        { -copy => 2, -question => 'QA:value', -score => 0.3409, -digits => 6 },
    ],

    export_full_ods =>
      [ { -copy => 2, -question => 'QA', -score => 0.3409, -digits => 6 }, ],

    check_topics => [
        {
            -id      => 'QA',
            -copy    => 2,
            -message => 'QA ~ D ~ Bof (0.3409 = 4.55/13.33)'
        },
    ],
);
$t->setup();
$t->default_process;
if ( $t->{error} ) {
    push @failed, "default";
}

for my $f (@failed) {
    $t->trace("[F] Failed: $f");
}
exit(1) if (@failed);


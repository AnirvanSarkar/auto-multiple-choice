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
    annote          => [3],
    annote_position => 'marges',
    annote_color    => 'grey',
    verdict         => 'TOTAL : %S/%M => %s/%m',
    move_files      => [ { from => 'topics0.yml', to => 'topics.yml' } ],
    export_full_csv => [
        { -copy => 1, -question => 'A0:score',  -score => 21 },
        { -copy => 1, -question => 'A0:max',    -score => 19 },
        { -copy => 1, -question => 'A0:level',  -score => 'X' },
        { -copy => 1, -question => 'A:score',   -score => 30 },
        { -copy => 1, -question => 'A:max',     -score => 28 },
        { -copy => 1, -question => 'A:level',   -score => 'X' },
        { -copy => 1, -question => 'B:score',   -score => 15 },
        { -copy => 1, -question => 'B:max',     -score => 17 },
        { -copy => 1, -question => 'Bi:score',  -score => '' },
        { -copy => 1, -question => 'Bi:max',    -score => '' },
        { -copy => 1, -question => 'M:score',   -score => 18 },
        { -copy => 1, -question => 'M:max',     -score => 17 },
        { -copy => 1, -question => 'all:value', -score => 20, -digits => 2 },

        { -copy => 2, -question => 'A0:score', -score => -3 },
        { -copy => 2, -question => 'A0:max',   -score => 19 },
        { -copy => 2, -question => 'A0:value', -score => 0 },
        { -copy => 2, -question => 'A0:level', -score => 'F' },
        { -copy => 2, -question => 'A:score',  -score => -2 },
        { -copy => 2, -question => 'A:max',    -score => 28 },
        {
            -copy     => 2,
            -question => 'A:value',
            -score    => -2 / 28 * 100,
            -digits   => 2
        },
        { -copy => 2, -question => 'A:level', -score => 'Z' },
        { -copy => 2, -question => 'B:score', -score => -1 },
        { -copy => 2, -question => 'B:max',   -score => 16 },
        {
            -copy     => 2,
            -question => 'B:value',
            -score    => -1 / 16 * 100,
            -digits   => 2
        },
        { -copy => 2, -question => 'M:score', -score => 1 },
        { -copy => 2, -question => 'M:max',   -score => 17 },
        {
            -copy     => 2,
            -question => 'M:value',
            -score    => 0.0588 * 100,
            -digits   => 2
        },
        { -copy => 2, -question => 'all:value', -score => -2.25, -digits => 2 },

        { -copy => 3, -question => 'A0:score', -score => 5 },
        { -copy => 3, -question => 'A0:max',   -score => 19 },
        { -copy => 3, -question => 'A0:value', -score => 5 / 19, -digits => 4 },
        { -copy => 3, -question => 'A0:level', -score => 'C' },
        { -copy => 3, -question => 'A:score',  -score => 9 },
        { -copy => 3, -question => 'A:max',    -score => 28 },
        {
            -copy     => 3,
            -question => 'A:value',
            -score    => 9 / 28 * 100,
            -digits   => 2
        },
        { -copy => 3, -question => 'A:level', -score => 'C' },
        { -copy => 3, -question => 'B:score', -score => 10 },
        { -copy => 3, -question => 'B:max',   -score => 17 },
        {
            -copy     => 3,
            -question => 'B:value',
            -score    => 10 / 17 * 100,
            -digits   => 2
        },
        { -copy => 3, -question => 'Bi:score', -score => '' },
        { -copy => 3, -question => 'Bi:max',   -score => '' },
        { -copy => 3, -question => 'Bi:value', -score => '' },
        { -copy => 3, -question => 'M:score',  -score => 7 },
        { -copy => 3, -question => 'M:max',    -score => 17 },
        {
            -copy     => 3,
            -question => 'M:value',
            -score    => 7 / 17 * 100,
            -digits   => 2
        },
        { -copy => 3, -question => 'all:value', -score => 8.25, -digits => 2 },

    ],

    export_full_ods => [
        { -copy => 1, -question => 'A0',   -score => 21 / 19, -digits => 2 },
        { -copy => 1, -question => 'A',    -score => '107.14%' },
        { -copy => 1, -question => 'B',    -score => '88.24%' },
        { -copy => 1, -question => 'Bi',   -score => '' },
        { -copy => 1, -question => 'M',    -score => '105.88%' },
        { -copy => 1, -question => 'A0#2', -score => 'X' },
        { -copy => 1, -question => 'A#2',  -score => 'X' },
        { -copy => 1, -question => 'all',  -score => 20, -digits => 2 },

        { -copy => 2, -question => 'A0',   -score => 0, -digits => 2 },
        { -copy => 2, -question => 'A',    -score => '-7.14%' },
        { -copy => 2, -question => 'B',    -score => '-6.25%' },
        { -copy => 2, -question => 'Bi',   -score => '-33.33%' },
        { -copy => 2, -question => 'M',    -score => '5.88%' },
        { -copy => 2, -question => 'A0#2', -score => 'F' },
        { -copy => 2, -question => 'A#2',  -score => 'Z' },
        { -copy => 2, -question => 'all',  -score => -2.25, -digits => 2 },

        { -copy => 3, -question => 'A0',   -score => 5 / 19, -digits => 2 },
        { -copy => 3, -question => 'A',    -score => '32.14%' },
        { -copy => 3, -question => 'B',    -score => '58.82%' },
        { -copy => 3, -question => 'Bi',   -score => '' },
        { -copy => 3, -question => 'M',    -score => '41.18%' },
        { -copy => 3, -question => 'A0#2', -score => 'C' },
        { -copy => 3, -question => 'A#2',  -score => 'C' },
        { -copy => 3, -question => 'all',  -score => 8.25, -digits => 2 },
    ],

    check_topics => [
        {
            -id      => 'A0',
            -copy    => 1,
            -message => 'X : acquis avec bonus (21 > 19)'
        },
        {
            -id    => 'A0',
            -copy  => 1,
            -color => '#00b935'
        },
        { -id => 'A0', -copy => 2, -message => 'F : à travailler' },
        { -id => 'A0', -copy => 2, -color   => '#ff2d3a' },
        { -id => 'A0', -copy => 3, -message => 'C : à renforcer (0.2632)' },
        { -id => 'A0', -copy => 3, -color   => '#ff9f2d' },
    ],
);
$t->setup();
$t->default_process;
if ( $t->{error} ) {
    push @failed, "default";
}

$t->clean();
$t->set(
    tmpdir     => '',
    move_files => [
        { from => 'topics_indic.yml',  to => 'topics.yml' },
        { from => 'options_indic.xml', to => 'options.xml' }
    ],
    export_full_csv => [
        { -copy => 1, -question => 'A0:score', -score => 25 },
        { -copy => 1, -question => 'A0:max',   -score => 25 },
        { -copy => 1, -question => 'A0:level', -score => 'A' },
        { -copy => 1, -question => 'A:score',  -score => 34 },
        { -copy => 1, -question => 'A:max',    -score => 34 },
        { -copy => 1, -question => 'A:level',  -score => 'A' },
        { -copy => 1, -question => 'B:score',  -score => 15 },
        { -copy => 1, -question => 'B:max',    -score => 17 },
        { -copy => 1, -question => 'Bi:score', -score => '' },
        { -copy => 1, -question => 'Bi:max',   -score => '' },
        { -copy => 1, -question => 'M:score',  -score => 18 },
        { -copy => 1, -question => 'M:max',    -score => 17 },

        { -copy => 2, -question => 'A0:score', -score => -2 },
        { -copy => 2, -question => 'A0:max',   -score => 25 },
        { -copy => 2, -question => 'A0:value', -score => 0 },
        { -copy => 2, -question => 'A0:level', -score => 'F' },
        { -copy => 2, -question => 'A:score',  -score => -1 },
        { -copy => 2, -question => 'A:max',    -score => 34 },
        {
            -copy     => 2,
            -question => 'A:value',
            -score    => -1 / 34 * 100,
            -digits   => 2
        },
        { -copy => 2, -question => 'A:level', -score => 'Z' },
        { -copy => 2, -question => 'B:score', -score => -1 },
        { -copy => 2, -question => 'B:max',   -score => 16 },
        {
            -copy     => 2,
            -question => 'B:value',
            -score    => -1 / 16 * 100,
            -digits   => 2
        },
        { -copy => 2, -question => 'M:score', -score => 1 },
        { -copy => 2, -question => 'M:max',   -score => 17 },
        {
            -copy     => 2,
            -question => 'M:value',
            -score    => 0.0588 * 100,
            -digits   => 2
        },

        { -copy => 3, -question => 'A0:score', -score => 9 },
        { -copy => 3, -question => 'A0:max',   -score => 25 },
        { -copy => 3, -question => 'A0:value', -score => 9 / 25, -digits => 4 },
        { -copy => 3, -question => 'A0:level', -score => 'C' },
        { -copy => 3, -question => 'A:score',  -score => 13 },
        { -copy => 3, -question => 'A:max',    -score => 34 },
        {
            -copy     => 3,
            -question => 'A:value',
            -score    => 13 / 34 * 100,
            -digits   => 2
        },
        { -copy => 3, -question => 'A:level', -score => 'C' },
        { -copy => 3, -question => 'B:score', -score => 10 },
        { -copy => 3, -question => 'B:max',   -score => 17 },
        {
            -copy     => 3,
            -question => 'B:value',
            -score    => 10 / 17 * 100,
            -digits   => 2
        },
        { -copy => 3, -question => 'Bi:score', -score => '' },
        { -copy => 3, -question => 'Bi:max',   -score => '' },
        { -copy => 3, -question => 'Bi:value', -score => '' },
        { -copy => 3, -question => 'M:score',  -score => 7 },
        { -copy => 3, -question => 'M:max',    -score => 17 },
        {
            -copy     => 3,
            -question => 'M:value',
            -score    => 7 / 17 * 100,
            -digits   => 2
        },
    ],

    export_full_ods => [
        { -copy => 1, -question => 'A0',   -score => 1, -digits => 2 },
        { -copy => 1, -question => 'A',    -score => '100.00%' },
        { -copy => 1, -question => 'B',    -score => '88.24%' },
        { -copy => 1, -question => 'Bi',   -score => '' },
        { -copy => 1, -question => 'M',    -score => '105.88%' },
        { -copy => 1, -question => 'A0#2', -score => 'A' },
        { -copy => 1, -question => 'A#2',  -score => 'A' },

        { -copy => 2, -question => 'A0',   -score => 0, -digits => 2 },
        { -copy => 2, -question => 'A',    -score => '-2.94%' },
        { -copy => 2, -question => 'B',    -score => '-6.25%' },
        { -copy => 2, -question => 'Bi',   -score => '-33.33%' },
        { -copy => 2, -question => 'M',    -score => '5.88%' },
        { -copy => 2, -question => 'A0#2', -score => 'F' },
        { -copy => 2, -question => 'A#2',  -score => 'Z' },

        { -copy => 3, -question => 'A0',   -score => 9 / 25, -digits => 2 },
        { -copy => 3, -question => 'A',    -score => '38.24%' },
        { -copy => 3, -question => 'B',    -score => '58.82%' },
        { -copy => 3, -question => 'Bi',   -score => '' },
        { -copy => 3, -question => 'M',    -score => '41.18%' },
        { -copy => 3, -question => 'A0#2', -score => 'C' },
        { -copy => 3, -question => 'A#2',  -score => 'C' },
    ],

    check_topics => [
        {
            -id      => 'A0',
            -copy    => 1,
            -message => 'A : pleinement acquis (1)'
        },
        {
            -id    => 'A0',
            -copy  => 1,
            -color => '#47b900'
        },
        { -id => 'A0', -copy => 2, -message => 'F : à travailler' },
        { -id => 'A0', -copy => 2, -color   => '#ff2d3a' },
        { -id => 'A0', -copy => 3, -message => 'C : à renforcer (0.36)' },
        { -id => 'A0', -copy => 3, -color   => '#ff9f2d' },
    ],
);
$t->setup();
$t->default_process;
if ( $t->{error} ) {
    push @failed, "including indicatives";
}

for my $f (@failed) {
    $t->trace("[F] Failed: $f");
}
exit(1) if (@failed);


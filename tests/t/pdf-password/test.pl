#! /usr/bin/perl
#
# Copyright (C) 2018-2021 Alexis Bienvenüe <paamc@passoire.fr>
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
    dir          => __FILE__,
    tex_engine   => 'xelatex',
    password     => 'x.fs_t43+0-',
    extract_with => 'pdftk+NA',
    perfect_copy => [],
    seuil        => 0.25,
    check_marks  => { 1 => 20, 2 => 20, 3 => 20 },
                      )->default_process;

# With some ImageMagick versions, decrypt with password may fail:
# see https://www.imagemagick.org/discourse-server/viewtopic.php?t=31530
# Please upgrade ImageMagick to version 7.0.8 or above
$t->may_fail();

$t->set(
    force_convert => 1,
    extract_with  => 'qpdf'
)->install->default_process;

$t->set( extract_with => 'pdftk' )->install->default_process;

$t->set( force_magick => 1 )->install->default_process;

$t->set( no_gs => 1 )->install->default_process;

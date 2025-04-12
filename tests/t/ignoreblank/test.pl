#! /usr/bin/env perl
#
# Copyright (C) 2021-2025 Alexis Bienvenüe <paamc@passoire.fr>
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

my @args=@ARGV;

AMC::Test->new(
    dir         => __FILE__,
    src         => 'simple.tex',
    tex_engine  => 'pdflatex',
    notemax     => 0,
    check_marks => { 1 => 10, 2 => 10, 4 => 8 },
)->default_process;

@ARGV=@args;

AMC::Test->new(
    dir         => __FILE__,
    src         => 'simple.tex',
    tex_engine  => 'pdflatex',
    postinstall => sub {
        my ($self) = @_;
        system( "env", "perl", "-pi", "-e", 's/.AMCnumericOpts/%/',
            "$self->{temp_dir}/simple.tex" );
    },
    notemax         => 0,
    check_marks     => { 1 => 2, 2 => 2, 4 => 4 },
    export_full_csv => [
        { -copy => 1, -question => 'sign', -score => 2 },
        { -copy => 2, -question => 'sign', -score => 2 },
        { -copy => 4, -question => 'sign', -score => 2 },
        { -copy => 4, -question => 'integer', -score => 2 },
    ],
)->default_process;


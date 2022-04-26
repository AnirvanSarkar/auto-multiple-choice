#! /usr/bin/env perl
#
# Copyright (C) 2016-2022 Alexis Bienvenüe <paamc@passoire.fr>
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

my $mode;

sub choose_codedigit {
    my ($self) = @_;
    system( "perl", "-pi", "-e", "s/CODEDIGIT/$mode/",
        $self->{temp_dir} . "/code.tex" );
}

sub check_codedigit {
    my ($self) = @_;
    my $l = AMC::Data->new( $self->{temp_dir} . "/data" )->module('layout');
    my $v = $l->variable_transaction('build:codedigit');
    if ( $v eq $mode ) {
        $self->trace("[T] codedigit is $v");
    } else {
        $self->trace("[E] codedigit is $v instead of $mode");
        $self->failed(1);
    }
}

$mode = 'squarebrackets';

my $t = AMC::Test->new(
    dir             => __FILE__,
    tex_engine      => 'pdflatex',
    postinstall     => \&choose_codedigit,
    additional_test => \&check_codedigit,
    perfect_copy    => '',
    seuil           => 0.15,
    check_assoc     => { 1 => 'AMA0123', 2 => '0C54', 3 => 'PH10' },
);

$t->default_process();

$mode = 'dot';
$t->install();
$t->default_process();

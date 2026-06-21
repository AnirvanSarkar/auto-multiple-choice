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

use AMC::Data;

use File::Spec::Functions qw(tmpdir);
use File::Temp qw(tempfile tempdir);

my $temp_loc = tmpdir();
my $temp_dir = tempdir(
    DIR     => $temp_loc,
    CLEANUP => ( !$self->{debug} )
                      );

my $t = AMC::Test->new(setup=>0);
my $err = 0;

my $data = AMC::Data->new($temp_dir);
my $mod = $data->module("test");

$mod->register_schema("test", "a INTEGER", "b INTEGER DEFAULT 12", "c REAL", "PRIMARY KEY(a,b)");

sub test_it {
    my ($a,$b,$title) = @_;
    if($a ne $b) {
        $t->trace("[E] $title: $b should be $a");
        $err++;
    }
}

test_it($mod->get_table_schema("test"),
        "(a INTEGER,b INTEGER DEFAULT 12,c REAL,PRIMARY KEY(a,b))",
        "Simple schema");
test_it($mod->get_table_schema("test", without=>"a;c"),
        "(b INTEGER DEFAULT 12,PRIMARY KEY(a,b))",
        "Schema without");

test_it($mod->get_table_cols("test"),
        "a,b,c",
        "Simple cols");
test_it($mod->get_table_cols("test", without=>"a;c"),
        "b",
        "Cols without");

$mod->begin_transaction("TST0");
$mod->create_table("test", without=>"b;PRIMARY KEY(a,b)");
$mod->sql_do("INSERT INTO ".$mod->table("test")." (a,c) VALUES (10,20)");
$mod->sql_do("INSERT INTO ".$mod->table("test")." (a,c) VALUES (11,21)");
$mod->end_transaction("TST0");

$mod->begin_transaction("TST1");
$mod->add_column_hard("test", "b");
test_it($mod->sql_single("SELECT b FROM " . $mod->table("test") . " WHERE a=11 AND c=21"),
        12, "Add column hard");
$mod->end_transaction("TST1");

if($err) {
    $self->failed(1);
}

$t->ok();

#! /usr/bin/perl
#
# Copyright (C) 2017 Alexis Bienvenue <paamc@passoire.fr>
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

use AMC::Basic;

use AMC::Data;
use AMC::DataModule::capture qw/ :zone /;;

my ($project_dir,$dest_dir)=@ARGV;

die "Project dir not found" if(!-d "$project_dir/data");
die "Destination dir not found" if(!-d $dest_dir);

my $data=AMC::Data->new("$project_dir/data");
my $capture=$data->module('capture');

my $project=$project_dir;
$project =~ s+.*/++;

$data->require_module('scoring');
$data->require_module('layout');

$sth=$capture->statement('entryImages');
$sth->execute(ZONE_BOX);
while(my $b=$sth->fetchrow_hashref) {
  print "- box S=$b->{student} C=$b->{copy} Q=$b->{question} A=$b->{answer} T=$b->{text_auto}|$b->{text_manual}($b->{correct_text})\n";
  my $classif=$b->{correct_text};
  $classif=$b->{text_manual} if(!$b->{correct_text});

  if($classif) {
    my $dir="$dest_dir/$classif";
    mkdir($dir) if(!-e $dir);
    my $filename=new_filename("$dir/P$project-S$b->{student}-C$b->{copy}-Q$b->{question}-A$b->{answer}.png");
    open(IMAGE,">$filename");
    print IMAGE $b->{imagedata};
    close IMAGE;
  }
}

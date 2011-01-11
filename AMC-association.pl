#! /usr/bin/perl
#
# Copyright (C) 2008 Alexis Bienvenue <paamc@passoire.fr>
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

use Getopt::Long;
use AMC::Gui::Association;

my $cr_dir='points-cr';
my $liste='noms.txt';
my $assoc_file='';

GetOptions("cr=s"=>\$cr_dir,
	   "liste=s"=>\$liste,
	   "o=s"=>\$assoc_file,
	   );

my $g=AMC::Gui::Association::new('cr'=>$cr_dir,
				 'liste'=>$liste,
				 'fichier-liens'=>$assoc_file,
				 'global'=>1,
				 );

Gtk2->main;


#! /usr/bin/perl
#
# Copyright (C) 2008-2010 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3 of
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

use Data::Dumper;

my $lic_head=q!# Copyright (C) 2008-2010 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3 of
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

!;

my %k=();

$s=`svnversion`;
if($s =~ /([0-9]+)[SM]*$/) {
    $k{'svn'}=$1;
}

open(CHL,"ChangeLog");
LINES: while(<CHL>) {
    if(/^([0-9:.-svn]+)/) {
	$k{'deb'}=$1;
	last LINES;
    }
}

$d = Data::Dumper->new([\%k], ['k']); 

open(VPL,">nv.pl");
print VPL $lic_head;
print VPL $d->Dump;
close(VPL);

open(VMK,">Makefile.versions");
print VMK $lic_head;
print VMK "PACKAGE_V_DEB=$k{'deb'}\n";
print VMK "PACKAGE_V_SVN=$k{'svn'}\n";
close(VMK);

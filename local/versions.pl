#! /usr/bin/perl
#
# Copyright (C) 2008-2011 Alexis Bienvenue <paamc@passoire.fr>
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

my $lic_head='';

open(THIS,__FILE__);
 LIG: while(<THIS>) {
     chomp;
     last LIG if(!/^#/);
     $lic_head.="$_\n";
}
close(THIS);
$lic_head.="\n";
    
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

open(VMK,">Makefile.versions");
print VMK $lic_head;
print VMK "PACKAGE_V_DEB=$k{'deb'}\n";
print VMK "PACKAGE_V_SVN=$k{'svn'}\n";
close(VMK);


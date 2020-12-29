#! /usr/bin/perl
#
# Copyright (C) 2008-2021 Alexis Bienvenue <paamc@passoire.fr>
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

use POSIX;

sub available {
    my $c = shift;
    $ok = '';
    for ( split( /:/, $ENV{PATH} ) ) {
        $ok = 1 if ( -x "$_/$c" );
    }
    return ($ok);
}

my %k = ( deb => "XX", vc => "", year => "2016", month => "01", day => "01" );

open( CHL, "ChangeLog" );
LINES: while (<CHL>) {
    if (/^([0-9~:.a-z+-]+)\s+\((\d{4})-(\d{2})-(\d{2})\)/) {
        $k{deb}   = $1;
        $k{year}  = $2;
        $k{month} = $3;
        $k{day}   = $4;
        last LINES;
    }
}

$ENV{TZ} = "UTC";
POSIX::tzset();
$k{epoch} = POSIX::mktime( 0, 0, 0, $k{day}, $k{month} - 1, $k{year} - 1900 );

if ( available("svnversion") ) {
    $s = `svnversion`;
    if ( $s =~ /([0-9]+)[SM]*$/ ) {
        $k{vc} = "svn:$1";
    }
}

if ( available("hg") && -d ".hg" ) {
    $s = `hg id`;
    if ( $s =~ /^([0-9a-f]+\+?)/ ) {
        $k{vc} = "r:$1";
    }
}

if ( available("git") && -d ".git" ) {
    chomp( $s = `git rev-parse --short HEAD` );
    if ( $s =~ /^([0-9a-f]+\+?)/ ) {
        $k{vc} = "r:$1";
    }
    chomp( $s = `git log -1 --date=short --format=%cd` );
    if ( $s =~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ ) {
        $k{deb} =~ s/\+(hg|git)[0-9]{4}-[0-9]{2}-[0-9]{2}/+git$s/;
    }
}

$k{sty} = "$k{year}/$k{month}/$k{day} v$k{deb} $k{vc}";
$k{sty} =~ s/\s+/ /;
$k{sty} =~ s/\s+$//;

open( VMK, ">Makefile.versions" );
print VMK "PACKAGE_V_DEB=$k{deb}\n";
print VMK "PACKAGE_V_VC=$k{vc}\n";
print VMK "PACKAGE_V_PDFDATE=$k{year}$k{month}$k{day}000000\n";
print VMK "PACKAGE_V_ISODATE=$k{year}-$k{month}-$k{day}\n";
print VMK "PACKAGE_V_STY=$k{sty}\n";
print VMK "PACKAGE_V_EPOCH=$k{epoch}\n";
close(VMK);


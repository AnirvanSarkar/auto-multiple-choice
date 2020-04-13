#! /usr/bin/perl
# -*- coding:utf-8 -*-
#
# Copyright (C) 2008-2020 Alexis Bienvenue <paamc@passoire.fr>
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
use Time::localtime;
use File::stat;

@d       = ();
$mode    = 'f';
$ext     = '(i386|amd64).deb';
$debug   = '';
$precomp = '';
$fich    = '';

GetOptions(
    "base=s"      => \@d,
    "fich=s"      => \$fich,
    "precomp!"    => \$precomp,
    "extension=s" => \$ext,
    "mode=s"      => \$mode,
    "debug!"      => \$debug,
);

@d = ( "/home/alexis/enseignement", "/tmp", "tmp" ) if ( !@d && !$fich );

my @v;

for my $d (@d) {
    if ( -d $d ) {
        opendir( DIR, $d );
        push @v, map { "$d/$_" } grep {
            /^auto-multiple-choice_.*$ext$/
              && ( $precomp || !/precomp/ )
              && !/current/
        } readdir(DIR);
        closedir(DIR);
    }
}

push @v, $fich if ($fich);

@mois =
  qw/janvier février mars avril mai juin juillet août septembre octobre novembre décembre/;

sub la_date {
    my $f = localtime( stat(shift)->mtime );
    return ( $f->mday . " " . $mois[ $f->mon ] . " " . ( $f->year + 1900 ) );
}

sub la_date_en {
    my $f = localtime( stat(shift)->mtime );
    return (
        sprintf( "%d-%02d-%02d", $f->year + 1900, $f->mon + 1, $f->mday ) );
}

sub version {
    my $f = shift;
    $f =~ s/^.*?_([^_]+)(_.*)?\.?$ext/$1/;
    return ($f);
}

sub vc {
    my ( $x, $y ) = @_;
    my $vx = version($x);
    my $vy = version($y);
    print STDERR "$vx $vy\n" if ($debug);
    `dpkg --compare-versions $vx gt $vy`;
    return ($?);
}

@v = sort { vc( $a, $b ); } @v;

if ( $mode =~ /f/i ) {
    print "$v[0]\n";
} elsif ( $mode =~ /v/i ) {
    print version( $v[0] ) . "\n";
} elsif ( $mode =~ /h/i ) {
    print "<!--#set var=\"VERSION\" value=\"" . version( $v[0] ) . "\"-->\n";
    print "<!--#set var=\"VERSIONDATE\" value=\""
      . la_date( $v[0] )
      . "\"-->\n";
    print "<!--#set var=\"VERSIONDATEEN\" value=\""
      . la_date_en( $v[0] )
      . "\"-->\n";
}


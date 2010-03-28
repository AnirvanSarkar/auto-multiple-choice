#! /usr/bin/perl
# -*- coding:utf-8 -*-

use Getopt::Long;
use Time::localtime;
use File::stat;

$d="/home/alexis/enseignement";
$mode='f';
$ext='i386.deb';
$debug='';

GetOptions("base=s"=>\$d,
	   "extension=s"=>\$ext,
	   "mode=s"=>\$mode,
	   "debug!"=>\$debug,
	   );

opendir(DIR,$d);
my @v=grep { /^auto-multiple-choice_.*$ext$/ && ! /precomp/ } readdir(DIR);
closedir(DIR);

@mois=qw/janvier février mars avril mai juin juillet août septembre octobre novembre décembre/;

sub la_date {
    my $f=localtime(stat(shift)->mtime);
    return($f->mday." ".$mois[$f->mon]." ".($f->year+1900));
}

sub version {
    my $f=shift;
    $f =~ s/^[^_]*_([^_]+)(_[^_.]*)?\.?$ext/$1/;
    return($f);
}

sub vc {
    my ($x,$y)=@_;
    my $vx=version($x);
    my $vy=version($y);
    print STDERR "$vx $vy\n" if($debug);
    `dpkg --compare-versions $vx '>' $vy`;
    return($?);
}

@v=sort { vc($a,$b); } @v;

if($mode =~ /f/i) {
    print "$d/$v[0]\n";
} elsif($mode =~ /v/i) {
    print version($v[0])."\n";
} elsif($mode =~ /h/i) {
    print "<!--#set var=\"VERSION\" value=\"".version($v[0])."\"-->\n";
    print "<!--#set var=\"VERSIONDATE\" value=\"".la_date("$d/$v[0]")."\"-->\n";
}



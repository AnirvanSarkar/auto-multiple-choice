#! /usr/bin/perl
# -*- coding:utf-8 -*-

use Getopt::Long;
use Time::localtime;
use File::stat;

@d=();
$mode='f';
$ext='i386.deb';
$debug='';
$precomp='';

GetOptions("base=s"=>\@d,
	   "precomp!"=>\$precomp,
	   "extension=s"=>\$ext,
	   "mode=s"=>\$mode,
	   "debug!"=>\$debug,
	   );

@d=("/home/alexis/enseignement","/tmp") if(!@d);

my @v;

for my $d (@d) {
    opendir(DIR,$d);
    push @v,map { "$d/$_" } grep { /^auto-multiple-choice_.*$ext$/ && ($precomp || ! /precomp/) && ! /current/ } readdir(DIR);
    closedir(DIR);
}

@mois=qw/janvier février mars avril mai juin juillet août septembre octobre novembre décembre/;

sub la_date {
    my $f=localtime(stat(shift)->mtime);
    return($f->mday." ".$mois[$f->mon]." ".($f->year+1900));
}

sub la_date_en {
    my $f=localtime(stat(shift)->mtime);
    return(sprintf("%d-%02d-%02d",$f->year+1900,$f->mon+1,$f->mday));
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
    print "$v[0]\n";
} elsif($mode =~ /v/i) {
    print version($v[0])."\n";
} elsif($mode =~ /h/i) {
    print "<!--#set var=\"VERSION\" value=\"".version($v[0])."\"-->\n";
    print "<!--#set var=\"VERSIONDATE\" value=\"".la_date($v[0])."\"-->\n";
    print "<!--#set var=\"VERSIONDATEEN\" value=\"".la_date_en($v[0])."\"-->\n";
}



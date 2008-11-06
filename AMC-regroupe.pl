#! /usr/bin/perl
#
# Copyright (C) 2008 Alexis Bienvenue <paamc@passoire.fr>
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

use Getopt::Long;
use Text::Unaccent;
use XML::Simple;

use AMC::Basic;
use AMC::Gui::Avancement;

my $jpgdir='';
my $pdfdir='';
my $modele="";
my $progress=1;
my $association='';

my $debug='';

GetOptions("cr=s"=>\$cr,
	   "modele=s"=>\$modele,
	   "association=s"=>\$association,
	   "progression=s"=>\$progress,
	   );

my $jpgdir="$cr/corrections/jpg";
my $pdfdir="$cr/corrections/pdf";

my $association="$cr/association.xml" if(-f "$cr/association.xml" && ! $association);

my $avance=AMC::Gui::Avancement::new($progress);

my $ass='';

$ass=XMLin($association,KeyAttr=> [ 'id' ],ForceArray=>['etudiant']) if($association);

opendir(JDIR, $jpgdir) || die "can't opendir $jpgdir: $!";
@pages = grep { /^page.*jpg$/ && -f "$jpgdir/$_" } readdir(JDIR);
closedir JDIR;
my %r=();
for my $f (@pages) {
    my ($e,$p)=get_ep(file2id($f));
    $r{$e}={} if(!$r{$e});
    $r{$e}->{$p}="$jpgdir/$f";
}
for my $e (keys %r) {
    print "Regroupement des pages pour ID=$e...\n";

    my $f=$modele;
    $f='(id)'.$f if(!$f);
    $f.='.pdf' if($f !~ /\.pdf$/i);
    
    my $ex=sprintf("%04d",$e);
    $f =~ s/\(id\)/$ex/gi;
    my $nom=$ass->{'etudiant'}->{$e}->{'content'};
    $nom =~ s/^\s+//;
    $nom =~ s/\s+$//;
    $nom =~ s/\s+/_/g;
    $nom=unac_string("UTF-8",$nom);
    $f =~ s/\(nom\)/$nom/gi;

    for my $k (grep { ! /^(nom|id|content)$/ } (keys %{$ass->{'etudiant'}->{$e}})) {
	my $t=$ass->{'etudiant'}->{$e}->{$k};
	$f =~ s/\($k:([0-9]+)\)/sprintf("%0$1d",$t)/gie;
	$f =~ s/\($k\)/$t/gi;
    }

    $f="$pdfdir/$f";
    my @sp=sort { $a <=> $b } (keys %{$r{$e}});
    system('convert',
	   '-quality',50,
	   '-adjoin',
	   '-page','A4',
	   (map { $r{$e}->{$_} } @sp),
	   $f);

    $avance->progres(1/(1+$#pages));
}

$avance->fin();

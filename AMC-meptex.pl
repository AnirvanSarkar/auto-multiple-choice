#! /usr/bin/perl
#
# Copyright (C) 2011 Alexis Bienvenue <paamc@passoire.fr>
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
use Encode;

use AMC::Basic;
use AMC::Gui::Avancement;

my $src;
my $mep_dir;
my $dpi=300;

my $progress;
my $progress_id;

GetOptions("src=s"=>\$src,
	   "mep-dir=s"=>\$mep_dir,
	   "progression-id=s"=>\$progress_id,
	   "progression=s"=>\$progress,
    );

die "No src file $src" if(! -f $src);
die "No mep dir $mep_dir" if(! -d $mep_dir);

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

# how much units in one inch ?
%u_in_one_inch=('in'=>1,
		'cm'=>2.54,
		'mm'=>25.4,
		'pt'=>72.27,
		'sp'=>65536*72.27,
    );

sub read_inches {
    my ($dim)=@_;
    if($dim =~ /^\s*([0-9]*\.?[0-9]*)\s*([a-zA-Z]+)\s*$/) {
	if($u_in_one_inch{$2}) {
	    return($1 / $u_in_one_inch{$2});
	} else {
	    die "Unknown unity: $2 ($dim)";
	}
    } else {
	die "Unknown dim: $dim";
    }
}

sub ajoute {
    my ($ar,$val)=@_;
    if(@$ar) {
	$ar->[0]=$val if($ar->[0]>$val && $val);
	$ar->[1]=$val if($ar->[1]<$val && $val);
    } else {
	$ar->[0]=$val if($val);
	$ar->[1]=$val if($val);
    }
}

my @pages=();
my $cases;
my $page_number=0;

open(SRC,$src) or die "Unable to open $src : $!";
while(<SRC>) {
    if(/\\page{([^\}]+)}{([^\}]+)}{([^\}]+)}/) {
	my $id=$1;
	my $dx=$2;
	my $dy=$3;
	$page_number++;
	$cases={};
	push @pages,{-id=>$id,-p=>$page_number,
		     -dim_x=>read_inches($dx),-dim_y=>read_inches($dy),
		     -cases=>$cases};
    }
    if(/\\tracepos\{([^\}]+)\}\{([^\}]*)\}\{([^\}]*)\}/) {
	my $i=$1;
	my $x=read_inches($2);
	my $y=read_inches($3);
	$i =~ s/^[0-9]+\/[0-9]+://;
	$cases->{$i}={'bx'=>[],'by'=>[]} if(!$cases->{$i});
	ajoute($cases->{$i}->{'bx'},$x);
	ajoute($cases->{$i}->{'by'},$y);
    }
}
close(SRC);

sub bbox {
    my ($c)=@_;
    return(sprintf(" xmin=\"%.2f\" xmax=\"%.2f\" ymin=\"%.2f\" ymax=\"%.2f\"",
		   $c->{'bx'}->[0],$c->{'bx'}->[1],
		   $c->{'by'}->[1],$c->{'by'}->[0]));
}

sub center {
    my ($c,$xy)=@_;
    return(($c->{$xy}->[0]+$c->{$xy}->[1])/2);
}

my $delta=(@pages ? 1/(1+$#pages) : 0);

for my $p (@pages) {

    my $diametre_marque=0;
    my $dmn=0;

  KEY: for my $k (keys %{$p->{-cases}}) {
      for(0..1) {
	  $p->{-cases}->{$k}->{'bx'}->[$_] *= $dpi;
	  $p->{-cases}->{$k}->{'by'}->[$_] = $dpi*($p->{-dim_y} - $p->{-cases}->{$k}->{'by'}->[$_]);
      }
      
      if($k =~ /position[HB][GD]$/) {
	  for my $dir ('bx','by') {
	      $diametre_marque+=abs($p->{-cases}->{$k}->{$dir}->[1]-$p->{-cases}->{$k}->{$dir}->[0]);
	      $dmn++;
	  }
      }
  }
    $diametre_marque/=$dmn;

    for my $pos ('HG','HD','BD','BG') {
	die "Needs position$pos from page $p->{-id}" if(!$c->{'position'.$pos});
    }

    my $fn="$mep_dir/mep-".id2idf($p->{-id}).".xml";
    open(XML,">:encoding(UTF-8)",$fn) or die "Unable to write to $fn : $!";
    print XML "<?xml version='1.0' encoding='UTF-8'?>\n";
    print XML sprintf("<mep image=\"latex.xy\" id=\"+%s+\" src=\"$src\" page=\"%d\" dpi=\"%.2f\" tx=\"%.2f\" ty=\"%.2f\" diametremarque=\"%.2f\">\n",
		      $p->{-id},$p->{-p},
		      $dpi,$dpi*$p->{-dim_x},$dpi*$p->{-dim_y},
		      $diametre_marque);

    my $c=$p->{-cases};

    my $nc=0;
    for my $pos ('HG','HD','BD','BG') {
	$nc++;
	print XML "<coin id=\"$nc\"><x>"
	    .center($c->{'position'.$pos},'bx')
	    ."</x><y>"
	    .center($c->{'position'.$pos},'by')
	    ."</y></coin>\n";
    }
    if($c->{'nom'}) {
	print XML "<nom".bbox($c->{'nom'})."/>\n";
    }
    for my $k (sort { $a cmp $b } (keys %$c)) {
	if($k=~/chiffre:([0-9]+),([0-9]+)$/) {
	    print XML "<chiffre n=\"$1\" i=\"$2\"".bbox($c->{$k})."/>\n";
	}
	if($k=~/case:(.*):([0-9]+),([0-9]+)$/) {
	    print XML "<case question=\"$2\" reponse=\"$3\"".bbox($c->{$k})."/>\n";
	}
    }

    print XML "</mep>\n";
    close(XML);

    $avance->progres($delta);
}

$avance->fin();

#! /usr/bin/perl -w
#
# Copyright (C) 2010 Alexis Bienvenue <paamc@passoire.fr>
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
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use File::Copy;
use AMC::Image;
use AMC::Basic;

my $debug='';

my $moteur_latex='latex,pdflatex,xelatex';
my $moteur_raster='im,gm,gs,pdftoppm';
my $keep=0;

GetOptions("latex=s"=>\$moteur_latex,
	   "raster=s"=>\$moteur_raster,
           "debug=s"=>\$debug,
	   "keep!"=>\$keep,
 	   );

set_debug($debug);

($e_volume,$e_vdirectories,undef) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
}

$temp_loc=tmpdir();
$temp_dir = tempdir( DIR=>$temp_loc,CLEANUP => !$keep );

print "Repertoire $temp_dir\n" if($keep);

$tex_file="$temp_dir/source.tex";
$ppm_file="$temp_dir/source.ppm";

open(LATEX,">$tex_file");

print LATEX q!
\documentclass{article}
\usepackage{automultiplechoice}
\begin{document}
\newcount\indice
\newcount\numquestion

\def\AMCbeginQuestion#1#2{\par Q#1#2 :}
\def\AMCbeginAnswer{}
\def\AMCendAnswer{}
\def\AMCanswer#1#2{#1 #2 }

\AMCnobloc

\exemplaire{1}{

  \champnom{\fbox{\begin{minipage}{.5\linewidth}
Nom et pr\'enom :

\vspace*{.5cm}\dotfill
\vspace*{1mm}
\end{minipage}}}

\numquestion=1
\loop
{
\begin{question}{\the\numquestion}\QuestionIndicative
  \begin{reponsesperso}[o]
    \indice=1\loop\mauvaise{\the\indice}\advance\indice by 1 \ifnum\indice<40\repeat
  \end{reponsesperso}
\end{question}
}
\advance\numquestion by 1
\ifnum\numquestion<15\repeat
}
\end{document}
!;
close(LATEX);

my $nb;
my %codes;

sub verif {
    my ($a,$b,$c)=@_;
    if(!$codes{$a}->{$b}->{$c}) {
	debug "Manque $a:$b:$c\n";
	$nb++;
    }
}

sub execute {
    open(CMD,"-|",@_);
    while(<CMD>) {
	debug $_;
    }
    close(CMD);
}

 ML:for my $m_l (split(/,+/,$moteur_latex)) {

     execute(with_prog("AMC-prepare.pl"),
	     "--mode","s","--with",$m_l,"--prefix","$temp_dir/",$tex_file);

     if(! -f "$temp_dir/calage.pdf") {
	 print "$m_l+*:ERREUR COMPILATION\n";
	 next ML;
     }

     copy("$temp_dir/calage.pdf","$temp_dir/$m_l-calage.pdf") if($keep);
     
   MR:for my $m_r (split(/,+/,$moteur_raster)) {
       
       execute(with_prog("AMC-raster.pl"),
	       "--moteur",$m_r,"$temp_dir/calage.pdf",$ppm_file);

       if(! -f $ppm_file) {
	   print "$m_l+$m_r:ERREUR RASTERISATION\n";
	   next ML;
       }

       copy($ppm_file,"$temp_dir/$m_l-$m_r-image.ppm") if($keep);

       my $im=AMC::Image::new($ppm_file);
       my @mag=$im->commande('magick');

       if($keep) {
	   open(MAG,">$temp_dir/$m_l-$m_r-boites.log");
	   print MAG join("\n",@mag)."\n";
	   close(MAG);
       }
       
       %codes=();
       
       for(@mag) {
	   if(/magick=([0-9]+)\s+exo=([0-9]+)\s+quest=([0-9]+)/) {
	       $codes{$1}->{$2}->{$3}++;
	   }
       }
       
       $nb=0;
       
       for my $q (1..14) {
	   for my $r (1..39) {
	       verif(200,$q,$r);
	   }
       }
       verif(201,255,255);
       for my $i (1..4) {
	   verif(201,100,$i);
       }
       for my $i (1..12) {
	   verif(201,1,$i);
       }
       for my $i (1..6) {
	   verif(201,2,$i);
	   verif(201,3,$i);
       }
       
       print ">>> $m_l+$m_r:".($nb==0 ? "OK" : "ERREUR ($nb couleurs manquantes)")."\n";

       unlink $ppm_file;
       
   }
     
     unlink "$temp_dir/calage.pdf";
 }

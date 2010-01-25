#! /usr/bin/perl
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

use AMC::Image;
use Getopt::Long;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;

# teste la transformation : RGB(reels) dans PDF --> RGB(entiers) dans PPM
# lors de la rasterisation

my $moteur='im';

my $a=0;
my $delta=0.00000001;
my $keep=0;

($e_volume,$e_vdirectories,undef) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
}

GetOptions("delta=s"=>\$delta,
	   "moteur=s"=>\$moteur,
	   "seuil=s"=>\$a,
	   "keep!"=>\$keep,
	   );

$temp_loc=tmpdir();
$temp_dir = tempdir( DIR=>$temp_loc,CLEANUP => !$keep );

my $tmpf="$temp_dir/seuil.pdf";
my $tmpp="$temp_dir/seuil.ppm";

sub makepdf {
    my ($fich,$r,$g,$b)=@_;
    my $col=sprintf("%.10f %.10f %.10f",$r,$g,$b);
    open(PDF,">$fich");
    print PDF q|%PDF-1.4
%‚„œ”
1 0 obj
<</ITXT(2.1.7)/Kids[2 0 R]/Type/Pages/Count 1>>
endobj
2 0 obj
<</Group<</CS/DeviceRGB/Type/Group/S/Transparency>>/Parent 1 0 R/MediaBox[0 0 171.428574 171.428574]/Resources 3 0 R/pdftk_PageNum 1/Type/Page/Contents 4 0 R>>
endobj
3 0 obj
<</ExtGState<</a0<</ca 1/CA 1>>>>>>
endobj
4 0 obj
<</Length 211>>stream
q
|.$col.q| rg /a0 gs
|.$col.q| RG 1.6 w
1 J
1 j
[] 0.0 d
4 M q 1 0 0 -1 0 171.428574 cm
0 0 m 171.43 0 l 171.43 171.43 l 0 171.43 l 0 0 l h
0 0 m B Q
Q

endstream
endobj
5 0 obj
<</Pages 1 0 R/Type/Catalog>>
endobj
6 0 obj
<</Creator(cairo 1.8.8 \(http://cairographics.org\))/Producer(cairo 1.8.8 \(http://cairographics.org\); modified using iText 2.1.7 by 1T3XT)/ModDate(D:20100121174015+01'00')>>
endobj
xref
0 7
0000000000 65535 f 
0000000015 00000 n 
0000000078 00000 n 
0000000253 00000 n 
0000000304 00000 n 
0000000563 00000 n 
0000000608 00000 n 
trailer
<</Info 6 0 R/Root 5 0 R/Size 7/ID [<50f634ab8ce0f97a408f40d266f9507a><cc5994650a530fa9590a7aba738497ee>]>>
startxref
799
%%EOF
|;
}

sub transfo {
    my (@cols)=@_;
    my @i=();

    makepdf($tmpf,@cols);
    system(with_prog('AMC-raster.pl'),'--moteur',$moteur,'--dpi',10,$tmpf,$tmpp);

    my $im=AMC::Image::new($tmpp);
    my @mag=$im->commande('pixel 10 10');
    for(@mag) {
	if(/RGB=([0-9]+)\s+([0-9]+)\s+([0-9]+)/) {
	    @i=($1,$2,$3);
	}
    }

    print "** ".join(' ',@cols).' --> '.join(' ',@i)."\n";
    return(@i);
}

if($a) {
    $a0=0;
    $a1=1;
    
    print "$a0 $a1\n";
    do {
	@tests=map { $a0+$_*($a1-$a0)/4 } (1,2,3);
	@i=transfo(@tests);
	for my $j (0..2) {
	    $a0=$tests[$j] if($i[$j]<$a);
	}
	for my $j (reverse(0..2)) {
	    $a1=$tests[$j] if($i[$j]>=$a);
	}
	print "$a0 $a1\n";
    } while(($a1-$a0)>$delta);
    
    @i=transfo($a0,$a1,1);
    
    print "--> ".$i[0]." ".$i[1]."\n";
    $s=($a0+$a1)/2;
    print "Seuil ".($a-1)." - $a estime : $s\n";
    print "Seuil * 255 = ".(255*$s)."\n";
    print "Seuil * 256 = ".(256*$s)."\n";
}




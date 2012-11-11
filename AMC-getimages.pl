#! /usr/bin/perl -w
#
# Copyright (C) 2012 Alexis Bienvenue <paamc@passoire.fr>
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

use AMC::Basic;
use AMC::Gui::Avancement;

use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempdir /;
use File::Copy;
use Unicode::Normalize;

use Getopt::Long;

use_gettext;

my $list_file='';
my $progress_id='';
my $copie='';
my $debug='';
my $vector_density=300;

GetOptions("list=s"=>\$list_file,
	   "progression-id=s"=>\$progress_id,
	   "copy-to=s"=>\$copie,
	   "debug=s"=>\$debug,
	   "vector-density=s"=>\$vector_density,
	  );

set_debug($debug);

$copie =~ s:(?<=.)/+$::;

my @f=(@ARGV);
my @fs;

if(-f $list_file) {
  open(LIST,$list_file);
  while(<LIST>) {
    chomp;
    push @f,$_;
  }
  close(LIST);
}

my $dp;
my $p;
$p=AMC::Gui::Avancement::new(1,'id'=>$progress_id)
  if($progress_id);

# first pass: split multi-page PDF with pdftk, which uses less
# memory than ImageMagick

if(commande_accessible('pdftk')) {

  my @pdfs=grep { /\.pdf$/i } @f;
  @fs=grep { ! /\.pdf$/i } @f;

  if(@pdfs) {
    $dp=1/(1+$#pdfs);
    $p->text(__("Splitting multi-page PDF files..."));

    for my $file (@pdfs) {

      my $temp_loc=tmpdir();
      my $temp_dir = tempdir( DIR=>$temp_loc,
			      CLEANUP => (!get_debug()) );

      debug "PDF split tmp dir: $temp_dir";

      system("pdftk",$file,"burst","output",
	     $temp_dir.'/page-%04d.pdf');

      opendir(my $dh, $temp_dir)
	|| debug "can't opendir $temp_dir: $!";
      push @fs, map { "$temp_dir/$_" }
	sort { $a cmp $b } grep { /^page/ } readdir($dh);
      closedir $dh;

      $p->progres($dp);
    }

    $p->text('');
  }

  @f=@fs;
}

# second pass: split other multi-page images (such as TIFF) with
# ImageMagick, and convert vector to bitmap

@fs=();
for my $fich (@f) {
  my (undef,undef,$fich_n)=splitpath($fich);
  my $suffix_change='';
  my @pre_options=();

  # number of pages :
  my $np=0;
  # any scene with number > 0 ? This may cause problems with OpenCV
  my $scene=0;
  open(NP,"-|",magick_module("identify"),"-format","%s\n",$fich);
  while(<NP>) {
    chomp();
    if(/[^\s]/) {
      $np++;
      $scene=1 if($_ > 0);
    }
  }
  close(NP);
  # Is this a vector format file? If so, we have to convert it
  # to bitmap
  my $vector='';
  if($fich_n =~ /\.(pdf|eps|ps)$/i) {
    $vector=1;
    $suffix_change='.png';
    @pre_options=('-density',$vector_density)
      if($vector_density);
  }

  debug "> Scan $fich: $np page(s)".($scene ? " [has scene>0]" : "");
  if($np>1 || $scene || $vector) {
    # split multipage image into 1-page images, and/or convert
    # to bitmap format

    $p->text(sprintf(
		     ($vector
# TRANSLATORS: Here, %s will be replaced with the path of a file that will be converted.
		      ? __("Converting %s to bitmap...")
# TRANSLATORS: Here, %s will be replaced with the path of a file that will be splitted to several images (one per page).
		      : __("Splitting multi-page image %s...")),
		     $fich_n));

    my $temp_loc=tmpdir();
    my $temp_dir = tempdir( DIR=>$temp_loc,
			    CLEANUP => (!get_debug()) );

    debug "Image split tmp dir: $temp_dir";

    my ($fxa,$fxb,$fb) = splitpath($fich);
    if(! ($fb =~ s/\.([^.]+)$/_%04d.$1/)) {
      $fb .= '_%04d';
    }
    $fb.=$suffix_change;

    system(magick_module("convert"),
	   @pre_options,$fich,"+adjoin","$temp_dir/$fb");
    opendir(my $dh, $temp_dir) || debug "can't opendir $temp_dir: $!";
    my @split = grep { -f "$temp_dir/$_" }
      sort { $a cmp $b } readdir($dh);
    closedir $dh;

    # if not to be copied in project dir, put them in the
    # same directory as original image

    if($copie) {
      push @fs,map { "$temp_dir/$_" } @split;
    } else {
      for(@split) {
	my $dest=catpath($fxa,$fxb,$_);
	debug "Moving one page to $dest";
	move("$temp_dir/$_",$dest);
	push @fs,$dest;
      }
    }

    $p->text('');
  } else {
    push @fs,$fich;
  }
}

@f=@fs;

# if requested, copy files to project directory

if($copie && @f) {
  $p->text(__"Copying scans to project directory...");

  $dp=1/(1+$#f);

  my @fl=();
  my $c=0;
  for my $fich (@f) {
    my ($fxa,$fxb,$fb) = splitpath($fich);

    # no accentuated or special characters in filename, please!
    # this could break the process somewere...
    $fb=NFKD($fb);
    $fb =~ s/\pM//og;
    $fb =~ s/[^a-zA-Z0-9.-_+]+/_/g;
    $fb =~ s/^[^a-zA-Z0-9]/scan_/;

    my $dest=$copie."/".$fb;
    my $deplace=0;

    if($fich ne $dest) {
      if(-e $dest) {
	# dest file already exists: change name
	debug "File $dest already exists";
	$dest=new_filename($dest);
	debug "--> $dest";
      }
      if(copy($fich,$dest)) {
	push @fl,$dest;
	$deplace=1;
      } else {
	debug "$fich --> $dest";
	debug "COPY ERROR: $!";
      }
    }
    $c+=$deplace;
    push @fl,$fich if(!$deplace);

    $p->progres($dp);
  }
  debug "Copied scan files: ".$c."/".(1+$#f);
  @f=@fl;

  $p->text('');
}

open(LIST,">",$list_file);
for(@f) {
  print LIST "$_\n";
}
close(LIST);

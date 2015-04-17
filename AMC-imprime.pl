#! /usr/bin/perl
#
# Copyright (C) 2008-2014 Alexis Bienvenue <paamc@passoire.fr>
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
use File::Spec::Functions qw/tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use File::Copy;

use Module::Load;
use Module::Load::Conditional qw/check_install/;

use AMC::Basic;
use AMC::Exec;
use AMC::Data;
use AMC::Gui::Avancement;

my $data_dir="";
my $sujet='';
my $print_cmd='cupsdoprint %f';
my $progress='';
my $progress_id='';
my $debug='';
my $fich_nums='';
my $methode='CUPS';
my $imprimante='';
my $options='number-up=1';
my $output_file='';
my $output_answers_file='';
my $split='';
my $extract_with='pdftk';

GetOptions(
	   "data=s"=>\$data_dir,
	   "sujet=s"=>\$sujet,
	   "fich-numeros=s"=>\$fich_nums,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "print-command=s"=>\$print_cmd,
	   "methode=s"=>\$methode,
	   "imprimante=s"=>\$imprimante,
	   "output=s"=>\$output_file,
	   "split!"=>\$split,
	   "options=s"=>\$options,
	   "debug=s"=>\$debug,
	   "extract-with=s"=>\$extract_with,
	   );

set_debug($debug);

my $commandes=AMC::Exec::new('AMC-imprime');
$commandes->signalise();

die "Needs data directory" if(!$data_dir);
die "Needs subject file" if(!$sujet);

die "Needs print command" if($methode =~ /^command/i && !$print_cmd);
die "Needs output file" if($methode =~ /^file/i && !$output_file);

my @available_extracts=(qw/pdftk gs/);

die "Invalid value for extract_with"
  if(!grep(/^$extract_with$/,@available_extracts));

@available_extracts=grep { commande_accessible($_) }
  @available_extracts;

die "No available extract engine" if(!@available_extracts);

if(!grep(/^$extract_with$/,@available_extracts)) {
  $extract_with=$available_extracts[0];
  debug("Switching to extract engine $extract_with");
}

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $data=AMC::Data->new($data_dir);
my $layout=$data->module('layout');

my @es;

if($fich_nums) {
    open(NUMS,$fich_nums);
    while(<NUMS>) {
	push @es,$1 if(/^([0-9]+)$/);
    }
    close(NUMS);
} else {
  $layout->begin_read_transaction('prST');
  @es=$layout->query_list('students');
  $layout->end_transaction('prST');
}

my $cups;
my $dest;

if($methode =~ /^cups/i) {
    if(check_install(module=>"Net::CUPS")) {
	load("Net::CUPS");
	debug_pm_version("Net::CUPS");
    } else {
	die "Needs Net::CUPS perl module for CUPS printing";
    }

    $cups=Net::CUPS->new();
    $dest=$cups->getDestination($imprimante);
    die "Can't access printer: $imprimante" if(!$dest);
    for my $o (split(/\s*,+\s*/,$options)) {
	my $on=$o;
	my $ov=1;
	if($o =~ /([^=]+)=(.*)/) {
	    $on=$1;
	    $ov=$2;
	}
	debug "Option : $on=$ov";
	$dest->addOption($on,$ov);
    }
}

sub process_pages {
  my ($first,$last,$f_dest,$elong)=@_;

  my $tmp = File::Temp->new( DIR=>tmpdir(),UNLINK => 1, SUFFIX => '.pdf' );
  $fn=$tmp->filename();

  print "Student $elong : pages $first-$last in file $fn...\n";

  if($extract_with eq 'gs') {
    $commandes->execute("gs","-dBATCH","-dNOPAUSE","-q","-sDEVICE=pdfwrite",
			"-sOutputFile=$fn",
			"-dFirstPage=$first","-dLastPage=$last",
			$sujet);
  } elsif($extract_with eq 'pdftk') {
    $commandes->execute("pdftk",$sujet,"cat","$first-$last","output",$fn);
  }

  if($methode =~ /^cups/i) {
    $dest->printFile($fn,"QCM : sheet $elong");
  } elsif($methode =~ /^file/i) {
    $f_dest.="-%e.pdf" if($f_dest !~ /[%]e/);
    $f_dest =~ s/[%]e/$elong/g;

    debug "Moving to $f_dest";
    move($fn,$f_dest);
  } elsif($methode =~ /^command/i) {
    my @c=map { s/[%]f/$fn/g; s/[%]e/$elong/g; $_; } split(/\s+/,$print_cmd);

    #print STDERR join(' ',@c)."\n";
    $commandes->execute(@c);
  } else {
    die "Unknown method: $methode";
  }

  close($tmp);
}

for my $e (@es) {
  my $elong=sprintf("%04d",$e);
  my ($debut,$fin,$debutA,$finA);
  $layout->begin_read_transaction('prSP');
  ($debut,$fin)=$layout->query_row('subjectpageForStudent',$e);
  ($debutA,$finA)=$layout->query_row('subjectpageForStudentA',$e)
    if($split);
  $layout->end_transaction('prSP');

  if($split) {
    if($debut<$debutA) {
      process_pages($debut,$debutA-1,$output_file,$elong."-0S");
    }
    process_pages($debutA,$finA,$output_file,$elong."-1A");
    if($fin>$finA) {
      process_pages($finA+1,$fin,$output_file,$elong."-2S");
    }
  } else {
    process_pages($debut,$fin,$output_file,$elong);
  }

  $avance->progres(1/(1+$#es));
}

$avance->fin();



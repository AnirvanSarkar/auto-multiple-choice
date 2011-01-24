#! /usr/bin/perl
#
# Copyright (C) 2010-2011 Alexis Bienvenue <paamc@passoire.fr>
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
use AMC::Basic;
use AMC::Queue;
use AMC::ANList;

use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;

($e_volume,$e_vdirectories,$e_vfile) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
}

my $seuil=0.15;
my $n_procs=0;
my $an_saved='';
my $cr_dir='';

my $progress=1;
my $progress_id='';

my $debug='';

my $rep_projet='';
my $rep_projets='';

GetOptions("seuil=s"=>\$seuil,
	   "n-procs=s"=>\$n_procs,
	   "an-saved=s"=>\$an_saved,
	   "cr-dir=s"=>\$cr_dir,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "debug=s"=>\$debug,
	   "projet=s"=>\$rep_projet,
	   "projets=s"=>\$rep_projets,
	   );


set_debug($debug);

debug("AMC-zooms / DEBUG") if($debug);

my $queue='';

sub catch_signal {
    my $signame = shift;
    debug "*** AMC-prepare : signal $signame, killing queue...";
    $queue->killall() if($queue);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

sub absolu {
    my $s=shift;
    $s=proj2abs({'%PROJET',$rep_projet,
		 '%PROJETS',$rep_projets,
		 '%HOME'=>$ENV{'HOME'},
	     },
		$s);
    return($s);
}

my $an_list;

if($an_saved) {
    $an_list=AMC::ANList::new($cr_dir,
			      'saved'=>$an_saved,
			      'action'=>'',
			      );
} elsif(-d $cr_dir) {
    $anl=AMC::ANList::new($cr_dir,
			  'saved'=>'',
			  );
} else {
    die "No ANList";
}

$queue=AMC::Queue::new('max.procs',$n_procs);

my @ids=$an_list->ids();
my $n=1+$#ids;

my @cmds=();

if($n>0) {
    
    for my $id (@ids) {
	
	my $scan=$an_list->attribut($id,'src');

	if($scan) {
	    my $zf=$cr_dir."/zoom-".id2idf($id).".jpg";
	    my $zd=$cr_dir."/zooms/".id2idf($id,'simple'=>1);

	    if(-d $zd) {
		debug "New zoom structure for ID $id: skipping...";
	    } else {
		
		push @cmds,[with_prog("AMC-zoom.pl"),
			    "--scan",absolu($scan),
			    "--seuil",$seuil,
			    "--analyse",$an_list->attribut($id,'fichier-scan'),
			    "--output",$zf,
			    "--progression-id",$progress_id,
			    "--debug",$debug,
		];
	    }
	} else {
	    debug "ID=$id --> no scan";
	}
    }
    
    $n=1+$#cmds;

    if($n>0) {
	debug "Zooms to extract: $n";

	for(@cmds) {
	    $queue->add_process(@$_,"--progression",1/$n);
	}
			    
	$queue->run();
    } else {
	debug "No zooms to extract...";
    }
}


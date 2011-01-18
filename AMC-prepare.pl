#! /usr/bin/perl
#
# Copyright (C) 2008-2011 Alexis Bienvenue <paamc@passoire.fr>
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

use XML::Simple;
use File::Copy;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use Data::Dumper;
use Getopt::Long;

use IO::File;
use XML::Writer;

use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::Queue;

use_gettext;

$VERSION_BAREME=2;

my $cmd_pid='';

my $queue='';

sub catch_signal {
    my $signame = shift;
    debug "*** AMC-prepare : signal $signame, killing $cmd_pid...";
    kill 9,$cmd_pid if($cmd_pid);
    $queue->killall() if($queue);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

my $mode="mbs";
my $mep_dir="";
my $bareme="";
my $convert_opts="-limit memory 512mb";
my $dpi=300;
my $calage='';

my $moteur_latex='latex';

my $prefix='';

my $debug='';

my $n_procs=0;
my $nombre_copies=0;

my $progress=1;
my $progress_id='';

my $out_calage='';
my $out_sujet='';
my $out_corrige='';

my $moteur_raster='poppler';

my $encodage_interne='UTF-8';

GetOptions("mode=s"=>\$mode,
	   "with=s"=>\$moteur_latex,
	   "mep=s"=>\$mep_dir,
	   "bareme=s"=>\$bareme,
	   "calage=s"=>\$calage,
	   "out-calage=s"=>\$out_calage,
	   "out-sujet=s"=>\$out_sujet,
	   "out-corrige=s"=>\$out_corrige,
	   "dpi=s"=>\$dpi,
	   "convert-opts=s"=>\$convert_opts,
	   "debug=s"=>\$debug,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "prefix=s"=>\$prefix,
	   "n-procs=s"=>\$n_procs,
	   "n-copies=s"=>\$nombre_copies,
	   "raster=s"=>\$moteur_raster,
	   );

set_debug($debug);

debug("AMC-prepare / DEBUG") if($debug);

$queue=AMC::Queue::new('max.procs',$n_procs);

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $tex_source=$ARGV[0];

die "Nonexistent LaTeX file: $tex_source" if(! -f $tex_source);

my $base=$tex_source;
$base =~ s/\.tex$//gi;

$bareme="$base-bareme.xml" if(!$bareme);
$mep_dir="$base-mep" if(!$mep_dir);

for(\$bareme,\$mep_dir,\$tex_source) {
    $$_=rel2abs($$_);
}

if(! -x $mep_dir) {
    mkdir($mep_dir);
}

die "Nonexistent directory: $mep_dir" if(! -d $mep_dir);

($e_volume,$e_vdirectories,$e_vfile) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
}

my $n_erreurs;
my $a_erreurs;
my @erreurs_msg=();
my %info_vars=();

sub verifie_q {
    my ($q,$t)=@_;
    if($q) {
	if(! $q->{'mult'}) {
	    my $oui=0;
	    my $tot=0;
	    for my $i (grep { /^R/ } (keys %$q)) {
		$tot++;
		$oui++ if($q->{$i});
	    }
	    if($oui!=1 && !$q->{'indicative'}) {
		$a_erreurs++;
		push @erreurs_msg,"ERR: "
		    .sprintf(__("%d/%d good answers not coherent for a simple question")." [%s]\n",$oui,$tot,$t);
	    }
	}
    }
}

sub analyse_amclog {
    # check common errors in LaTeX about questions:
    # * same ID used multiple times for the same paper
    # * simple questions with number of good answers != 1
    my ($fich)=@_;

    my %analyse_data=();
    my %titres=();
    @erreurs_msg=();

    debug("Check AMC log : $fich");

    open(AMCLOG,$fich) or die "Unable to open $fich : $!";
    while(<AMCLOG>) {

	if(/AUTOQCM\[Q=([0-9]+)\]/) { 
	    verifie_q($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});
	    $analyse_data{'q'}={};
	    if($analyse_data{'qs'}->{$1}) {
		$a_erreurs++;
		push @erreurs_msg,"ERR: "
		    .sprintf(__("question ID used several times for the same paper: \"%s\"")." [%s]\n",$titres{$1},$analyse_data{'etu'});
	    }
	    $analyse_data{'titre'}=$titres{$1};
	    $analyse_data{'qs'}->{$1}=1;
	}
	if(/AUTOQCM\[ETU=([0-9]+)\]/) {
	    verifie_q($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});
	    %analyse_data=('etu'=>$1,'qs'=>{});
	}
	if(/AUTOQCM\[NUM=([0-9]+)=([^\]]+)\]/) {
	    $titres{$1}=$2;
	    $analyse_data{'titres'}->{$2}=1;
	}
	if(/AUTOQCM\[MULT\]/) { 
	    $analyse_data{'q'}->{'mult'}=1;
	}
	if(/AUTOQCM\[INDIC\]/) { 
	    $analyse_data{'q'}->{'indicative'}=1;
	}
	if(/AUTOQCM\[REP=([0-9]+):([BM])\]/) {
	    my $rep="R".$1;
	    if($analyse_data{'q'}->{$rep}) {
		$a_erreurs++;
		push @erreurs_msg,"ERR: "
		    .sprintf(__("Answer number ID used several times for the same question: %s")." [%s]\n",$1,$analyse_data{'titre'});
	    }
	    $analyse_data{'q'}->{$rep}=($2 eq 'B' ? 1 : 0);
	}
	if(/AUTOQCM\[VAR:([0-9a-zA-Z.-]+)=([^\]]+)\]/) {
	    $info_vars{$1}=$2;
	}
    
    }
    close(AMCLOG);
    
    verifie_q($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});

    debug(@erreurs_msg);
    print join('',@erreurs_msg);

    debug("AMC log $fich : $a_erreurs errors.");
}

sub execute {
    my %oo=(@_);

    my $n_run=0;
    my $rerun=0;
    my $format='';

    for my $ext (qw/pdf dvi ps/) {
	if(-f $f_base.".$ext") {
	    debug "Removing old $ext";
	    unlink($f_base.".$ext");
	}
    }

    do {

	$n_run++;
	
	$n_erreurs=0;
	$a_erreurs=0;
    
	debug "%%% Compiling: pass $n_run";

	$cmd_pid=open(EXEC,"-|",@{$oo{'command'}});
	die "Can't exec ".join(' ',@{$oo{'command'}}) if(!$cmd_pid);

	while(<EXEC>) {
	    #LaTeX Warning: Label(s) may have changed. Rerun to get cross-references right.
	    $rerun=1 if(/^LaTeX Warning:.*Rerun to get cross-references right/);
	    $format=$1 if(/^Output written on .*\.([a-z]+) \(/);

	    $n_erreurs++ if(/^\!.*\.$/);
	    print $_ if(/^.+$/);
	}
	close(EXEC);
	$cmd_pid='';

    } while($rerun && $n_run<=1 && ! $oo{'once'});

    # transformation dvi en pdf si besoin...

    $format='dvi' if($moteur_latex eq 'latex');
    $format='pdf' if($moteur_latex eq 'pdflatex');
    $format='pdf' if($moteur_latex eq 'xelatex');

    print "Output format: $format\n";
    debug "Output format: $format\n";

    if($format eq 'dvi') {
	if(-f $f_base.".dvi") {
	    system("dvips","-q",$f_base,"-o",$f_base.".ps");
	    print "Error dvips : $?\n" if($?);
	    if(-f $f_base.".ps") {
		system("ps2pdf",$f_base.".ps",$f_base.".pdf");
		print "Error ps2pdf : $?\n" if($?);
	    } else {
		debug "No PS";
	    }
	} else {
	    debug "No DVI";
	}
    }

}

$temp_loc=tmpdir();
$temp_dir = tempdir( DIR=>$temp_loc,CLEANUP => 1 );

# reconnaissance mode binaire/decimal :

$binaire='--binaire';

$cmd_pid=open(SCANTEX,$tex_source);
die "Error reading $tex_source: $!" if(!$cmd_pid);

while(<SCANTEX>) {
    if(/usepackage\[([^\]]+)\]\{automultiplechoice\}/) {
	my $opts=$1;
	if($opts =~ /\bdecimal\b/) {
	    $binaire="--no-binaire";
	    print "Decimal mode.\n";
	}

    }
}
close(SCANTEX);
$cmd_pid='';

# on se place dans le repertoire du LaTeX
($v,$d,$f_tex)=splitpath($tex_source);
chdir(catpath($v,$d,""));
$f_base=$f_tex;
$f_base =~ s/\.tex$//i;

$prefix=$f_base."-" if(!$prefix);

sub transfere {
    my ($orig,$dest)=@_;
    if(-f $orig) {
	debug "Moving $orig --> $dest";
	move($orig,$dest);
    } else {
	debug "No source: removing $dest";
	unlink($dest);
    }
}

sub latex_cmd {
    my (%o)=@_;

    $o{'AMCNombreCopies'}=$nombre_copies if($nombre_copies>0);

    return($moteur_latex,
	   "\\nonstopmode"
	   .join('',map { "\\def\\".$_."{".$o{$_}."}"; } (keys %o) )
	   ." \\input{\"$f_tex\"}");
}

sub check_moteur {
    if(!commande_accessible($moteur_latex)) {
	print "ERR: ".sprintf(__("LaTeX command configured is not present (%s). Install it or change configuration, and then rerun."),$moteur_latex)."\n";
	exit(1);
    }
}

if($mode =~ /k/) {
    # CORRECTION INDIVIDUELLE

    check_moteur();

    execute('command'=>[latex_cmd(qw/NoWatermarkExterne 1 NoHyperRef 1 CorrigeIndivExterne 1/)]);
    transfere("$f_base.pdf",($out_corrige ? $out_corrige : $prefix."corrige.pdf"));
    if($n_erreurs>0) {
	print "ERR: "
	    .sprintf(__("%d errors during LaTeX compiling")." (%s)\n",$n_erreurs,__"individual solution");
	exit(1);
    }
}

if($mode =~ /s/) {
    # SUJETS

    check_moteur();

    my %opts=(qw/NoWatermarkExterne 1 NoHyperRef 1/);

    $out_calage=$prefix."calage.xy" if(!$out_calage);
    $out_corrige=$prefix."corrige.pdf" if(!$out_corrige);
    $out_sujet=$prefix."sujet.pdf" if(!$out_sujet);

    for my $f ($out_calage,$out_corrige,$out_sujet) {
	if(-f $f) {
	    debug "Removing already existing file: $f";
	    unlink($f);
	}
    }
	       

    # 1) sujet et calage

    execute('command'=>[latex_cmd(%opts,'SujetExterne'=>1)]);
    analyse_amclog("$f_base.amc");
    transfere("$f_base.pdf",$out_sujet);
    if($n_erreurs>0) {
	print "ERR: "
	    .sprintf(__("%d errors during LaTeX compiling")." (%s)\n",$n_erreurs,__"question sheet");
	exit(1);
    }
    exit(1) if($a_erreurs>0);

    transfere("$f_base.xy",$out_calage);

    # transmission des variables

    print "Variables :\n";
    for my $k (keys %info_vars) {
	print "VAR: $k=".$info_vars{$k}."\n";
    }

    # 2) corrige

    execute('command'=>[latex_cmd(%opts,'CorrigeExterne'=>1)]);
    transfere("$f_base.pdf",$out_corrige);
    if($n_erreurs>0) {
	print "ERR: "
	    .sprintf(__("%d errors during LaTeX compiling")." (%s)\n",$n_erreurs,__"solution");
	exit(1);
    }


}

if($mode =~ /m/) {
    # MISE EN PAGE

    my $xyfile=$calage;
    $xyfile =~ s/\.pdf/.xy/;
    
    if($xyfile =~ /\.xy$/ && -f $xyfile) {

	$|++;
	my @c=(with_prog("AMC-meptex.pl"),
	       "--mep-dir",$mep_dir,
	       "--progression",0.93*$progress,
	       "--progression-id",$progress_id,
	       "--src",$xyfile);

	$cmd_pid=open(EXEC,"-|",@c) ;
	
	debug "[$cmd_pid] MEP-Tex: ".join(' ',@c);

	die "Can't exec AMC-meptex.pl: $!" if(!$cmd_pid);
	while(<EXEC>) {
	    print $_;
	    chomp;
	    debug($_);
	}
	close(EXEC);
	
    } else {

	# OLD STYLE CALIBRATION PDF FILE - ONLY WHEN DOCUMENTS
	# WERE MADE WITH OLD AMC VERSION

	# 1) compilation en mode calibration

	if(-f $calage) {
	    print "Using file $calage\n";
	} else {
	    print "********** Compilation...\n";
	    
	    execute('command'=>[latex_cmd(qw/CalibrationExterne 1 NoHyperRef 1/)]);
	    $calage="$f_base.pdf";
	}

	$avance->progres(0.07);

	# 2) analyse page par page

	print "********** To bitmap and analysis...\n";

	if($moteur_raster eq 'poppler') {

	    # tout en un grace a poppler

	    $|++;
	    my @c=(with_prog("AMC-mepdirect"),
		   "-r",$dpi,
		   "-d",$mep_dir,
		   "-e",0.93*$progress,
		   "-n",$progress_id,
		   $calage);

	    $cmd_pid=open(EXEC,"-|",@c) ;

	    debug "[$cmd_pid] Poppler: ".join(' ',@c);

	    die "Can't exec AMC-mepdirect: $!" if(!$cmd_pid);
	    while(<EXEC>) {
		print $_;
		chomp;
		debug($_);
	    }
	    close(EXEC);

	} else {

	    die "This method is no longer supported... Please make new version of working documents, or switch to Poppler.";
	}
    }
}

if($mode =~ /b/) {
    # BAREME

    print "********** Making marks scale...\n";

    # compilation en mode calibration

    my %bs=();
    my %qs=();
    my %titres=();

    my $quest='';
    my $rep='';
    my $etu='';

    my $delta=0;

    execute('command'=>[latex_cmd(qw/CalibrationExterne 1 NoHyperRef 1/)],
	    'once'=>1);
    open(AMCLOG,"$f_base.amc") or die "Unable to open $f_base.amc : $!";
    while(<AMCLOG>) {
	debug($_);
	if(/AUTOQCM\[TOTAL=([\s0-9]+)\]/) { 
	    my $t=$1;
	    $t =~ s/\s//g;
	    if($t>0) {
		$delta=1/$t;
	    } else {
		print "*** TOTAL=$t ***\n";
	    }
	}
	if(/AUTOQCM\[FQ\]/) {
	    $quest='';
	    $rep='';
	}
	if(/AUTOQCM\[Q=([0-9]+)\]/) { 
	    $quest=$1;
	    $rep=''; 
	    $qs{$quest}={};
	}
	if(/AUTOQCM\[ETU=([0-9]+)\]/) {
	    $avance->progres($delta) if($etu ne '');
	    $etu=$1;
	    print "Sheet $etu...\n";
	    debug "Sheet $etu...\n";
	    $bs{$etu}={};
	}
	if(/AUTOQCM\[NUM=([0-9]+)=([^\]]+)\]/) {
	    $titres{$1}=$2;
	}
	if(/AUTOQCM\[MULT\]/) { 
	    $qs{$quest}->{'multiple'}=1;
	}
	if(/AUTOQCM\[INDIC\]/) { 
	    $qs{$quest}->{'indicative'}=1;
	}
	if(/AUTOQCM\[REP=([0-9]+):([BM])\]/) {
	    $rep=$1;
	    $bs{$etu}->{"$quest.$rep"}={-bonne=>($2 eq 'B' ? 1 : 0)};
	}
	if(/AUTOQCM\[B=([^\]]+)\]/) {
	    $bs{$etu}->{"$quest.$rep"}->{-bareme}=$1;
	}
	if(/AUTOQCM\[BD(S|M)=([^\]]+)\]/) {
	    $bs{'defaut'}->{"$1."}->{-bareme}=$2;
	}
    }
    close(AMCLOG);
    $cmd_pid='';

    debug "Writing $bareme";

    my $output=new IO::File($bareme,
			    ">:encoding($encodage_interne)");
    if(! $output) {
	die "Can't open $bareme: $!";
    }

    my $writer = new XML::Writer(OUTPUT=>$output,
				 ENCODING=>$encodage_interne,
				 DATA_MODE=>1,
				 DATA_INDENT=>2);
    $writer->xmlDecl($encodage_interne);

    my %opts=(src=>$f_tex,
	      version=>$VERSION_BAREME);

    $opts{'main'}=$bs{''}->{'.'}->{-bareme} if($bs{''}->{'.'}->{-bareme});

    $writer->startTag('bareme',%opts);

    for my $etu (grep { $_ ne '' } (keys %bs)) {
	$writer->startTag('etudiant',id=>$etu);

	my $bse=$bs{$etu};
	my @q_ids=();
	if($etu eq 'defaut') {
	    @q_ids=('S','M');
	} else {
	    @q_ids=(keys %qs);
	}
	for my $q (@q_ids) {
	    $writer->startTag('question',id=>$q,
			     titre=>$titres{$q},
			     bareme=>$bse->{"$q."}->{-bareme},
			     indicative=>$qs{$q}->{'indicative'},
			     multiple=>$qs{$q}->{'multiple'},
			     );

	    for my $i (keys %$bse) {
		if($i =~ /^$q\.([0-9]+)/) {
		    my $rep=$1;
		    $writer->emptyTag('reponse',
				      id=>$rep,
				      bonne=>$bse->{$i}->{-bonne},
				      bareme=>$bse->{"$i"}->{-bareme},
				      );
		}
	    }
	    $writer->endTag('question');
	}
	$writer->endTag('etudiant');
    }
    $writer->endTag('bareme');
    $writer->end();
    $output->close();
}

$avance->fin();

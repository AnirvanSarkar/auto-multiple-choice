#! /usr/bin/perl
#
# Copyright (C) 2008-2009 Alexis Bienvenue <paamc@passoire.fr>
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

use XML::Simple;
use File::Copy;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use Data::Dumper;
use Getopt::Long;

use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::Queue;

$VERSION_BAREME=2;

my $cmd_pid='';

my $queue='';

sub catch_signal {
    my $signame = shift;
    debug "*** AMC-prepare : signal $signame, je tue $cmd_pid...";
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

my $ppm_via='pdf';
my $with_prog='latex';

my $prefix='';

my $debug='';

my $n_procs=0;

my $progress=1;
my $progress_id='';

GetOptions("mode=s"=>\$mode,
	   "via=s"=>\$ppm_via,
	   "with=s"=>\$with_prog,
	   "mep=s"=>\$mep_dir,
	   "bareme=s"=>\$bareme,
	   "calage=s"=>\$calage,
	   "dpi=s"=>\$dpi,
	   "convert-opts=s"=>\$convert_opts,
	   "debug=s"=>\$debug,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "prefix=s"=>\$prefix,
	   "n-procs=s"=>\$n_procs,
	   );

set_debug($debug);

debug("AMC-prepare / DEBUG") if($debug);

$queue=AMC::Queue::new('max.procs',$n_procs);

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $tex_source=$ARGV[0];

die "Fichier inconnu : $tex_source" if(! -f $tex_source);

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

die "Repertoire inexistant : $mep_dir" if(! -d $mep_dir);

($e_volume,$e_vdirectories,$e_vfile) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
}

my $n_erreurs;
my $a_erreurs;
my $analyse_q='';

sub execute {
    my @s=@_;
    my %analyse_data=();
    my %titres=();

    $n_erreurs=0;
    $a_erreurs=0;

    $cmd_pid=open(EXEC,"-|",@s) or die "Impossible d'executer $s";
    while(<EXEC>) {
	if($analyse_q) {
	    
	    if(/AUTOQCM\[Q=([0-9]+)\]/) { 
		verifie_q($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});
		$analyse_data{'q'}={};
		if($analyse_data{'qs'}->{$1}) {
		    $a_erreurs++;
		    print "ERR: identifiant d'exercice utilisé plusieurs fois : « ".$titres{$1}." » [".$analyse_data{'etu'}."]\n";
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
		    print "ERR: numéro de réponse utilisé plusieurs fois : $1 [".$analyse_q{'etu'}.":".$analyse_data{'titre'}."]\n";
		}
		$analyse_data{'q'}->{$rep}=($2 eq 'B' ? 1 : 0);
	    }
	}
	s/AUTOQCM\[.*\]//g;
	$n_erreurs++ if(/^\!.*\.$/);
	print $_ if(/^.+$/);
    }
    close(EXEC);
    verifie_q($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'}) if($analyse_q);
    $cmd_pid='';
}

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
		print "ERR: $oui/$tot bonnes réponses dans une question simple [$t]\n";
	    }
	}
    }
}

$temp_loc=tmpdir();
$temp_dir = tempdir( DIR=>$temp_loc,CLEANUP => 1 );

# reconnaissance mode binaire/decimal :

$binaire='--binaire';

$cmd_pid=open(SCANTEX,$tex_source) or die "Impossible de lire $tex_source : $!";
while(<SCANTEX>) {
    if(/usepackage\[([^\]]+)\]\{autoQCM\}/) {
	my $opts=$1;
	if($opts =~ /\bdecimal\b/) {
	    $binaire="--no-binaire";
	    print "Mode decimal.\n";
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

sub latex_cmd {
    my ($prefix,@o)=@_;

    my $cmd=($with_prog ne 'latex' ? $with_prog : $prefix."latex");
    
    return($cmd,
	   "\\nonstopmode"
	   .join('',map { "\\def\\".$_."{1}"; } @o )
	   ." \\input{\"$f_tex\"}");
}

if($mode =~ /s/) {
    # SUJETS

    # 1) document de calage

    $analyse_q=1;
    execute(latex_cmd('pdf',qw/NoWatermarkExterne CalibrationExterne NoHyperRef/));
    $analyse_q='';
    if($n_erreurs>0) {
	print "ERR: $n_erreurs erreurs lors de la compilation LaTeX (calage)\n";
	exit(1);
    }
    exit(1) if($a_erreurs>0);
    move("$f_base.pdf",$prefix."calage.pdf");

    # 2) compilation de la correction

    execute(latex_cmd('pdf',qw/NoWatermarkExterne CorrigeExterne NoHyperRef/));
    if($n_erreurs>0) {
	print "ERR: $n_erreurs erreurs lors de la compilation LaTeX (correction)\n";
	exit(1);
    }
    move("$f_base.pdf",$prefix."corrige.pdf");

    # 3) compilation du sujet

    execute(latex_cmd('pdf',qw/NoWatermarkExterne SujetExterne NoHyperRef/));
    if($n_erreurs>0) {
	print "ERR: $n_erreurs erreurs lors de la compilation LaTeX (sujet)\n";
	exit(1);
    }
    move("$f_base.pdf",$prefix."sujet.pdf");

}

if($mode =~ /m/) {
    # MISE EN PAGE

    # 1) compilation en mode calibration

    print "********** Compilation...\n";

    if(-f $calage && $calage =~ /\.$ppm_via$/) {
	print "Utilisation du fichier de calage $calage\n";
    } else {
	if($ppm_via eq 'pdf') {
	    execute(latex_cmd('pdf',qw/CalibrationExterne NoHyperRef/));
	} elsif($ppm_via eq 'ps') {
	    execute(latex_cmd('',qw/CalibrationExterne NoHyperRef/));
	    execute("dvips",$f_base,"-o");
	} else {
	    die "Mauvaise valeur pour --via : $ppm_via";
	}
	$calage="$f_base.$ppm_via";
    }

    $avance->progres(0.07);

    # 2) analyse page par page

    print "********** Conversion en bitmap et analyse...\n";

    @pages=();

    if($ppm_via eq 'pdf') {
	$cmd_pid=open(IDCMD,"-|","pdfinfo",$calage)
	    or die "Erreur d'identification : $!";
	while(<IDCMD>) {
	    if(/^Pages:\s+([0-9]+)/) {
		my $npages=$1;
		for my $j (1..$npages) {
		    push @pages,$calage."[".($j-1)."]";
		}
	    }
	}
	close(IDCMD);
	$cmd_pid='';
    } else {
	$cmd_pid=open(IDCMD,"-|","identify",$calage)
	    or die "Erreur d'identification : $!";
	while(<IDCMD>) {
	    if(/^([^\[]+)\[([0-9]+)\]\s+(PDF|PS)/) {
		push @pages,$1."[".$2."]";
	    }
	}
	close(IDCMD);
	$cmd_pid='';
    }
    
    $avance->progres(0.03);
    
    my $npage=0;
    my $np=1+$#pages;
    for my $p (@pages) {
	$npage++;

	$queue->add_process(["convert",split(/\s+/,$convert_opts),
			     "-density",$dpi,
			     "-depth",8,
			     "+antialias",
			     $p,"$temp_dir/page-$npage.ppm"],
			    [with_prog("AMC-calepage.pl"),
			     "--progression-debut",.4,
			     "--progression",0.9/$np*$progress,
			     "--progression-id",$progress_id,
			     "--debug",debug_file(),
			     $binaire,
			     "--pdf-source",$calage,
			     "--page",$npage,
			     "--dpi",$dpi,
			     "--modele",
			     "--mep",$mep_dir,
			     "$temp_dir/page-$npage.ppm"],
			    ['rm',"$temp_dir/page-$npage.ppm"],
			    );
    }

    $queue->run();
}

if($mode =~ /b/) {
    # BAREME

    print "********** Preparation du bareme...\n";

    # compilation en mode calibration

    my %bs=();
    my %qs=();
    my %titres=();

    my $quest='';
    my $rep='';
    my $etu='';

    my $delta=0;

    $cmd_pid=open(TEX,"-|",latex_cmd('pdf',qw/CalibrationExterne NoHyperRef/))
	or die "Impossible d'executer latex";
    while(<TEX>) {
	if(/AUTOQCM\[TOTAL=([\s0-9]+)\]/) { 
	    my $t=$1;
	    $t =~ s/\s//g;
	    if($t>0) {
		$delta=1/$t;
	    } else {
		print "*** TOTAL=$t ***\n";
	    }
	}
	if(/AUTOQCM\[Q=([0-9]+)\]/) { 
	    $quest=$1;
	    $rep=''; 
	    $qs{$quest}={};
	}
	if(/AUTOQCM\[ETU=([0-9]+)\]/) {
	    $avance->progres($delta) if($etu ne '');
	    $etu=$1;
	    print "Copie $etu...\n";
	    debug "Copie $etu...\n";
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
    }
    close(TEX);
    $cmd_pid='';

    debug "Ecriture bareme dans $bareme";

    open(BAR,">",$bareme) or die "Impossible d'ecrire dans $bareme";
    print BAR "<?xml version='1.0' standalone='yes'?>\n";
    print BAR "<bareme src=\"$f_tex\" version=\"$VERSION_BAREME\">\n";
    for my $etu (keys %bs) {
	print BAR "  <etudiant id=\"$etu\">\n";
	my $bse=$bs{$etu};
	for my $q (keys %qs) {
	    print BAR "    <question id=\"$q\""
		." titre=\"".$titres{$q}."\""
		.($bse->{"$q."} ? " bareme=\"".$bse->{"$q."}->{-bareme}."\"" : "")
		.join(" ",map { " ".$_."=\"".$qs{$q}->{$_}."\"" } 
		      grep { /^(indicative|multiple)$/ }
		      (keys %{$qs{$q}}) )
		.">\n";
	    for my $i (keys %$bse) {
		if($i =~ /^$q\.([0-9]+)/) {
		    my $rep=$1;
		    print BAR "      <reponse id=\"$rep\" bonne=\""
			.$bse->{$i}->{-bonne}."\""
			.($bse->{"$i"}->{-bareme} ? " bareme=\"".$bse->{"$i"}->{-bareme}."\"" : "")
			." />\n";
		}
	    }
	    print BAR "    </question>\n";
	}
	print BAR "  </etudiant>\n";
    }
    print BAR "</bareme>\n";
    close(BAR);
}

$avance->fin();

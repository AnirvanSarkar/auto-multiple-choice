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

package AMC::Test;

use AMC::Data;

use File::Spec::Functions qw(tmpdir);
use File::Temp qw(tempfile tempdir);
use File::Copy::Recursive qw(rcopy);
use File::Copy;
use Digest::MD5;

use DBI;

use IPC::Run qw(run);

use Getopt::Long;

sub new {
  my ($class,%oo)=@_;

  my $self=
    {
     'dir'=>'',
     'tex_engine'=>'pdflatex',
     'n_copies'=>5,
     'check_marks'=>'',
     'perfect_copy'=>[3],
     'src'=>'',
     'debug'=>0,
     'scans'=>'',
     'seuil'=>0.5,
     'tol_marque'=>0.4,
     'rounding'=>'i',
     'grain'=>0.01,
     'notemax'=>20,
     'postcorrect_student'=>'',
     'postcorrect_copy'=>'',
     'list'=>'',
     'list_key'=>'id',
     'code'=>'student',
     'check_assoc'=>'',
     'annote'=>'',
     'annote_files'=>[],
     'verdict'=>'%(id) %(ID)'."\n".'TOTAL : %S/%M => %s/%m',
     'verdict_question'=>"\"%"."s/%"."m\"",
     'model'=>'(N).pdf',
     'ok_checksums'=>{},
     'ok_checksums_file'=>'',
     'to_check'=>[],
    };

  for (keys %oo) {
    $self->{$_}=$oo{$_} if(exists($self->{$_}));
  }

  $self->{'dir'} =~ s:/[^/]*$::;

  bless($self,$class);

  if (!$self->{'src'}) {
    opendir(my $dh, $self->{'dir'})
      || die "can't opendir $self->{'dir'}: $!";
    my @tex = grep { /\.tex$/ } readdir($dh);
    closedir $dh;
    $self->{'src'}=$tex[0];
  }

  if (!$self->{'list'}) {
    opendir(my $dh, $self->{'dir'})
      || die "can't opendir $self->{'dir'}: $!";
    my @l = grep { /\.txt$/ } readdir($dh);
    closedir $dh;
    $self->{'list'}=$l[0];
  }

  GetOptions("debug!"=>\$self->{'debug'});

  $self->install;

  $self->{'check_dir'}=tmpdir()."/AMC-VISUAL-TEST";
  mkdir($self->{'check_dir'}) if(!-d $self->{'check_dir'});

  $self->read_checksums($self->{'ok_checksums_file'});
  $self->read_checksums($self->{'dir'}.'/ok-checksums');

  return $self;
}

sub read_checksums {
  my ($self,$file)=@_;

  if (-f $file) {
    my $n=0;
    open CSF,$file or die "Error opening $file: $!";
    while (<CSF>) {
      if (/^\s*([a-f0-9]+)\s/) {
	$self->{'ok_checksums'}->{$1}=1;
	$n++;
      }
    }
    close CSF;
    $self->trace("[I] $n checksums read from $file");
  }

}

sub install {
  my ($self)=@_;

  my $temp_loc=tmpdir();
  $self->{'temp_dir'} = tempdir( DIR=>$temp_loc,
				 CLEANUP => (!$self->{'debug'}) );

  rcopy($self->{'dir'}.'/*',$self->{'temp_dir'});

  print STDERR "[>] Installed in $self->{'temp_dir'}\n";

  if(-d ($self->{'temp_dir'}."/scans") && !$self->{'scans'}) {
    opendir(my $dh, $self->{'temp_dir'}."/scans")
      || die "can't opendir $self->{'temp_dir'}: $!";
    my @s = grep { ! /^\./ } readdir($dh);
    closedir $dh;

    if(@s) {
      $self->trace("[I] Provided scans: ".(1+$#s));
      $self->{'scans'}=[map { $self->{'temp_dir'}."/scans/$_" } @s];
    }
  }

  for my $d (qw(data cr cr/zooms cr/corrections cr/corrections/jpg cr/corrections/pdf)) {
    mkdir($self->{'temp_dir'}."/$d") if(!-d $self->{'temp_dir'}."/$d");
  }

  $self->{'debug_file'}=$self->{'temp_dir'}."/debug.log";
}

sub see_file {
  my ($self,$file)=@_;
  my $ext=$file;
  $ext =~ s/.*\.//;
  $ext=lc($ext);
  my $digest=Digest::MD5->new;
  open(FILE,$file) or die "Can't open '$file': $!";
  while(<FILE>) {
    if($ext eq 'pdf') {
      s:^/Producer \(.*\)::;
      s:^/CreationDate \(.*\)::;
      s:^/ModDate \(.*\)::;
    }
    $digest->add($_);
  }
  close FILE;
  my $dig=$digest->hexdigest;
  my $ff=$file;
  $ff =~ s:.*/::;
  if($self->{'ok_checksums'}->{$dig}) {
    $self->trace("[T] File ok: $ff");
  } else {
    my $i=0;
    my $dest;
    do {
      $dest=sprintf("%s/%04d-%s",$self->{'check_dir'},$i,$ff);
      $i++;
    } while(-f $dest);
    copy($file,$dest);
    push @{$self->{'to_check'}},[$dig,$dest];
  }
}

sub trace {
  my ($self,@m)=@_;
  print STDERR join(' ',@m)."\n";
  open LOG,">>$self->{'debug_file'}";
  print LOG join(' ',@m)."\n";
  close LOG;
}

sub command {
  my ($self,@c)=@_;

  $self->trace("[*] ".join(' ',@c)) if($self->{'debug'});
  if(!run(\@c,'>>',$self->{'debug_file'},'2>>',$self->{'debug_file'})) {
    $self->trace("[E] Command returned with $?");
    exit 1;
  }
}

sub amc_command {
  my ($self,$sub,@opts)=@_;

  push @opts,'--debug','%PROJ/debug.log' if($self->{'debug'});
  @opts=map { s:%DATA:$self->{'temp_dir'}/data:g;
	      s:%PROJ:$self->{'temp_dir'}:g;
	      $_;
	    } @opts;

  $self->command('auto-multiple-choice',$sub,@opts);
}

sub prepare {
  my ($self)=@_;

  $self->amc_command('prepare',
		     '--with',$self->{'tex_engine'},
		     '--mode','s',
		     '--n-copies',$self->{'n_copies'},
		     '--prefix',$self->{'temp_dir'}.'/',
		     '%PROJ/'.$self->{'src'},
		     );
  $self->amc_command('meptex',
		     '--src','%PROJ/calage.xy',
		     '--data','%DATA',
		     );
  $self->amc_command('prepare',
		     '--with',$self->{'tex_engine'},
		     '--mode','b',
		     '--n-copies',$self->{'n_copies'},
		     '--data','%DATA',
		     '%PROJ/'.$self->{'src'},
		     );
}

sub analyse {
  my ($self)=@_;

  if($self->{'perfect_copy'}) {
    $self->amc_command('prepare',
		       '--with',$self->{'tex_engine'},
		       '--mode','k',
		       '--n-copies',$self->{'n_copies'},
		       '--prefix','%PROJ/',
		       '%PROJ/'.$self->{'src'},
		      );
    my $nf=$self->{'temp_dir'}."/num";
    open(NUMS,">$nf");
    for (@{$self->{'perfect_copy'}}) { print NUMS "$_\n"; }
    close(NUMS);
    $self->amc_command('imprime',
		       '--sujet','%PROJ/corrige.pdf',
		       '--methode','file',
		       '--output','%PROJ/xx-copie-%e.pdf',
		       '--fich-numeros',$nf,
		       '--data','%DATA',
		      );
    system("cd $self->{'temp_dir'} ; gm convert xx-*.pdf yy-scan.png");

    opendir(my $dh, $self->{'temp_dir'})
      || die "can't opendir $self->{'temp_dir'}: $!";
    my @s = grep { /^yy-scan\./ } readdir($dh);
    closedir $dh;
    push @{$self->{'scans'}},map { $self->{'temp_dir'}."/$_" } @s;
  }

  $self->amc_command('analyse',
		     '--tol-marque',$self->{'tol_marque'},
		     '--projet','%PROJ',
		     '--data','%DATA',
		     '--debug-image-dir','%PROJ/cr',
		     @{$self->{'scans'}},
		     ) if($self->{'debug'});
  $self->amc_command('analyse',
		     '--tol-marque',$self->{'tol_marque'},
		     '--projet','%PROJ',
		     '--data','%DATA',
		     @{$self->{'scans'}},
		     );
}

sub note {
  my ($self)=@_;

  $self->amc_command('note',
		     '--data','%DATA',
		     '--seuil',$self->{'seuil'},
		     '--grain',$self->{'grain'},
		     '--arrondi',$self->{'rounding'},
		     '--notemax',$self->{'notemax'},
		     '--postcorrect-student',$self->{'postcorrect_student'},
		     '--postcorrect-copy',$self->{'postcorrect_copy'},
		     );
}

sub assoc {
  my ($self)=@_;

  return if(!$self->{'list'});

  $self->amc_command('association-auto',
		     '--liste','%PROJ/'.$self->{'list'},
		     '--liste-key',$self->{'list_key'},
		     '--notes-id',$self->{'code'},
		     '--data','%DATA',
		     );
}

sub get_marks {
  my ($self)=@_;

  my $sf=$self->{'temp_dir'}."/data/scoring.sqlite";
  my $dbh = DBI->connect("dbi:SQLite:dbname=$sf","","");
  $self->{'marks'}=$dbh->selectall_arrayref("SELECT * FROM scoring_mark",
					    { Slice => {} });

  $self->trace("[I] Marks:");
  for my $m (@{$self->{'marks'}}) {
    $self->trace("    ".join(' ',map { $_."=".$m->{$_} } (qw/student copy total max mark/)));
  }
}

sub check_perfect {
  my ($self)=@_;
  return if(!$self->{'perfect_copy'});

  $self->trace("[T] Perfect copies test: "
	       .join(',',@{$self->{'perfect_copy'}}));

  my %p=map { $_=>1 } @{$self->{'perfect_copy'}};

  for my $m (@{$self->{'marks'}}) {
    $p{$m->{'student'}}=0
      if($m->{'total'} == $m->{'max'}
	&& $m->{'total'}>0 );
  }

  for my $i (keys %p) {
    if($p{$i}) {
      $self->trace("[E] Non-perfect copy: $i");
      exit(1);
    }
  }
}

sub check_marks {
  my ($self)=@_;
  return if(!$self->{'check_marks'});

  $self->trace("[T] Marks test: "
	       .join(',',keys %{$self->{'check_marks'}}));

  my %p=(%{$self->{'check_marks'}});

  for my $m (@{$self->{'marks'}}) {
    delete($p{$m->{'student'}})
      if($self->{'check_marks'}->{$m->{'student'}}
	 == $m->{'mark'});
  }

  my @no=(keys %p);
  if(@no) {
    $self->trace("[E] Uncorrect marks: ".join(',',@no));
    exit(1);
  }

}

sub get_assoc {
  my ($self)=@_;

  my $sf=$self->{'temp_dir'}."/data/association.sqlite";

  if(-f $sf) {
    my $dbh = DBI->connect("dbi:SQLite:dbname=$sf","","");
    $self->{'association'}=$dbh->selectall_arrayref("SELECT * FROM association_association",
						    { Slice => {} });

    $self->trace("[I] Assoc:");
    for my $m (@{$self->{'association'}}) {
      $self->trace("    ".join(' ',map { $_."=".$m->{$_} } (qw/student copy auto manual/)));
    }
  }
}

sub check_assoc {
  my ($self)=@_;
  return if(!$self->{'check_assoc'});

  $self->trace("[T] Association test: "
	       .join(',',keys %{$self->{'check_assoc'}}));

  my %p=(%{$self->{'check_assoc'}});

  for my $m (@{$self->{'association'}}) {
    delete($p{$m->{'student'}})
      if($self->{'check_assoc'}->{$m->{'student'}}
	 eq $m->{'auto'});
  }

  my @no=(keys %p);
  if(@no) {
    $self->trace("[E] Uncorrect association: ".join(',',@no));
    exit(1);
  }

}

sub annote {
  my ($self)=@_;
  return if(!$self->{'annote'});

  $self->amc_command('annote',
		     '--fich-noms','%PROJ/'.$self->{'list'},
		     '--verdict',$self->{'verdict'},
		     '--verdict-question',$self->{'verdict_question'},
		     '--projet','%PROJ',
		     '--data','%DATA',
		     );

  my $nf=$self->{'temp_dir'}."/num-pdf";
  open(NUMS,">$nf");
  for (@{$self->{'annote'}}) { print NUMS "$_\n"; }
  close(NUMS);
  $self->amc_command('regroupe',
		     '--projet','%PROJ',
		     '--n-copies',$self->{'n_copies'},
		     '--sujet','%PROJ/sujet.pdf',
		     '--data','%DATA',
		     '--tex-src','%PROJ/'.$self->{'src'},
		     '--with',$self->{'tex_engine'},
		     '--modele',$self->{'model'},
		     '--id-file','%PROJ/num-pdf',
		     );

  $pdf_dir=$self->{'temp_dir'}.'/cr/corrections/pdf';
  opendir(my $dh, $pdf_dir)
    || die "can't opendir $pdf_dir: $!";
  my @pdf = grep { /\.pdf$/i } readdir($dh);
  closedir $dh;
  for my $f (@pdf) { $self->see_file($pdf_dir.'/'.$f); }

  if(@{$self->{'annote_files'}}) {
    my %p=map { $_=>1 } @pdf;
    for my $f (@{$self->{'annote_files'}}) {
      if(!$p{$f}) {
	$self->trace("[E] Annotated file $f has not been generated.");
	exit(1);
      }
    }
    $self->trace("[T] Annotated file names: ".join(', ',@{$self->{'annote_files'}}));
  }
}

sub ok {
  my ($self)=@_;
  if(@{$self->{'to_check'}}) {
    $self->trace("[?] ".(1+$#{$self->{'to_check'}})." files to check in $self->{'check_dir'}:");
    for(@{$self->{'to_check'}}) {
      $self->trace("    ".$_->[0]." ".$_->[1]);
    }
    exit(2);
  } else {
    $self->trace("[0] Test completed succesfully");
  }
}

sub defects {
  my ($self)=@_;

  my $l=AMC::Data->new($self->{'temp_dir'}."/data")->module('layout');
  $l->begin_read_transaction('test');
  my $d=$l->defects();
  $l->end_transaction('test');
  my @t=(keys %$d);
  if(@t) {
    $self->trace("[E] Layout defects: ".join(', ',@t));
  } else {
    $self->trace("[T] No layout defects");
  }
}

sub default_process {
  my ($self)=@_;

  $self->prepare;
  $self->defects;
  $self->analyse;
  $self->note;
  $self->assoc;
  $self->get_marks;
  $self->check_marks;
  $self->check_perfect;
  $self->get_assoc;
  $self->check_assoc;
  $self->annote;

  $self->ok;
}

1;

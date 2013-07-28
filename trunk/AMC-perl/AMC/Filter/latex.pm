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

package AMC::Filter::latex;

use AMC::Basic;
use AMC::Filter;

use Cwd;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Copy;
use Text::ParseWords;

@ISA=("AMC::Filter");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    bless ($self, $class);
    return $self;
}

sub filter {
  my ($self,$input_file,$output_file)=@_;

  # first of all, look in the source file header if there are some
  # AMC options

  my %options=();

  open(INPUT,$input_file);
 LINE: while(<INPUT>) {
    if(/^[%]{2}AMC:\s*([a-zA-Z0-9_-]+)\s*=\s*(.*)/) {
      $options{$1}=$2;
    }
    last LINE if(!/^%/);
  }
  close(INPUT);

  print STDERR "Options : ".join(' ',keys %options)."\n";

  # pass some of these options to AMC project configuration

  $self->set_project_option('moteur_latex_b',$options{'latex_engine'})
    if($options{'latex_engine'});

  # exec preprocess command if needed

  if($options{'preprocess_command'}) {

    # copy the file, unchanged

    copy($input_file,$output_file);

    # exec preprocess command, that may modify this file

    my ($fxa,$fxb,$f) = splitpath($output_file);
    my @cmd=quotewords('\s+',0,$options{'preprocess_command'});
    $cmd[0]="./".$cmd[0] if($cmd[0] && $cmd[0] !~ m:/:);
    push @cmd,$f;

    my $cwd=getcwd;
    chdir(catpath($fxa,$fxb,''));
    debug_and_stderr "Working directory: ".getcwd;
    debug_and_stderr "Calling preprocess command: ".join(' ',@cmd);
    if(system(@cmd)!=0) {
      debug_and_stderr("Preprocess command call failed: [$?] $!");
    }
    chdir($cwd);

  } else {
    $self->set_filter_result('unchanged',1);
  }
}

1;

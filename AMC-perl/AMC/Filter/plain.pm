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

package AMC::Filter::plain;

use AMC::Filter;
use AMC::Basic;

use Data::Dumper;

@ISA=("AMC::Filter");

use_gettext;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    $self->{'options_names'}=[qw/Title Presentation Code Lang Font
				 AnswerSheetTitle AnswerSheetPresentation
				 CompleteMulti SeparateAnswerSheet
				 DefaultScoringM DefaultScoringS
				 L-Question L-None L-Name L-Student
				 LaTeX LaTeX-Preambule LaTeX-BeginDocument
				 ShuffleQuestions Columns QuestionBlocks/];
    $self->{'options_boolean'}=[qw/LaTeX ShuffleQuestions QuestionBlocks
				   CompleteMulti SeparateAnswerSheet/];
    $self->{'groups'}=[];
    $self->{'maxhorizcode'}=6;
    $self->{'options'}={'questionblocks'=>1,'shufflequestions'=>1,
			'completemulti'=>1,
			'font'=>'Linux Libertine O',
			'defaultscoringm'=>'haut=2',
			'l-name'=>__("Name and surname"),
			'l-student'=>__("Please code your student number opposite, and write your name in the box below."),
		       };
    $self->{'qid'}=0;
    bless ($self, $class);
    return $self;
}

sub parse_bool {
  my ($b)=@_;
  if($b =~ /^\s*(no|false|0)\s*$/i) {
    return(0);
  } else {
    return($b);
  }
}

sub parse_options {
  my ($self)=@_;
  for my $n (@{$self->{'options_boolean'}}) {
    $self->{'options'}->{lc($n)}=parse_bool($self->{'options'}->{lc($n)});
  }
}

sub add_object {
  my ($container,%object)=@_;
  push @$container,{%object};
  return($container->[$#$container]);
}

sub add_group {
  my ($self,%g)=@_;
  add_object($self->{'groups'},%g);
}

sub value_cleanup {
  my ($self,$v)=@_;
  $$v =~ s/^\s+//;
  $$v =~ s/\s+$//;
}

sub read_source {
  my ($self,$input_file)=@_;

  my %opts=();
  my $follow='';
  my $group='';
  my $question='';

  my $opt_re='('.join('|',@{$self->{'options_names'}}).')';

  open(IN,"<:utf8",$input_file);
 LINE: while(<IN>) {
    chomp;

    # comments
    s/(?<!\\)\#.*//;
    s/\\\#/\#/g;

    # groups
    if(/^\s*Group:\s*(.*)/) {
      $group=$self->add_group('title'=>$1,'questions'=>[]);
      $self->value_cleanup($follow);
      $follow=\$group->{'title'};
      next LINE;
    }

    # options
    if(/^\s*$opt_re:\s*(.*)/i) {
      $self->{'options'}->{lc($1)}=$2;
      $self->value_cleanup($follow);
      $follow=\$self->{'options'}->{lc($1)};
      next LINE;
    }

    # questions
    if(/^\s*(\*{1,2})(?:\[([^]]*)\])?(?:\{([^\}]*)\})?\s*(.*)/) {
      my $star=$1;
      my $text=$4;
      my $scoring=$3;
      my @opts=split(/,+/,$2);
      my %oo=();
      for (@opts) {
	if(/^([^=]+)=(.*)/) {
	  $oo{$1}=$2;
	} else {
	  $oo{$_}=1;
	}
      }
      if(!$group) {
	$group=$self->add_group('title'=>'','questions'=>[]);
      }
      $question=add_object($group->{'questions'},
			   'multiple'=>length($star)==2,
			   'scoring'=>$scoring,
			   'text'=>$text,'answers'=>[],%oo);
      $self->value_cleanup($follow);
      $follow=\$question->{'text'};
      next LINE;
    }

    # answers
    if(/^\s*(\+|-)(?:\{([^\}]*)\})?\s*(.*)/) {
      my $a=add_object($question->{'answers'},
		       'text'=>$3,'correct'=>($1 eq '+'),
		       'scoring'=>$2);
      $self->value_cleanup($follow);
      $follow=\$a->{'text'};
      next LINE;
    }

    # text following last line
    if($follow) {
      $$follow.="\n".$_;
    }
  }
  $self->value_cleanup($follow);
  close(IN);
}

sub format_text {
  my ($self,$t)=@_;
  $t =~ s/^\s+//;
  $t =~ s/\s+$//;
  if($self->{'options'}->{'latex'}) {
  } else {
    $t =~ s/\\/\\(\\backslash\\)/g;
    $t =~ s/~/\\(\\sim\\)/g;
    $t =~ s/\*/\\(\\ast\\)/g;
    $t =~ s/([&{}\#_%])/\\\1/g;
    $t =~ s/-/-{}/g;
    $t =~ s/\$/\\textdollar{}/g;
    $t =~ s/\^/\\textasciicircum{}/g;
  }
  return($t);
}

sub scoring_string {
  my ($self,$obj,$type)=@_;
  my $s=$obj->{'scoring'}
    || $self->{'options'}->{'defaultscoring'.$type};
  return($s ? "\\scoring{$s}" : "");
}

sub format_answer {
  my ($self,$a)=@_;
  my $t='\\'.($a->{'correct'} ? 'correct' : 'wrong').'choice{'
    .$self->format_text($a->{'text'})."}";
  $t.=$self->scoring_string($a,'a');
  $t.="\n";
  return($t);
}

sub format_question {
  my ($self,$q)=@_;
  my $qid=$q->{'id'};
  $qid=sprintf("Q%03d",++$self->{'qid'}) if(!$qid);
  my $mult=($q->{'multiple'} ? 'mult' : '');
  my $ct=($q->{'horiz'} ? 'horiz' : '');

  my $t='\\begin{question'.$mult.'}{'.$qid."}";
  $t.=$self->scoring_string($q,($q->{'multiple'} ? 'm' : 's'));
  $t.="\n";
  $t.=$self->format_text($q->{'text'})."\n";
  $t.="\\begin{multicols}{".$q->{'columns'}."}\n"
    if($q->{'columns'}>1);
  $t.="\\begin{choices$ct}".($q->{'ordered'} ? "[o]" : "")."\n";
  for my $a (@{$q->{'answers'}}) {
    $t.=$self->format_answer($a);
  }
  $t.="\\end{choices$ct}\n";
  $t.="\\end{multicols}\n"
    if($q->{'columns'}>1);
  $t.="\\end{question".$mult."}\n";
  return($t);
}

sub group_name {
  my ($self,$group)=@_;
  if(!$group->{'name'}) {
    $group->{'name'}="group".chr(ord("A")+($self->{'group_number'}++));
  }
  return($group->{'name'});
}

sub file_header {
  my ($self)=@_;
  my $t='';

  my @package_options=();
  push @package_options,"bloc" if($self->{'options'}->{'questionblocks'});
  for my $on (qw/completemulti separateanswersheet/) {
    push @package_options,$on if($self->{'options'}->{$on});
  }

  push @package_options,"lang=".uc($self->{'options'}->{'lang'})
    if($self->{'options'}->{'lang'});

  my $po='';
  $po='['.join(',',@package_options).']' if(@package_options);

  $t .= "\\documentclass{article}\n";
  $t .= "\\usepackage{xltxtra}\n";
  $t .= "\\usepackage".$po."{automultiplechoice}\n";
  $t .= "\\usepackage{multicol}\n";
  $t .= "\\setmainfont[Mapping=tex-text]{".$self->{'options'}->{'font'}."}\n"
    if($self->{'options'}->{'font'});
  $t .= $self->{'options'}->{'latex-preambule'};
  $t .= "\\begin{document}\n";
  $t .= "\\AMCrandomseed{1527384}\n";

  $t .= "\\AMCtext{none}{"
    .$self->format_text($self->{'options'}->{'l-none'})."}"
    if($self->{'options'}->{'l-none'});

  $t.="\\def\\AMCbeginQuestion#1#2{\\par\\noindent{\\bf "
    .$self->{'options'}->{'l-question'}." #1} #2\\hspace{1em}}\n"
      ."\\def\\AMCformQuestion#1{\\vspace{\\AMCformVSpace}\\par{\\bf "
	.$self->{'options'}->{'l-question'}." #1 :}}"
    if($self->{'options'}->{'l-question'});

  $t .= $self->{'options'}->{'latex-begindocument'};

  return($t);
}

sub page_header {
  my ($self,$answersheet)=@_;
  my $t="";

  my $titlekey='';

  if($self->{'options'}->{'separateanswersheet'}) {
    if($answersheet) {
      if($self->{'options'}->{'code'}>0) {
	$titlekey='answersheettitle';
      }
    } else {
      $titlekey='title';
    }
  } else {
    if($self->{'options'}->{'code'}>0) {
      $titlekey='title';
    }
  }
  $t.="\\begin{center}\\bf\\large "
	.$self->format_text($self->{'options'}->{$titlekey})
	  ."\\end{center}\n\n"
	    if($titlekey && $self->{'options'}->{$titlekey});

  return($t);
}

sub student_block {
  my ($self)=@_;
  my $t='';

  if($self->{'options'}->{'code'}>0) {
    # Header layout with a code (student number)

    my $vertical=($self->{'options'}->{'code'}>$self->{'maxhorizcode'});

    $t.="{\\setlength{\\parindent}{0pt}\\hspace*{\\fill}";
    $t.=($vertical?"":"\\hbox{\\vbox{")
      ."\\AMCcode".($vertical ? "" : "H")."{student.number}{".
	$self->{'options'}->{'code'}."}".($vertical?"":"}}")."\\hspace*{\\fill}"
	  ."\\begin{minipage}".($vertical?"[b]":"")."{5.8cm}"
	    ."\$\\longleftarrow{}\$\\hspace{0pt plus 1cm}"
	      .$self->{'options'}->{'l-student'}
		."\\vspace{3ex}\n\n\\hfill\\namefield{\\fbox{\\begin{minipage}{.9\\linewidth}"
		  .$self->{'options'}->{'l-name'}
		    ."\n\n\\vspace*{.5cm}\\dotfill\n\n\\vspace*{.5cm}\\dotfill\n\\vspace*{1mm}"
		      ."\n\\end{minipage}\n}}\\hfill\\vspace{5ex}\\end{minipage}\\hspace*{\\fill}"
			."\n\n}";
    $t.="\\vspace{4mm}\n";
  } else {
    # header layout without code
    $t.= "\\begin{minipage}{.47\\linewidth}\n";
    my $titlekey=($self->{'options'}->{'separateanswersheet'}
		  ? 'answersheettitle' : 'title');
    if($self->{'options'}->{$titlekey}) {
      $t.= "\\begin{center}\\bf\\large "
	.$self->format_text($self->{'options'}->{$titlekey})
	  ."\\end{center}\n\n";
    }
    $t.= "\\end{minipage}\\hfill\n";
    $t.= "\\begin{minipage}{.47\\linewidth}\n";
    $t.= "\\namefield{\\fbox{\\begin{minipage}{.9\\linewidth}";
    $t.= $self->{'options'}->{'l-name'}."\n\n";
    $t.= "\\vspace*{.5cm}\\dotfill\\vspace*{1mm}\\end{minipage}}}\n";
    $t.= "\\end{minipage}\\vspace{4mm}\n\n";
  }
  return($t);
}

sub write_latex {
  my ($self,$output_file)=@_;

  open(OUT,">:utf8",$output_file);

  print OUT $self->file_header();

  if($self->{'options'}->{'shufflequestions'}) {
    for my $group (@{$self->{'groups'}}) {
      for my $question (@{$group->{'questions'}}) {
	print OUT "\\element{".$self->group_name($group)."}{\n";
	print OUT $self->format_question($question);
	print OUT "}\n";
      }
    }
  }

  print OUT "\\onecopy{5}{\n";

  print OUT $self->page_header(0);
  print OUT $self->student_block
    if(!$self->{'options'}->{'separateanswersheet'});

  if($self->{'options'}->{'presentation'}) {
    print OUT $self->format_text($self->{'options'}->{'presentation'})."\n\n";
  }
  print OUT "\\vspace{4mm}\\noindent\\hrule\n";

  for my $group (@{$self->{'groups'}}) {
    if($group->{'title'}) {
      print OUT "\\begin{center}\\hrule\\vspace{2mm}\\bf\\Large ".
	$self->format_text($group->{'title'})."\\vspace{1mm}\\hrule\\end{center}\n";
    }
    print OUT "\\begin{multicols}{".$self->{'options'}->{'columns'}."}\n"
      if($self->{'options'}->{'columns'}>1);

    if($self->{'options'}->{'shufflequestions'}) {
      print OUT "\\shufflegroup{".$self->group_name($group)."}\n";
      print OUT "\\insertgroup{".$self->group_name($group)."}\n";
    } else {
      for my $question (@{$group->{'questions'}}) {
	print OUT $self->format_question($question);
      }
    }

    print OUT "\\end{multicols}\n"
      if($self->{'options'}->{'columns'}>1);
  }

  if($self->{'options'}->{'separateanswersheet'}) {
    print OUT "\\AMCcleardoublepage\n";
    print OUT "\\AMCformBegin\n";

    print OUT $self->page_header(1);
    print OUT $self->student_block;
    if($self->{'options'}->{'answersheetpresentation'}) {
      print OUT $self->format_text($self->{'options'}->{'answersheetpresentation'})."\n\n";
    }
    print OUT "\\vspace{4mm}\\noindent\\hrule\n";

    print OUT "\\AMCform\n";
  }

  print OUT "}\n";
  print OUT "\\end{document}\n";
  close(OUT);
}

sub check {
  my ($self)=@_;
  if($self->{'options'}->{'font'}) {
    if(!check_fonts({'type'=>'fontconfig',
		     'family'=>[$self->{'options'}->{'font'}]})) {
      $self->error(sprintf(__("The following font does not seem to be installed on the system: <b>%s</b>."),$self->{'options'}->{'font'}));
    }
  }
}

sub filter {
  my ($self,$input_file,$output_file)=@_;
  $self->read_source($input_file);
  $self->parse_options();
  $self->check();
  $self->write_latex($output_file);
}

1;

#
# Copyright (C) 2012-2013 Alexis Bienvenue <paamc@passoire.fr>
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

use utf8;

@ISA=("AMC::Filter");

use_gettext;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();

    # list of available global options:

    $self->{'options_names'}=[qw/Title Presentation Code Lang Font
				 BoxColor PaperSize
				 AnswerSheetTitle AnswerSheetPresentation
				 AnswerSheetColumns
				 CompleteMulti SeparateAnswerSheet
				 DefaultScoringM DefaultScoringS
				 L-Question L-None L-Name L-Student
				 LaTeX LaTeX-Preambule LaTeX-BeginDocument
				 LaTeXEngine xltxtra
				 ShuffleQuestions Columns QuestionBlocks
				 Arabic ArabicFont
				 Disable
				 ManualDuplex SingleSided
				 L-OpenText
				/];

    # from these options, which ones are boolean valued?

    $self->{'options_boolean'}=[qw/LaTeX xltxtra
				   ShuffleQuestions QuestionBlocks
				   CompleteMulti SeparateAnswerSheet
				   Arabic
				   ManualDuplex SingleSided
				  /];

    # current groups list
    $self->{'groups'}=[];
    # maximum of digits that a hrizontal code can handle
    $self->{'maxhorizcode'}=6;
    # options values
    $self->{'options'}={};

    # default values for options:

    $self->{'default_options'}=
      {'latexengine'=>'xelatex','xltxtra'=>1,
       'questionblocks'=>1,'shufflequestions'=>1,
       'completemulti'=>1,
       'font'=>'Linux Libertine O',
       'arabicfont'=>'Rasheeq',
       'defaultscoringm'=>'haut=2',
       'l-name'=>__("Name and surname"),
       'l-student'=>__("Please code your student number opposite, and write your name in the box below."),
       'disable'=>'',
       'manualduplex'=>'',
       'singlesided'=>'',
      };

    # List of modules to be used when parsing (see parse_*
    # corresponding methods for implementation). Modules in the
    # Disable global option won't be used.

    $self->{'parse_modules'}=['local_latex','images','embf','text'];

    # current question number among questions for which no ID is given
    # in the source
    $self->{'qid'}=0;

    bless ($self, $class);
    return $self;
}

# arabic default localisation texts
my %l_arabic=('l-question'=>'السؤال',
	      'l-none'=>'لا توجد اجابة صحيحة',
	      );

# arabic alphabet to replace letters ABCDEF... in the boxes
my @alphabet_arabic=('أ','ب','ج','د','ه','و','ز','ح','ط','ي','ك','ل',
		     'م','ن','س','ع','ف','ص','ق','ر','ش','ت','ث','خ',
		     'ذ','ض','ظ','غ',
		     );

# parse boolean options to get 0 (from empty value, "NO" or " FALSE")
# or 1 (from other values).
sub parse_bool {
  my ($b)=@_;
  if($b =~ /^\s*(no|false|0)\s*$/i) {
    return(0);
  } else {
    return($b);
  }
}

# transforms the list of current options values to make it coherent
sub parse_options {
  my ($self)=@_;

  # boolean options are parsed to get 0 or 1
  for my $n (@{$self->{'options_boolean'}}) {
    $self->{'options'}->{lc($n)}=parse_bool($self->{'options'}->{lc($n)});
  }

  # if AR language is selected, apply default arabic localisation
  # options and set 'arabic' option to 1
  if($self->{'options'}->{'lang'} eq 'AR') {
    for (keys %l_arabic) {
      $self->{'options'}->{$_}=$l_arabic{$_}
	if(!$self->{'options'}->{$_});
    }
    $self->{'options'}->{'arabic'}=1;
  }

  # if JA language is selected, switch to 'platex+dvipdfmx' LaTeX
  # engine, remove default font and don't use xltxtra LaTeX package
  if($self->{'options'}->{'lang'} eq 'JA') {
    $self->{'default_options'}->{'latexengine'}='platex+dvipdfmx';
    $self->{'default_options'}->{'font'}='';
    $self->{'default_options'}->{'xltxtra'}='';
  }

  # set options values to default if not defined in the source
  for my $k (keys %{$self->{'default_options'}}) {
    $self->{'options'}->{$k}=$self->{'default_options'}->{$k}
      if(!defined($self->{'options'}->{$k}));
  }

  # relay LaTeX engine option to the project itself
  $self->set_project_option('moteur_latex_b',
			    $self->{'options'}->{'latexengine'});
}

# adds an object (hash) to a container (list) and returns the
# corresponding new hashref
sub add_object {
  my ($container,%object)=@_;
  push @$container,{%object};
  return($container->[$#$container]);
}

# adds a group to current state
sub add_group {
  my ($self,%g)=@_;
  add_object($self->{'groups'},%g);
}

# cleanup for text: removes leading and trailing spaces
sub value_cleanup {
  my ($self,$v)=@_;
  $$v =~ s/^\s+//;
  $$v =~ s/\s+$//;
}

# issue an AMC-TXT (syntax) error to be shown by the GUI
sub parse_error {
  my ($self,$text)=@_;
  $self->error("<i>AMC-TXT(".sprintf(__('Line %d'),$.).")</i> ".$text);
}

# check that a set of answers for a given question is coherent: one
# need more than one answer, and a simple question needs one and only
# one correct answer.
sub check_answers {
  my ($self,$question)=@_;
  if($question) {
    if($#{$question->{'answers'}}<1) {
# TRANSLATORS: Error text for AMC-TXT parsing, when opening a new question whereas the previous question has less than two choices
      $self->parse_error(__"Previous question has less than two choices");
    } else {
      my $n_correct=0;
      for my $a (@{$question->{'answers'}}) {
	$n_correct++ if($a->{'correct'});
      }
      if(!$question->{'multiple'}) {
	if($n_correct!=1) {
# TRANSLATORS: Error text for AMC-TXT parsing
	  $self->parse_error(sprintf(__("Previous question is a simple question but has %d correct choice(s)"),$n_correct));
	}
      }
    }
  }
}

# parse the whole source file to a data tree ($self->{'groups'})
sub read_source {
  my ($self,$input_file)=@_;

  my %opts=();
  my $follow=''; # variable where to add content comming from
                 # following lines
  my $group='';  # current group
  my $question=''; # current question

  # regexp that matches an option name:
  my $opt_re='('.join('|',@{$self->{'options_names'}}).')';

  open(IN,"<:utf8",$input_file);
 LINE: while(<IN>) {
    chomp;

    # removes comments
    s/^\s*\#.*//;

    # groups
    if(/^\s*Group:\s*(.*)/) {
      if($group && !@{$group->{'questions'}}) {
# TRANSLATORS: Error text for AMC-TXT parsing, when opening a new group whereas the previous group is empty
 	$self->parse_error(__"Previous group was empty");
      }
      $group=$self->add_group('title'=>$1,'questions'=>[]);
      $self->value_cleanup($follow);
      $follow=\$group->{'title'};
      $self->check_answers($question);
      $question='';
      next LINE;
    }

    # options
    if(/^\s*$opt_re:\s*(.*)/i) {
      $self->{'options'}->{lc($1)}=$2;
      $self->value_cleanup($follow);
      $follow=\$self->{'options'}->{lc($1)};
      $self->check_answers($question);
      $question='';
      next LINE;
    }

    if(/\s*([a-z0-9-]+):/i) {
# TRANSLATORS: Error text for AMC-TXT parsing, when an unknown option is given a value
      $self->parse_error(sprintf(__("Unknown option: %s"),$1));
    }

    # questions
    if(/^\s*(\*{1,2})(?:<([^>]*)>)?(?:\[([^]]*)\])?(?:\{([^\}]*)\})?\s*(.*)/) {
      $self->check_answers($question);
      my $star=$1;
      my $angles=$2;
      my @opts=split(/,+/,$3);
      my $scoring=$4;
      my $text=$5;
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
			   'open'=>$angles,
			   'scoring'=>$scoring,
			   'text'=>$text,'answers'=>[],%oo);
      $self->value_cleanup($follow);
      $follow=\$question->{'text'};
      next LINE;
    }

    # answers
    if(/^\s*(\+|-)(?:\[([^]]*)\])?(?:\{([^\}]*)\})?\s*(.*)/) {
      if($question) {
	my $sign=$1;
	my $letter=$2;
	my $scoring=$3;
	my $text=$4;
	my $a=add_object($question->{'answers'},
			 'text'=>$text,'correct'=>($sign eq '+'),
			 'letter'=>$letter,
			 'scoring'=>$scoring);
	$self->value_cleanup($follow);
	$follow=\$a->{'text'};
      } else {
# TRANSLATORS: Error text for AMC-TXT parsing when a choice is given but no question were opened
	$self->parse_error(__"Choice outside question");
      }
      next LINE;
    }

    # text following last line
    if($follow) {
      $$follow.="\n".$_;
    }
  }
  $self->value_cleanup($follow);
  $self->check_answers($question);
  close(IN);
}

# bold font LaTeX command, not used in arabic language because there
# is often no bold font arabic font.
sub bf_or {
  my($self,$replace,$bf)=@_;
  return($self->{'options'}->{'arabic'}
	 ? $replace : ($bf ? $bf : "\\bf"));
}

####################################################################
# PARSING METHODS
#
# ARGUMENT: list of components
# RETURN VALUE: list of parsed components
#
# A component is a {type=>TYPE,string=>STRING} hashref, where
# * TYPE is the component type: 'txt' for AMC-TXT text, 'latex' for
#   LaTeX code.
# * STRING is the component string
#
# When all parsing methods has been applied, the result must be a list
# of 'latex' components, that will be concatenated to get the LaTeX
# code corresponding to the source file.

# parse_images extracts an image specification (like '!image.jpg!')
# from 'txt' components, and replaces the component with 3 components:
# the preceding text, the LaTeX code that inserts the image, and the
# following text
sub parse_images {
  my ($self,@components)=@_;
  my @o=();
  for my $c (@components) {
    if($c->{'type'} eq 'txt') {
      my $s=$c->{'string'};
      while($s =~ /!(?:\{([^!\s]+)\})?(?:\[([^!\s]+)\])?([^!\s]+)!/p) {
	my $options=$1;
	my $ig_options=$2;
	my $path=$3;
	my $before=${^PREMATCH};
	my $after=${^POSTMATCH};
	push @o,{'type'=>'txt','string'=>$before};
	my $l="\\includegraphics".($ig_options ? '['.$ig_options.']' : '')
	  .'{'.$path.'}';
	if($options =~ /\bcenter\b/) {
	  $l="\\begin{center}$l\\end{center}";
	}
	push @o,{'type'=>'latex','string'=>$l};
	$s=$after;
      }
      push @o,{'type'=>'txt','string'=>$s};
    } else {
      push @o,$c;
    }
  }
  return(@o);
}

# parse_local_latex extracts a local LaTeX specification (like
# '[[$f(x)$]]') from 'txt' components
sub parse_local_latex {
  my ($self,@components)=@_;
  my @o=();
  for my $c (@components) {
    if($c->{'type'} eq 'txt') {
      my $s=$c->{'string'};
      while($s =~ /\[\[(((?!\]\]).)+)\]\]/p) {
	my $latex=$1;
	my $before=${^PREMATCH};
	my $after=${^POSTMATCH};
	push @o,{'type'=>'txt','string'=>$before};
	push @o,{'type'=>'latex','string'=>$latex};
	$s=$after;
      }
      push @o,{'type'=>'txt','string'=>$s};
    } else {
      push @o,$c;
    }
  }
  return(@o);
}

# parse_embf inserts LaTeX commands to switch to italic or bold font
# when '[_ ... _]' or '[* ... *]' constructs are used in AMC-TXT.
sub parse_embf {
  my ($self,@components)=@_;
  my @o=();
  for my $c (@components) {
    if($c->{'type'} eq 'txt') {
      my $s=$c->{'string'};
      while($s =~ /\[([_\*])(((?!\]\]).)+?)\1\]/p) {
	my $modif=$1;
	my $modif_latex;
	my $text=$2;
	my $before=${^PREMATCH};
	my $after=${^POSTMATCH};
	if($modif eq '_') {
	  $modif_latex='it';
	} else {
	  $modif_latex='bf';
	}
	push @o,{'type'=>'txt','string'=>$before};
	push @o,{'type'=>'latex','string'=>"\\text".$modif_latex."{"};
	push @o,$self->parse_embf({'type'=>'txt','string'=>$text});
	push @o,{'type'=>'latex','string'=>"}"};
	$s=$after;
      }
      push @o,{'type'=>'txt','string'=>$s};
    } else {
      push @o,$c;
    }
  }
  return(@o);
}

# parse_text transforms plain text (with no special constructs) to
# LaTeX code, escaping some characters that have special meaning for
# LaTeX.
sub parse_text {
  my ($self,@components)=@_;
  my @o=();
  for my $c (@components) {
    if($c->{'type'} eq 'txt') {
      my $s=$c->{'string'};
      if(! $self->{'options'}->{'latex'}) {
	$s =~ s/\\/\\(\\backslash\\)/g;
	$s =~ s/~/\\(\\sim\\)/g;
	$s =~ s/\*/\\(\\ast\\)/g;
	$s =~ s/([&{}\#_%])/\\\1/g;
	$s =~ s/-/-{}/g;
	$s =~ s/\$/\\textdollar{}/g;
	$s =~ s/\^/\\textasciicircum{}/g;
      }
      push @o,{'type'=>'latex','string'=>$s};
    } else {
      push @o,$c;
    }
  }
  return(@o);
}

# parse_all calls all requested parse_* methods in turn (when they are
# not disabled by the Disable global option).
sub parse_all {
  my ($self,@components)=@_;
  for my $m (@{$self->{'parse_modules'}}) {
    my $mm='parse_'.$m;
    @components=$self->$mm(@components)
      if($self->{'options'}->{'disable'} !~ /\b$m\b/);
  }
  return(@components);
}

# Checks that the resulting components list has only 'latex' components
sub check_latex {
  my ($self,@components)=@_;
  my @s=();
  for my $c (@components) {
    if($c->{'type'} ne 'latex') {
      debug_and_stderr "ERR(FILTER): non-latex resulting component (".
	$c->{'type'}."): ".$c->{'string'};
    }
    push @s,$c->{'string'};
  }
  return(@s);
}

# converts AMC-TXT string to a LaTeX string: make a single 'txt'
# component, apply parse_all and check_latex, and then concatenates
# the components
sub format_text {
  my ($self,$t)=@_;
  $t =~ s/^\s+//;
  $t =~ s/\s+$//;

  return(join('',$self->check_latex($self->parse_all({'type'=>'txt','string'=>$t}))));
}

# builds the LaTeX scoring command from the question's scoring
# strategy (or the default scoring strategy)
sub scoring_string {
  my ($self,$obj,$type)=@_;
  my $s=$obj->{'scoring'}
    || $self->{'options'}->{'defaultscoring'.$type};
  return($s ? "\\scoring{$s}" : "");
}

# builds the LaTeX code for an answer: \correctchoice or \wrongchoice,
# followed by the scoring command
sub format_answer {
  my ($self,$a)=@_;
  my $t='\\'.($a->{'correct'} ? 'correct' : 'wrong').'choice';
  $t.='['.$a->{letter}.']' if($a->{letter} ne '');
  $t.='{'
    .$self->format_text($a->{'text'})."}";
  $t.=$self->scoring_string($a,'a');
  $t.="\n";
  return($t);
}

# builds the LaTeX code for the question (including answers)
sub format_question {
  my ($self,$q)=@_;
  my $qid=$q->{'id'};
  $qid=sprintf("Q%03d",++$self->{'qid'}) if(!$qid);
  my $mult=($q->{'multiple'} ? 'mult' : '');
  my $ct=($q->{'horiz'} ? 'horiz' : '');

  my $t='';
  $t.="\\begin{arab}"
    if($self->{'options'}->{'arabic'} && $self->bidi_year()<2011);
  $t.='\\begin{question'.$mult.'}{'.$qid."}";
  $t.=$self->scoring_string($q,($q->{'multiple'} ? 'm' : 's'));
  $t.="\n";
  $t.=$self->format_text($q->{'text'})."\n";
  if($q->{open} ne '') {
    $t.="\\AMCOpen{".$q->{open}."}{";
  } else {
    $t.="\\begin{multicols}{".$q->{'columns'}."}\n"
      if($q->{'columns'}>1);
    $t.="\\begin{choices$ct}".($q->{'ordered'} ? "[o]" : "")."\n";
  }
  for my $a (@{$q->{'answers'}}) {
    $t.=$self->format_answer($a);
  }
  if($q->{open} ne '') {
    $t.="}\n";
  } else {
    $t.="\\end{choices$ct}\n";
    $t.="\\end{multicols}\n"
      if($q->{'columns'}>1);
  }
  $t.="\\end{question".$mult."}";
  $t.="\\end{arab}"
    if($self->{'options'}->{'arabic'} && $self->bidi_year()<2011);
  $t.="\n";
  return($t);
}

# returns the group name, defaulting to 'groupX' (where X is a letter
# beginnig at A)
sub group_name {
  my ($self,$group)=@_;
  if(!$group->{'name'}) {
    $group->{'name'}="group".chr(ord("A")+($self->{'group_number'}++));
  }
  return($group->{'name'});
}

# gets the Year for the version of installed bidi.sty. This will be
# used to adapt the LaTeX code to version before or after 2011
sub bidi_year {
  my ($self)=@_;
  if(!$self->{'bidiyear'}) {
    my $f=find_latex_file("bidi.sty");
    if(-f $f) {
      open(BIDI,$f);
    BIDLIG: while(<BIDI>) {
	if(/\\bididate\{([0-9]+)\//) {
	  $self->{'bidiyear'}=$1;
	  last BIDLIG;
	}
      }
      close(BIDI);
    }
  }
  return($self->{'bidiyear'});
}

# builds and returns the LaTeX header
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

  if($self->{'options'}->{'arabic'}) {
    $t.="% bidi YEAR ".$self->bidi_year()."\n";
  }

  $t .= "\\documentclass{article}\n";
  $t .= "\\usepackage{bidi}\n"
    if($self->{'options'}->{'arabic'} && $self->bidi_year()<2011);
  $t .= "\\usepackage{xltxtra}\n" if($self->{'options'}->{'xltxtra'});
  $t .= "\\usepackage{arabxetex}\n"
    if($self->{'options'}->{'arabic'} && $self->bidi_year()<2011);
  $t .= "\\usepackage".$po."{automultiplechoice}\n";
  $t .= "\\usepackage{"
    .($self->{'options'}->{'arabic'} && $self->bidi_year()<2011
      ? "fmultico" : "multicol")."}\n";
  $t .= "\\setmainfont{".$self->{'options'}->{'font'}."}\n"
    if($self->{'options'}->{'font'});
  $t .= "\\newfontfamily{\\arabicfont}[Script=Arabic,Scale=1]{".$self->{'options'}->{'arabicfont'}."}\n"
    if($self->{'options'}->{'arabicfont'} && $self->{'options'}->{'arabic'});
  $t .= "\\geometry{paper=".lc($self->{'options'}->{'papersize'})."paper}\n"
    if($self->{'options'}->{'papersize'});
  $t .= $self->{'options'}->{'latex-preambule'};
  $t .= "\\usepackage{arabxetex}\n"
    if($self->{'options'}->{'arabic'} && $self->bidi_year()>=2011);
  $t .= "\\begin{document}\n";
  $t .= "\\AMCrandomseed{1527384}\n";
  if($self->{'options'}->{'boxcolor'}) {
    if($self->{'options'}->{'boxcolor'}
       =~ /^\\definecolor\{amcboxcolor\}/) {
      $t .= $self->{'options'}->{'boxcolor'};
    } elsif($self->{'options'}->{'boxcolor'}
       =~ /^\#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2})$/i) {
      $t .= "\\definecolor{amcboxcolor}{rgb}{"
	.sprintf("%0.2f,%0.2f,%0.2f",map { hex($_)/256.0 } ($1,$2,$3))."}\n";
    } else {
      $t .= "\\definecolor{amcboxcolor}{named}{"
	.$self->{'options'}->{'boxcolor'}."}\n";
    }
    $t .= "\\AMCboxColor{amcboxcolor}\n";
  }
  $t .= "\\AMCtext{none}{"
    .$self->format_text($self->{'options'}->{'l-none'})."}\n"
    if($self->{'options'}->{'l-none'});
  $t .= "\\def\\AMCotextGoto{\\par ".$self->format_text($self->{'options'}->{'l-opentext'})."}"
    if($self->{'options'}->{'l-opentext'});

  $t.="\\def\\AMCbeginQuestion#1#2{\\par\\noindent{"
    .$self->bf_or("\\Large")." "
      .$self->{'options'}->{'l-question'}." #1} #2\\hspace{1em}}\n"
	."\\def\\AMCformQuestion#1{\\vspace{\\AMCformVSpace}\\par{"
	  .$self->bf_or("\\Large")." "
	    .$self->{'options'}->{'l-question'}." #1 :}}\n"
	      if($self->{'options'}->{'l-question'});
  if($self->{'options'}->{'arabic'}) {
    $t.="\\def\\AMCchoiceLabel#1{\\csname ArabicAlphabet\\Alph{#1}\\endcsname}\n";
    my $letter="A";
    for my $c (@alphabet_arabic) {
      $t.="\\def\\ArabicAlphabet$letter"."{$c}\n";
      $letter++;
    }
  }
  $t .= $self->{'options'}->{'latex-begindocument'};

  return($t);
}

# Builds and returns the question sheet head (or the answer sheet head
# if $answersheet is true)
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
  if($titlekey && $self->{'options'}->{$titlekey}) {
    $t.="\\begin{center}".$self->bf_or("\\Large","\\bf\\large")." "
      .$self->format_text($self->{'options'}->{$titlekey})
	."\\end{center}";
    $t.="\n\n";
  }
  return($t);
}

# Builds and returns the name field LaTeX code
sub full_namefield {
  my ($self,$n_ligs)=@_;
  my $t='';
  $t.="\\namefield{\\fbox{";
  $t.="\\begin{minipage}{.9\\linewidth}"
    .$self->{'options'}->{'l-name'}
	.("\n\n\\vspace*{.5cm}\\dotfill" x $n_ligs)
	  ."\n\\vspace*{1mm}"
	    ."\n\\end{minipage}";
  $t.="\n}}";
  return($t);
}

# Builds and returns the student identification block LaTeX code (with
# name field and AMCcode if requested)
sub student_block {
  my ($self)=@_;
  my $t='';

  if($self->{'options'}->{'code'}>0) {
    # Header layout with a code (student number)

    my $vertical=($self->{'options'}->{'code'}>$self->{'maxhorizcode'});

    $t.="{\\setlength{\\parindent}{0pt}\\hspace*{\\fill}";
    $t.=($vertical?"":"\\hbox{\\vbox{");
    $t.= "\\LR{" if($self->{'options'}->{'arabic'} && $vertical);
    $t.="\\AMCcode".($vertical ? "" : "H")."{student.number}{".
	$self->{'options'}->{'code'}."}";
    $t.= "}" if($self->{'options'}->{'arabic'} && $vertical);
    $t.=($vertical?"":"}}")."\\hspace*{\\fill}"
      ."\\begin{minipage}".($vertical?"[b]":"")."{5.8cm}"
	."\$\\long".($self->{'options'}->{'arabic'} ? "right" : "left")
	  ."arrow{}\$\\hspace{0pt plus 1cm}"
	    .$self->{'options'}->{'l-student'}
	      ."\\vspace{3ex}\n\n\\hfill"
		.$self->full_namefield(2)
		  ."\\hfill\\vspace{5ex}\\end{minipage}\\hspace*{\\fill}"
		    ."\n\n}";
    $t.="\\vspace{4mm}\n";
  } else {
    # header layout without code
    $t.= "\\begin{minipage}{.47\\linewidth}\n";
    my $titlekey=($self->{'options'}->{'separateanswersheet'}
		  ? 'answersheettitle' : 'title');
    if($self->{'options'}->{$titlekey}) {
      $t.= "\\begin{center}".$self->bf_or("\\Large","\\bf\\large")." "
	.$self->format_text($self->{'options'}->{$titlekey})
	  ."\\end{center}\n\n";
    }
    $t.= "\\end{minipage}\\hfill\n";
    $t.= "\\begin{minipage}{.47\\linewidth}\n";
    $t.= $self->full_namefield(1);
    $t.= "\\end{minipage}\\vspace{4mm}\n\n";
  }
  return($t);
}

# writes the LaTeX output file
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

  print OUT "\\begin{arab}" if($self->{'options'}->{'arabic'});
  print OUT $self->page_header(0);
  print OUT $self->student_block
    if(!$self->{'options'}->{'separateanswersheet'});

  if($self->{'options'}->{'presentation'}) {
    print OUT $self->format_text($self->{'options'}->{'presentation'})."\n\n";
  }
  print OUT "\\vspace{4mm}\\noindent\\hrule\n";
  print OUT "\\end{arab}" if($self->{'options'}->{'arabic'});
  print OUT "\n\n";

  for my $group (@{$self->{'groups'}}) {
    if($group->{'title'}) {
      print OUT "\\begin{center}\\hrule\\vspace{2mm}"
	.$self->bf_or("\\Large","\\bf\\Large")." ".
	  $self->format_text($group->{'title'})."\\vspace{1mm}\\hrule\\end{center}\n\n";
    }
    print OUT "\\begin{arab}"
      if($self->{'options'}->{'arabic'} && $self->bidi_year()>=2011);
    if($self->{'options'}->{'columns'}>1) {
      print OUT "\\begin{multicols}{".$self->{'options'}->{'columns'}."}\n";
    } else {
      print OUT "\\vspace{2ex}\n\n";
    }

    if($self->{'options'}->{'shufflequestions'}) {
      print OUT "\\shufflegroup{".$self->group_name($group)."}\n";
      print OUT "\\insertgroup{".$self->group_name($group)."}\n";
    } else {
      for my $question (@{$group->{'questions'}}) {
	print OUT $self->format_question($question);
      }
    }

    if($self->{'options'}->{'columns'}>1) {
      print OUT "\\end{multicols}\n";
    }
    print OUT "\\end{arab}"
      if($self->{'options'}->{'arabic'} && $self->bidi_year()>=2011);
  }

  if($self->{'options'}->{'separateanswersheet'}) {
    if($self->{'options'}->{'singlesided'}) {
      print OUT "\n\\clearpage\n\n";
    } else {
      print OUT "\n\\AMCcleardoublepage\n\n";
    }
    print OUT "\\AMCformBegin\n";

    print OUT "\\begin{arab}" if($self->{'options'}->{'arabic'});
    print OUT $self->page_header(1);
    print OUT $self->student_block;
    if($self->{'options'}->{'answersheetpresentation'}) {
      print OUT $self->format_text($self->{'options'}->{'answersheetpresentation'})."\n\n";
    }
    print OUT "\\vspace{4mm}\\noindent\\hrule\n";
    print OUT "\\end{arab}" if($self->{'options'}->{'arabic'});
    print OUT "\n\n";

    print OUT "\\begin{arab}" if($self->{'options'}->{'arabic'});
    print OUT "\\begin{multicols}{".$self->{'options'}->{'answersheetcolumns'}."}\n"
      if($self->{'options'}->{'answersheetcolumns'}>1);
    print OUT "\\AMCform\n";
    print OUT "\\end{multicols}\n"
      if($self->{'options'}->{'answersheetcolumns'}>1);
    print OUT "\\end{arab}" if($self->{'options'}->{'arabic'});
  }

  print OUT "\\AMCcleardoublepage\n" if($self->{'options'}->{'manualduplex'});

  print OUT "}\n";
  print OUT "\\end{document}\n";
  close(OUT);
}

# Checks that the requested prerequisites (in fact, fonts) are
# installed on the system
sub check {
  my ($self)=@_;
  my @cf=('font');
  my @mf=();
  push @cf,'arabicfont' if($self->{'options'}->{'arabic'});
  for my $k (@cf) {
    if($self->{'options'}->{'font'}) {
      if(!check_fonts({'type'=>'fontconfig',
		       'family'=>[$self->{'options'}->{$k}]})) {
	push @mf,$self->{'options'}->{$k}
      }
    }
  }
  $self->error(sprintf(__("The following fonts does not seem to be installed on the system: <b>%s</b>."),join(', ',@mf))) if(@mf);
}

# Whole filter processing
sub filter {
  my ($self,$input_file,$output_file)=@_;
  $self->read_source($input_file);
  $self->parse_options();
  $self->check();
  $self->write_latex($output_file);
}

1;

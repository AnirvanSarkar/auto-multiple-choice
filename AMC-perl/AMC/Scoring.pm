# -*- perl -*-
#
# Copyright (C) 2011 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Scoring;

use XML::Simple;
use AMC::Basic;

sub new {
    my (%o)=(@_);

    my $self={'onerror'=>'stderr',
	      'seuil'=>0,
	      'data'=>'',
	      '_capture'=>'',
	      '_scoring'=>'',
	  };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    bless $self;

    if($self->{'data'}) {
      $self->{'_capture'}=$self->{'data'}->module('capture');
      $self->{'_scoring'}=$self->{'data'}->module('scoring');
    }

    return($self);
}

sub error {
    my ($t)=@_;
    debug $t;
    if($self->{'onerror'} =~ /\bstderr\b/i) {
	print STDERR "$t\n";
    }
    if($self->{'onerror'} =~ /\bdie\b/i) {
	die $t;
    }
}

###################
# derived methods #
###################

sub ticked {
  my ($self,$student,$copy,$question,$answer)=@_;
  return($self->{'_capture'}
	 ->ticked($student,$copy,$question,$answer,$self->{'seuil'}));
}

# tells if the answer given by the student is the correct one (ticked
# if it has to be, or not ticked if it has not to be).
sub answer_is_correct {
    my ($self,$student,$copy,$question,$answer)=@_;
    return($self->ticked($student,$copy,$question,$answer)
	   == $self->{'_scoring'}->correct_answer($student,$question,$answer));
}

#################
# score methods #
#################

# reads a scoring strategy string, and returns a hash with parameters
# values.
#
# $s is the scoring strategy string
#
# $defaut is the default scoring strategy hash reference, as returned
# by degroupe for the default scoring strategy.
#
# $vars is a hash reference with variables values to be substituted in
# the scoring parameters values.
sub degroupe {
    my ($self,$s,$defaut,$vars)=(@_);
    my %r=(%$defaut);
    for my $i (split(/,+/,$s)) {
	$i =~ s/^\s+//;
	$i =~ s/\s+$//;
	if($i =~ /^([^=]+)=([-+*\/0-9a-zA-Z\.\(\)?:|&=<>!\s]+)$/) {
	    $r{$1}=$2;
	} else {
	    $self->error("Marking scale syntax error: $i within $s") if($i);
	}
    }
    # substitute variables values, and then evaluate the value.
    for my $k (keys %r) {
	my $v=$r{$k};
	for my $vv (keys %$vars) {
	    $v=~ s/\b$vv\b/$vars->{$vv}/g;
	}
	$self->error("Syntax error (unknown variable): $v") if($v =~ /[a-z]/i);
	my $calc=eval($v);
	$self->error("Syntax error (operation) : $v") if(!defined($calc));
	debug "Evaluation : $r{$k} => $calc" if($r{$k} ne $calc);
	$r{$k}=$calc;
    }
    #
    return(%r);
}

# returns a given parameter from the main scoring strategy, or
# $default if not present.
sub main_tag {
    my ($self,$tag,$default,$etu)=@_;
    my $r=$default;
    my %m=($self->degroupe($self->{'_scoring'}->main_strategy(0),{},{}));
    $r=$m{$tag} if(defined($m{$tag}));
    if($etu) {
	%m=($self->degroupe($self->{'_scoring'}->main_strategy($etu),{},{}));
	$r=$m{$tag} if(defined($m{$tag}));
    }
    return($r);
}

# returns the score for a particular student-sheet/question, applying
# the given scoring strategy.
sub score_question {
    my ($self,$etu,$copy,$question,$correct)=@_;

    my $xx='';
    my $raison='';
    my $vars={'NB'=>0,'NM'=>0,'NBC'=>0,'NMC'=>0};
    my %b_q=();

    my $n_ok=0;
    my $n_coche=0;
    my $id_coche=-1;
    my $n_tous=0;

    my @rep=$self->{'_scoring'}->answers($etu,$question);
    my @rep_pleine=grep { $_ !=0 } @rep; # on enleve " aucune "

    debug("SCORE : $etu:$copy/$question - "
	  .$self->{'_scoring'}->question_strategy($etu,$question));

    for my $a (@rep) {
	my $c=$self->{'_scoring'}->correct_answer($etu,$question,$a);
	my $t=($correct ? $c :
	       $self->ticked($etu,$copy,$question,$a));

	debug("[$etu:$copy/$question:$a] $t ($c)\n");

	$n_ok+=($c == $t ? 1 : 0);
	$n_coche+=$t;
	$id_coche=$a if($t);
	$n_tous++;

	if($a!=0) {
	    my $bn=($c ? 'B' : 'M');
	    my $co=($t ? 'C' : '');
	    $vars->{'N'.$bn}++;
	    $vars->{'N'.$bn.$co}++ if($co);
	}
    }

    # question wide variables
    $vars->{'N'}=(1+$#rep_pleine);
    $vars->{'IMULT'}=($self->{'_scoring'}->multiple($etu,$question) ? 1 : 0);
    $vars->{'IS'}=1-$vars->{'IMULT'};

    if($vars->{'IMULT'}) {
	# MULTIPLE QUESTION

	$xx=0;

	%b_q=$self->degroupe($self->{'_scoring'}->default_strategy(QUESTION_MULT)
		      .",".$self->{'_scoring'}->question_strategy($etu,$question),
		      {'e'=>0,'b'=>1,'m'=>0,'v'=>0,'d'=>0},
		      $vars);

	if($b_q{'haut'}) {
	    $b_q{'d'}=$b_q{'haut'}-(1+$#rep_pleine);
	    $b_q{'p'}=0 if(!defined($b_q{'p'}));
	    debug "Q=$question REPS=".join(',',@rep)." BQ{".join(" ",map { "$_=$b_q{$_}" } (keys %b_q) )."}";
	} elsif($b_q{'mz'}) {
	    $b_q{'d'}=$b_q{'mz'};
	    $b_q{'p'}=0 if(!defined($b_q{'p'}));
	    $b_q{'b'}=0;$b_q{'m'}=-( abs($b_q{'mz'})+abs($b_q{'p'})+1 );
	} else {
	    $b_q{'p'}=-100 if(!defined($b_q{'p'}));
	}

	if($n_coche !=1 && (!$correct) && $self->ticked($etu,$question,0)) {
	    # incompatible answers: the student has ticked one
	    # plain answer AND the answer "none of the
	    # above"...
	    $xx=$b_q{'e'};
	    $raison='E';
	} elsif($n_coche==0) {
	    # no ticked boxes
	    $xx=$b_q{'v'};
	    $raison='V';
	} else {
	    # standard case: adds the 'b' or 'm' scores for each answer
	    for my $a (@rep) {
		if($a != 0) {
		    $code=($correct ||
			   $self->answer_is_correct($etu,$copy,$question,$a)
			   ? "b" : "m");
		    my %b_qspec=$self->degroupe($self->{'_scoring'}
						->answer_strategy($etu,$question,$a),
						\%b_q,$vars);
		    debug("Delta($a|$code)=$b_qspec{$code}");
		    $xx+=$b_qspec{$code};
		}
	    }
	}

	# adds the 'd' shift value
	$xx+=$b_q{'d'} if($raison !~ /^[VE]/i);
	
	# applies the 'p' floor value
	if($xx<$b_q{'p'} && $raison !~ /^[VE]/i) {
	    $xx=$b_q{'p'};
	    $raison='P';
	}
    } else {
	# SIMPLE QUESTION
	
	%b_q=$self->degroupe($self->{'_scoring'}->default_strategy(QUESTION_SIMPLE)
			     .",".$self->{'_scoring'}->question_strategy($etu,$question),
			     {'e'=>0,'b'=>1,'m'=>0,'v'=>0,'auto'=>-1},
			     $vars);
	
	if(defined($b_q{'mz'})) {
	    $b_q{'b'}=$b_q{'mz'};
	    $b_q{'m'}=$b_q{'d'} if(defined($b_q{'d'}));
	}
	
	if($n_coche==0) {
	    # no ticked boxes
	    $xx=$b_q{'v'};
	    $raison='V';
	} elsif($n_coche>1) {
	    # incompatible answers: there are more than one
	    # ticked boxes
	    $xx=$b_q{'e'};
	    $raison='E';
	} else {
	    # standard case
	    $sb=$self->{'_scoring'}->answer_strategy($etu,$question,$id_coche);
	    if($sb ne '') {
		# some value is given as a score for the
		# ticked answer
		$xx=$sb; 
	    } else {
		# take into account the scoring strategy for
		# the question: 'auto', or 'b'/'m'
		$xx=($b_q{'auto'}>-1
		     ? $id_coche+$b_q{'auto'}-1
		     : ($n_ok==$n_tous ? $b_q{'b'} : $b_q{'m'}));
	    }
	}
    }

    return($xx,$raison,\%b_q);
}

# returns the score associated with correct answers for a question.
sub score_correct_question {
    my ($self,$etu,$question)=@_;
    return($self->score_question($etu,0,$question,1));
}

# returns the maximum score for a question: MAX parameter value, or,
# if not present, the score_correct_question value.
sub score_max_question {
   my ($self,$etu,$question)=@_;
   my ($x,$raison,$b)=($self->score_question($etu,0,$question,1));
   if(defined($b->{'MAX'})) {
       return($b->{'MAX'},'M',$b);
   } else {
       return($x,$raison,$b);
   }
} 

1;

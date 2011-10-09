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

    my $self={'file'=>'',
	      'tick'=>{},
	      'onerror'=>'stderr',
	      'ticked_info'=>{},
	  };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    bless $self;
    
    $self->read() if($self->{'file'});

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

############################
# base data access methods #
############################

# Reads the XML file (usualy bareme.xml) dscribing the scoring
# strategy.
sub read {
    my ($self,$f)=@_;
    $f=$self->{'file'} if($self->{'file'} && !$f);
    $self->{'bar'}=XMLin($f,ForceArray => 1,KeyAttr=> [ 'id' ]);
}

# writes scoring strategy (but not ticked boxes data).
sub write {
    my ($self,$f)=@_;
    $f=$self->{'file'} if($self->{'file'} && !$f);

    debug "Writing scoring strategy to $f ...";

    if(open(BAR,">",$f)) {
	print BAR XMLout($self->{'bar'},
			 'RootName'=>'bareme',
			 KeyAttr=> [ 'id' ],
	    );
	close(BAR);
    } else {
	$self->error("Unable to write to $f: $!");
    }
}

# returns the scoring file version.
sub version {
    my ($self)=@_;
    return($self->{'bar'}->{'version'});
}

# returns the main (outside questions) scoring strategy string
sub main {
    my ($self,$etu)=@_;
    if($etu) {
	return($self->{'bar'}->{'etudiant'}->{$etu}->{'main'});
    } else {
	return($self->{'bar'}->{'main'});
    }
}

# returns the main (outside questions) variable value
sub main_var {
    my ($self,$name)=@_;
    return($self->{'bar'}->{$name});
}

# returns the list of all students sheets IDs
sub etus {
    my ($self)=@_;
    return( sort { $a <=> $b } (keys %{$self->{'bar'}->{'etudiant'}}) );
}

# returns the list of questions numbers for a particular student sheet ID
sub questions {
    my ($self,$etu)=@_;
    return(sort { $a <=> $b }
	   (keys %{$self->{'bar'}->{'etudiant'}->{$etu}->{'question'}}) );
}

# returns the question title (first argument of \begin{question}: this
# in fact is an ID) from the question number.
sub question_title {
    my ($self,$etu,$question)=@_;
    return($self->{'bar'}->{'etudiant'}->{$etu}->{'question'}->{$question}->{'titre'});
}

# tells is the question is a multiple question.
sub question_is_multiple {
    my ($self,$etu,$question)=@_;
    return($self->{'bar'}->{'etudiant'}->{$etu}->{'question'}->{$question}->{'multiple'});
}

# tells if the question is an indicative question.
sub question_is_indicative {
    my ($self,$etu,$question)=@_;
    return($self->{'bar'}->{'etudiant'}->{$etu}->{'question'}->{$question}->{'indicative'});
}

# returns the scoring strategy string for the question (\scoring used
# inside question but outside answers environment).
sub question_scoring {
    my ($self,$etu,$question)=@_;
    return($self->{'bar'}->{'etudiant'}->{$etu}->{'question'}->{$question}->{'bareme'});
}

# returns the scoring strategy string for a particular answer(\scoring
# used inside answers environment).
sub answer_scoring {
    my ($self,$etu,$question,$answer)=@_;
    return($self->{'bar'}->{'etudiant'}->{$etu}->{'question'}->{$question}->{'reponse'}->{$answer}->{'bareme'});
}

# returns an ordered list of answers numbers. Answer number 0, placed
# at the end, corresponds to the answer "None of the above", when
# present.
sub answers_ids {
    my ($self,$etu,$question)=@_;
    return(sort { ($a==0 || $b==0 ? $b <=> $a : $a <=> $b) }
	   (keys %{$self->{'bar'}->{'etudiant'}->{$etu}->{'question'}->{$question}->{'reponse'}}) );
}

# tells if the answer is correct (does it have to be ticked?).
sub correct_answer {
    my ($self,$etu,$question,$answer)=@_;
    return($self->{'bar'}->{'etudiant'}->{$etu}->{'question'}->{$question}->{'reponse'}->{$answer}->{'bonne'});
}

# tells if the answer is correct, setting this value for ALL sheets
sub postcorrect_answer {
    my ($self,$question,$answer,$value)=@_;
    for my $etu ($self->etus) {
	$self->{'bar'}->{'etudiant'}->{$etu}->{'question'}->{$question}->{'reponse'}->{$answer}->{'bonne'}=$value;
    }
}

# returns a list telling, for each answer (in the same order as
# returned by answers_id), if it has to be ticked.
sub correct_answers {
    my ($self,$etu,$question)=@_;
    my @a=$self->answers_ids($etu,$question);
    return(map { $self->{'bar'}->{'etudiant'}->{$etu}->{'question'}->{$question}->{'reponse'}->{$_}->{'bonne'} } (@a));
}

# The following method allows to access the 'ticked' state of
# answers. This has to be called before computing scores, as this is
# not known from the bareme.xml file.

# $self->ticked_answer($etu,$question,$answer) returns a value telling
# if this answer is ticked.

# $self->ticked_answer($etu,$question,$answer,$t) sets the 'ticked'
# state for an answer.
sub ticked_answer {
    my ($self,$etu,$question,$answer,$t)=@_;
    if(defined($t)) {
	$self->{'tick'}->{$etu}={} if(!defined($self->{'tick'}->{$etu}));
	$self->{'tick'}->{$etu}->{$question}={} 
	if(!defined($self->{'tick'}->{$etu}->{$question}));
	$self->{'tick'}->{$etu}->{$question}->{$answer}={} 
	if(!defined($self->{'tick'}->{$etu}->{$question}->{$answer}));
    }
    my $a=$self->{'tick'}->{$etu}->{$question}->{$answer};
    if(defined($t)) {
	$a->{'ticked'}=$t;
	$self->{'ticked_info'}->{$etu}++;
    }
    return($a->{'ticked'});
}

###################
# derived methods #
###################

# tells if we have 'ticked or not' data for some answer for this
# student sheet.
sub ticked_info {
    my ($self,$etu)=@_;
    return(defined($self->{'ticked_info'}->{$etu}) ?
	   $self->{'ticked_info'}->{$etu} : 0);
}

# tells if the answer given by the student is the correct one (ticked
# if it has to be, or not ticked if it has not to be).
sub answer_is_correct {
    my ($self,$etu,$question,$answer)=@_;
    return($self->ticked_answer($etu,$question,$answer) 
	   == $self->correct_answer($etu,$question,$answer));
}

# sets/gets 'ticked' states for all answers of a question. When
# setting (using the optional $t argument), $t is an array reference.
sub ticked_question {
    my ($self,$etu,$question,$t)=@_;
    my @a=$self->answers_ids($etu,$question);
    my @r=();
    if($t && ($#{$t} != $#a)) {
	debug "Error: ticked_question bad length : ".(1+$#{$t})." != ".(1+$#a);
	return();
    }
    for my $i (0..$#a) {
	my @par=($etu,$question,$a[$i]);
	push @par,$t->[$i] if(defined($t));
	push @r,$self->ticked_answer(@par);
    }
    return(@r);
}

# returns a semicolon separated list of 'ticked' states for the
# answers of a question.
sub ticked_list {
    my ($self,$etu,$question)=@_;
    return(join(";",$self->ticked_question($etu,$question)));
}

# takes correct answers from ticked answers of sheet id $postcorrect
sub postcorrect {
    my ($self,$postcorrect)=@_;
    debug "PostCorrection: from E $postcorrect";
    for my $q ($self->questions($postcorrect)) {
	if(! $self->question_is_indicative($postcorrect,$q)) {
	    for my $a ($self->answers_ids($postcorrect,$q)) {
		my $value=$self->ticked_answer($postcorrect,$q,$a);
		debug "PostCorrection: Q $q A $a -> $value";
		$self->postcorrect_answer($q,$a,$value);
	    }
	}
    }
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
    my %m=($self->degroupe($self->main,{},{}));
    $r=$m{$tag} if(defined($m{$tag}));
    if($etu) {
	%m=($self->degroupe($self->main($etu),{},{}));
	$r=$m{$tag} if(defined($m{$tag}));
    }
    return($r);
}

# returns the score for a particular student-sheet/question, applying
# the given scoring strategy.
sub score_question {
    my ($self,$etu,$question,$correct)=@_;
    
    my $xx='';
    my $raison='';
    my $vars={'NB'=>0,'NM'=>0,'NBC'=>0,'NMC'=>0};
    my %b_q=();
	    
    my $n_ok=0;
    my $n_coche=0;
    my $id_coche=-1;
    my $n_tous=0;
	    
    my @rep=$self->answers_ids($etu,$question);
    my @rep_pleine=grep { $_ !=0 } @rep; # on enleve " aucune "

    debug("SCORE : $etu/$question - "
	  .$self->question_scoring($etu,$question));
    
    for my $a (@rep) {
	my $c=$self->correct_answer($etu,$question,$a);
	my $t=($correct ? $c : $self->ticked_answer($etu,$question,$a));

	debug("[$etu:$question:$a] $t ($c)\n");

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
    $vars->{'IMULT'}=($self->question_is_multiple($etu,$question) ? 1 : 0);
    $vars->{'IS'}=1-$vars->{'IMULT'};
    
    if($self->question_is_multiple($etu,$question)) {
	# MULTIPLE QUESTION
	
	$xx=0;
	
	%b_q=$self->degroupe($self->question_scoring('defaut','M')
		      .",".$self->question_scoring($etu,$question),
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
	
	if($n_coche !=1 && (!$correct) && $self->ticked_answer($etu,$question,0)) {
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
			   $self->answer_is_correct($etu,$question,$a)
			   ? "b" : "m");
		    my %b_qspec=$self->degroupe($self->answer_scoring($etu,$question,$a),
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
	
	%b_q=$self->degroupe($self->question_scoring('defaut','S')
			     .",".$self->question_scoring($etu,$question),
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
	    $sb=$self->answer_scoring($etu,$question,$id_coche);
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
    return($self->score_question($etu,$question,1));
}

# returns the maximum score for a question: MAX parameter value, or,
# if not present, the score_correct_question value.
sub score_max_question {
   my ($self,$etu,$question)=@_;
   my ($x,$raison,$b)=($self->score_question($etu,$question,1));
   if(defined($b->{'MAX'})) {
       return($b->{'MAX'},'M',$b);
   } else {
       return($x,$raison,$b);
   }
} 

1;

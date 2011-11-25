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

package AMC::DataModule::scoring;

# AMC scoring management.

# This module is used to store (in a SQLite database) and handle all
# data concerning data scoring (scoring strategies, scores and marks).

# TABLES:
#

use Exporter qw(import);

use constant {
  QUESTION_SIMPLE => 1,
  QUESTION_MULT => 2,
};

our @EXPORT_OK = qw(QUESTION_SIMPLE QUESTION_MULT);
our %EXPORT_TAGS = ( 'question' => [ qw/QUESTION_SIMPLE QUESTION_MULT/ ],
		   );

use AMC::Basic;
use AMC::DataModule;

use XML::Simple;

@ISA=("AMC::DataModule");

sub version_upgrade {
    my ($self,$old_version)=@_;
    if($old_version==0) {

	# Upgrading from version 0 (empty database) to version 1 :
	# creates all the tables.

	debug "Creating scoring tables...";
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("title")
		      ." (question INTEGER, title TEXT)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("default")
		      ." (type INTEGER, strategy TEXT)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("main")
		      ." (student INTEGER, strategy TEXT)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("question")
		      ." (student INTEGER, question INTEGER, type INTEGER, indicative INTEGER DEFAULT 0, strategy TEXT, PRIMARY KEY (student,question))");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("answer")
		      ." (student INTEGER, question INTEGER, answer INTEGER, correct INTEGER, strategy INTEGER, PRIMARY KEY (student,question,answer))");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("alias")
		      ." (student INTEGER,see INTEGER)");

	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("score")
		      ." (student INTEGER, copy INTEGER, question INTEGER, score REAL, why TEXT, max REAL, PRIMARY KEY (student,copy,question))");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("mark")
		      ." (student INTEGER, copy INTEGER, total REAL, max REAL, mark REAL, PRIMARY KEY (student,copy))");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("code")
		      ." (student INTEGER, copy INTEGER, code TEXT, value TEXT, PRIMARY KEY (student,copy,code))");

	$self->statement('NEWdefault')->execute(QUESTION_SIMPLE,"");
	$self->statement('NEWdefault')->execute(QUESTION_MULT,"");

	$self->populate_from_xml;

	return(1);
    }
    return('');
}

# populate_from_xml read the old format XML files (if any) and inserts
# them in the new SQLite database

sub populate_from_xml {
  my ($self)=@_;
  my $scoring_file=$self->{'data'}->directory;
  $scoring_file =~ s:/[^/]+/?$:/bareme.xml:;
  return if(!-f $scoring_file);

  my $xml=XMLin($scoring_file,ForceArray => 1,KeyAttr=> [ 'id' ]);

  $self->main_strategy(-1,$xml->{'main'});
  for my $student (keys %{$xml->{'etudiant'}}) {
    my $s=$xml->{'etudiant'}->{$student};
    if($student eq 'defaut') {
      $self->default_strategy(QUESTION_SIMPLE,
			      $s->{'question'}->{'S'}->{'bareme'});
      $self->default_strategy(QUESTION_MULT,
			      $s->{'question'}->{'M'}->{'bareme'});
    } elsif($student =~ /^[0-9]+$/) {
      $self->main_strategy($student,$s->{'main'});
      for my $question (keys %{$s->{'question'}}) {
	if($question =~ /^[0-9]+$/) {
	  my $q=$s->{'question'}->{$question};
	  $self->question_title($question,$q->{'titre'});
	  $self->statement('NEWQuestion')
	    ->execute($student,$question,
		      ($q->{'multiple'} ? QUESTION_MULT : QUESTION_SIMPLE),
		      $q->{'indicative'},$q->{'bareme'});

	  for my $answer (keys %{$q->{'reponse'}}) {
	    my $a=$q->{'reponse'}->{$answer};
	    $self->statement('NEWAnswer')
	      ->execute($student,$question,$answer,
			$a->{'bonne'},$a->{'bareme'});
	  }
	} else {
	  debug "Unknown question id: <$question>";
	}
      }
    } else {
      debug "Unknown student id: <$student>";
    }
  }
}

# defines all the SQL statements that will be used

sub define_statements {
  my ($self)=@_;
  $self->{'statements'}=
    {
     'NEWdefault'=>{'sql'=>"INSERT INTO ".$self->table("default")
		    ." (type,strategy) VALUES (?,?)"},
     'getDefault'=>{'sql'=>"SELECT strategy FROM ".$self->table("default")
		    ." WHERE type=?"},
     'setDefault'=>{'sql'=>"UPDATE ".$self->table("default")
		    ." SET strategy=? WHERE type=?"},
     'noDefault'=>{'sql'=>"UPDATE ".$self->table("default")
		    ." SET strategy=''"},
     'NEWMain'=>{'sql'=>"INSERT INTO ".$self->table("main")
		  ." (student,strategy) VALUES (?,?)"},
     'getMain'=>{'sql'=>"SELECT strategy FROM ".$self->table("main")
		  ." WHERE student=?"},
     'setMain'=>{'sql'=>"UPDATE ".$self->table("main")
		  ." SET strategy=? WHERE student=?"},
     'NEWTitle'=>{'sql'=>"INSERT INTO ".$self->table("title")
		  ." (question,title) VALUES (?,?)"},
     'getTitle'=>{'sql'=>"SELECT title FROM ".$self->table("title")
		  ." WHERE question=?"},
     'setTitle'=>{'sql'=>"UPDATE ".$self->table("title")
		  ." SET title=? WHERE question=?"},
     'NEWQuestion'=>{'sql'=>"INSERT INTO ".$self->table("question")
		     ." (student,question,type,indicative,strategy)"
		     ." VALUES (?,?,?,?,?)"},
     'NEWAnswer'=>{'sql'=>"INSERT INTO ".$self->table("answer")
		   ." (student,question,answer,correct,strategy)"
		   ." VALUES (?,?,?,?,?)"},
     'setAnswerStrat'=>{'sql'=>"UPDATE ".$self->table("answer")
		       ." SET strategy=? WHERE student=? AND question=? AND answer=?"},
     'NEWAlias'=>{'sql'=>"INSERT INTO ".$self->table("alias")
		  ." (student,see) VALUES (?,?)"},
     'getAlias'=>{'sql'=>"SELECT see FROM ".$self->table("alias")
		  ." WHERE student=?"},
     'postCorrect'=>{'sql'=>""},

     'NEWScore'=>{'sql'=>"INSERT INTO ".$self->table("score")
		  ." (student,copy,question,score,max,why)"
		  ." VALUES (?,?,?,?,?,?)"},
     'NEWMark'=>{'sql'=>"INSERT INTO ".$self->table("mark")
		  ." (student,copy,total,max,mark)"
		  ." VALUES (?,?,?,?,?)"},
     'NEWCode'=>{'sql'=>"INSERT INTO ".$self->table("code")
		  ." (student,copy,code,value)"
		  ." VALUES (?,?,?,?)"},

     'codes'=>{'sql'=>"SELECT code from ".$self->table("code")
	       ." GROUP BY code ORDER BY code"},
     'qStrat'=>{'sql'=>"SELECT strategy FROM ".$self->table("question")
		." WHERE student=? AND question=?"},
     'aStrat'=>{'sql'=>"SELECT strategy FROM ".$self->table("answer")
		." WHERE student=? AND question=? AND answer=?"},
     'answers'=>{'sql'=>"SELECT answer FROM ".$self->table("answer")
		 ." WHERE student=? AND question=?"
		." ORDER BY answer"},
     'questions'=>{'sql'=>"SELECT question FROM ".$self->table("question")
		   ." WHERE student=?"},
     'correct'=>{'sql'=>"SELECT correct FROM ".$self->table("answer")
		 ." WHERE student=? AND question=? AND answer=?"},
     'multiple'=>{'sql'=>"SELECT type FROM ".$self->table("question")
		 ." WHERE student=? AND question=?"},
     'indicative'=>{'sql'=>"SELECT indicative FROM ".$self->table("question")
		    ." WHERE student=? AND question=?"},

     'avgMark'=>{'sql'=>"SELECT AVG(mark) FROM ".$self->table("mark")},
    };
}

sub default_strategy {
  my ($self,$type,$strategy)=@_;
  if(defined($strategy)) {
    $self->statement('setDefault')->execute($strategy,$type);
  } else {
    return($self->sql_single($self->statement('getDefault'),$type));
  }
}

sub main_strategy {
  my ($self,$student,$strategy)=@_;
  $student=-1 if($student<=0);
  if(defined($strategy)) {
    if(defined($self->main_strategy($student))) {
      $self->statement('setMain')->execute($strategy,$student);
    } else {
      $self->statement('NEWMain')->execute($student,$strategy);
    }
  } else {
    return($self->sql_single($self->statement('getMain'),$student));
  }
}

sub question_strategy {
  my ($self,$student,$question)=@_;
  return($self->sql_single($self->statement('qStrat'),$student,$question));
}

sub answer_strategy {
  my ($self,$student,$question,$answer)=@_;
  return($self->sql_single($self->statement('aStrat'),$student,$question,$answer));
}

# answers($student,$question) returns an ordered list of answers
# numbers. Answer number 0, placed at the end, corresponds to the
# answer "None of the above", when present.

sub answers {
  my ($self,$student,$question)=@_;
  my @a=$self->sql_list($self->statement('answers'),$student,$question);
  if($a[0]==0) {
    shift @a;
    push @a,0;
  }
  return(@a);
}

sub correct_answer {
  my ($self,$student,$question,$answer)=@_;
  return($self->sql_single($self->statement('correct'),
			   $student,$question,$answer));
}

sub multiple {
  my ($self,$student,$question)=@_;
  return($self->sql_single($self->statement('multiple'),
			   $student,$question) == QUESTION_MULT);
}

sub indicative {
  my ($self,$student,$question)=@_;
  return($self->sql_single($self->statement('indicative'),
			   $student,$question));
}

sub question_title {
  my ($self,$question,$title)=@_;
  if(defined($title)) {
    if(defined($self->question_title($question))) {
      $self->statement('setTitle')->execute($title,$question);
    } else {
      $self->statement('NEWTitle')->execute($question,$title);
    }
  } else {
    return($self->sql_single($self->statement('getTitle'),$question));
  }
}

sub clear_strategy {
  my ($self)=@_;
  $self->clear_variables;
  $self->statement('noDefault')->execute;
  for my $t (qw/title main question answer alias/) {
    $self->sql_do("DELETE FROM ".$self->table($t));
  }
}

sub clear_score {
  my ($self)=@_;
  for my $t (qw/score mark code/) {
    $self->sql_do("DELETE FROM ".$self->table($t));
  }
}

sub set_answer_strategy {
  my ($self,$student,$question,$answer,$strategy)=@_;
  $self->statement('setAnswerStrat')->execute($strategy,$student,$question,$answer);
}

sub replicate {
  my ($self,$see,$student)=@_;
  $self->statement('NEWAlias')->execute($student,$see);
}

sub unalias {
  my ($self,$student)=@_;
  my $s;
  do {
    $s=$self->sql_single($self->statement('getAlias'),$student);
  } while($s);
  return($student);
}

sub postcorrect {
  my ($self,$student)=@_;
  $self->statement('postCorrect')->execute($student);
}

sub new_score {
  my ($self,$student,$copy,$question,$score,$score_max,$why)=@_;
  $self->statement('NEWScore')
    ->execute($student,$copy,$question,$score,$score_max,$why);
}

sub new_mark {
  my ($self,$student,$copy,$total,$max,$mark)=@_;
  $self->statement('NEWMark')
    ->execute($student,$copy,$total,$max,$mark);
}

sub new_code {
  my ($self,$student,$copy,$code,$value)=@_;
  $self->statement('NEWCode')
    ->execute($student,$copy,$code,$value);
}

sub student_questions {
  my ($self,$student)=@_;
  return($self->sql_list($self->statement('questions'),
			 $student));
}

sub average_mark {
  my ($self)=@_;
  return($self->sql_single($self->statement('avgMark')));
}

sub codes {
  my ($self)=@_;
  return($self->sql_list($self->statement('codes')));
}

1;

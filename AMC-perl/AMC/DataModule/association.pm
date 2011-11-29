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

package AMC::DataModule::association;

# AMC associations management.

# This module is used to store (in a SQLite database) and handle all
# data concerning associations between completed answer sheets and
# students (from the students list).

# TABLES:
#

use AMC::Basic;
use AMC::DataModule;

use IO::File;
use XML::Simple;

@ISA=("AMC::DataModule");

sub version_upgrade {
    my ($self,$old_version)=@_;
    if($old_version==0) {

	# Upgrading from version 0 (empty database) to version 1 :
	# creates all the tables.

	debug "Creating scoring tables...";
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("association")
		      ." (student INTEGER, copy INTEGER, manual TEXT, auto TEXT, PRIMARY KEY (student,copy))");

	$self->populate_from_xml;

	return(1);
    }
    return('');
}

# populate_from_xml read the old format XML file (if any) and insert
# it in the new SQLite database

sub populate_from_xml {
  my ($self)=@_;
  my $assoc_file=$self->{'data'}->directory;
  $assoc_file =~ s:/[^/]+/?$:/association.xml:;
  return if(!-f $assoc_file);

  my $i=IO::File->new($assoc_file,"<:encoding(utf-8)");
  my $a=XMLin($i,'ForceArray'=>1,'KeyAttr'=>['id']);
  $i->close();

  $self->variable('key_in_list',$a->{'liste_key'});
  $self->variable('code',$a->{'notes_id'});

  for my $student (keys %{$a->{'copie'}}) {
    my $s=$a->{'copie'}->{$student};
    $self->statement('NEWAssoc')
      ->execute($student,0,$s->{'manuel'},$s->{'auto'});
  }
}

# defines all the SQL statements that will be used

sub define_statements {
  my ($self)=@_;
  my $at=$self->table("association");
  $self->{'statements'}=
    {
     'NEWAssoc'=>{'sql'=>"INSERT INTO $at"
		  ." (student,copy,manual,auto) VALUES (?,?,?,?)"},
     'insert'=>{'sql'=>"INSERT OR IGNORE INTO $at"
		." (student,copy,manual,auto) VALUES (?,?,?,?)"},
     'getManual'=>{'sql'=>"SELECT manual FROM $at"
		   ." WHERE student=? AND copy=?"},
     'getAuto'=>{'sql'=>"SELECT auto FROM $at"
		 ." WHERE student=? AND copy=?"},
     'setManual'=>{'sql'=>"UPDATE $at"
		   ." SET manual=? WHERE student=? AND copy=?"},
     'setAuto'=>{'sql'=>"UPDATE $at"
		 ." SET auto=? WHERE student=? AND copy=?"},
     'getReal'=>{'sql'=>"SELECT CASE"
		 ." WHEN manual IS NOT NULL THEN manual"
		 ." ELSE auto END"
		 ." FROM $at"
		 ." WHERE student=? AND copy=?"},
     'realCount'=>{'sql'=>"SELECT COUNT(*) FROM ( SELECT CASE"
		   ." WHEN manual IS NOT NULL THEN manual"
		   ." ELSE auto END AS real"
		   ." FROM $at"
		   ." ) WHERE real=?"},
     'realBack'=>{'sql'=>"SELECT student,copy FROM ( SELECT CASE"
		  ." WHEN manual != '' THEN manual"
		  ." ELSE auto END AS real, student, copy"
		  ." FROM $at"
		  ." ) WHERE real=?"},
     'counts'=>{'sql'=>"SELECT COUNT(auto),COUNT(manual),COUNT(manual and auto)"
		." FROM $at"},
     'clearAuto'=>{'sql'=>"UPDATE $at SET auto=NULL"},
     'findManual'=>{'sql'=>"SELECT student,copy FROM $at WHERE manual=?"},
     'unlinkA'=>{'sql'=>"UPDATE $at SET auto=NULL"
		 ." WHERE manual=? AND auto IS NULL"},
     'unlinkB'=>{'sql'=>"UPDATE $at SET auto='NONE'"
		 ." WHERE manual=? AND auto IS NOT NULL"},
    };
}

sub get_manual {
  my ($self,$student,$copy)=@_;
  return($self->sql_single($self->statement('getManual'),
			   $student,$copy));
}

sub get_auto {
  my ($self,$student,$copy)=@_;
  return($self->sql_single($self->statement('getAuto'),
			   $student,$copy));
}

sub get_real {
  my ($self,$student,$copy)=@_;
  return($self->sql_single($self->statement('getReal'),
			   $student,$copy));
}

sub set_manual {
  my ($self,$student,$copy,$manual)=@_;
  my $n=$self->statement('insert')->execute($student,$copy,$manual,undef);
  if($n<=0) {
    $self->statement('setManual')->execute($manual,$student,$copy);
  }
}

sub set_auto {
  my ($self,$student,$copy,$auto)=@_;
  my $n=$self->statement('insert')->execute($student,$copy,undef,$auto);
  if($n<=0) {
    $self->statement('setAuto')->execute($auto,$student,$copy);
  }
}

sub counts {
  my ($self)=@_;
  my $sth=$self->statement('counts');
  $sth->execute;
  return(@{$sth->fetchrow_arrayref});
}

sub clear {
  my ($self)=@_;
  $self->sql_do("DELETE FROM ".$self->table('association'));
}

sub clear_auto {
  my ($self)=@_;
  $self->statement('clearAuto')->execute;
}

sub check_keys {
  my ($self,$key_in_list,$code)=@_;
  if($self->variable('key_in_list') ne $key_in_list
     || ($code ne '---' && $self->variable('code') ne $code)) {
    debug "Association variable mismatch: clearing database";
    $self->clear;
    $self->variable('key_in_list',$key_in_list);
    $self->variable('code',$code);
  }
}

sub real_back {
  my ($self,$code)=@_;
  return($self->sql_single($self->statement('realBack'),$code));
}

sub state {
  my ($self,$student,$copy)=@_;
  my $r=$self->get_real($student,$copy);
  if(!defined($r) || !$r || $r eq 'NONE') {
    return(0);
  } else {
    my $nb=$self->sql_single($self->statement('realCount'),$r);
    return($nb==1 ? 1 : 2);
  }
}

sub delete_target {
  my ($self,$code)=@_;
  my @r=$self->dbh->selectall_arrayref($self->statement('findManual'),{},$code);
  $self->statement('unlinkA')->execute($code);
  $self->statement('unlinkB')->execute($code);
  return(@r);
}

1;

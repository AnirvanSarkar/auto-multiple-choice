# -*- perl -*-
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

package AMC::DataModule::report;

# AMC reports data management.

# This module is used to store (in a SQLite database) and handle some
# data concerning reports.

# TABLES:
#
# student stores some student reports filenames.
#
# * type is the kind of report (see REPORT_* constants).
#
# * file is the filename of the report.
#
# * student
# * copy identify the student sheet.
#
# * timestamp is the time when the report were generated.

use Exporter qw(import);

use constant {
  REPORT_ANNOTATED_PDF=>1,
};

our @EXPORT_OK = qw(REPORT_ANNOTATED_PDF);
our %EXPORT_TAGS = ( 'const' => [ qw/REPORT_ANNOTATED_PDF/ ],
		   );

use AMC::Basic;
use AMC::DataModule;

@ISA=("AMC::DataModule");

sub version_current {
  return(1);
}

sub version_upgrade {
    my ($self,$old_version)=@_;
    if($old_version==0) {

	# Upgrading from version 0 (empty database) to version 1 :
	# creates all the tables.

	debug "Creating capture tables...";
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("student")
		      ." (type INTEGER, file TEXT, student INTEGER, copy INTEGER DEFAULT 0, timestamp INTEGER, PRIMARY KEY (type,student,copy))");

	return(1);
    }
    return('');
}

# defines all the SQL statements that will be used

sub define_statements {
  my ($self)=@_;
  my $t_student=$self->table("student");
  $self->{'statements'}=
    {
     'setStudent'=>{'sql'=>"INSERT OR REPLACE INTO $t_student"
		    ." (file,timestamp,type,student,copy)"
		    ." VALUES (?,?,?,?,?)"},
     'getStudent'=>{'sql'=>"SELECT file FROM $t_student"
		    ." WHERE type=? AND student=? AND copy=?"},
     'deleteType'=>{'sql'=>"DELETE FROM $t_student"
		    ." WHERE type=?"},
    };
}

# delete_student_type($type) deletes all records for specified type.

sub delete_student_type {
  my ($self,$type)=@_;
  $self->statement('delete')->execute($type);
}

# set_student_type($type,$student,$copy,$file,$timestamp) creates a
# new record for a stduent report file, or replace data if this report
# is already in the table.

sub set_student_report {
  my ($self,$type,$student,$copy,$file,$timestamp)=@_;
  $timestamp=time() if($timestamp eq 'now');
  $self->statement('setStudent')
    ->execute($file,$timestamp,$type,$student,$copy);
}

# get_student_report($type,$student,$copy) returns the filename of a
# given report.

sub get_student_report {
  my ($self,$type,$student,$copy)=@_;
  return($self->sql_single($self->statement('getStudent'),
			   $type,$student,$copy));
}

1;

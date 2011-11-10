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

package AMC::Data;

use Module::Load;
use AMC::Basic;
use DBI;

sub new {
    my ($class,$dir,%oo)=@_;

    my $self={
	'directory'=>$dir,
	'timeout'=>300000,
	'dbh'=>DBI->connect("dbi:SQLite:",undef,undef,
			    {AutoCommit => 0,
			     RaiseError => 0,
			    }),
	'modules'=>{},
	'on_error'=>'die',
    };

    for(keys %oo) {
	$self->{$_}=$oo{$_} if(exists($self->{$_}));
    }

    $self->{'dbh'}->sqlite_busy_timeout($self->{'timeout'});
    
    bless($self,$class);
    return $self;
}

sub directory {
    my ($self)=@_;
    return($self->{'directory'});
}

sub dbh {
    my ($self)=@_;
    return($self->{'dbh'});
}

sub begin_transaction {
    my ($self)=@_;
    $self->sql_do("BEGIN IMMEDIATE");
}

sub begin_read_transaction {
    my ($self)=@_;
    $self->sql_do("BEGIN");
}

sub end_transaction {
    my ($self)=@_;
    $self->sql_do("COMMIT");
}

sub sql_quote {
    my ($self,$string)=@_;
    return $self->{'dbh'}->quote($string);
}

sub sql_do {
    my ($self,$sql,@bind)=@_;
    if(!$self->{'dbh'}->do($sql,{},@bind)) {
	debug_and_stderr("SQL ERROR: ".$self->{'dbh'}->errstr);
	debug_and_stderr("WHILE EXECUTING: ".$sql);
	die "*SQL*" if($self->{'on_error'} =~ /die/);
    }
}

sub sql_tables {
    my ($self,$tables)=@_;
    return($self->{'dbh'}->tables('%','%',$tables));
}

sub require_module {
    my ($self,$module)=@_;
    if(!$self->{'modules'}->{$module}) {
	my $filename=$self->{'directory'}."/".$module.".sqlite";
	if(! -f $filename) {
	    debug("Creating unexistant database file for module $module...");
	}

	$self->{'dbh'}->{AutoCommit}=1;
	$self->sql_do("ATTACH DATABASE ".$self->sql_quote($filename)." AS $module");
	$self->{'dbh'}->{AutoCommit}=0;

	load("AMC::DataModule::$module");
	$self->{'modules'}->{$module}="AMC::DataModule::$module"->new($self);

	debug "Module $module loaded.";
    }
}

sub module {
    my ($self,$module)=@_;
    $self->require_module($module);
    return($self->{'modules'}->{$module});
}

1;

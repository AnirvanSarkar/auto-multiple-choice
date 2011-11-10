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

package AMC::DataModule;

use AMC::Basic;

sub new {
    my ($class,$data,%oo)=@_;

    my $self={
	'data'=>$data,
	'name'=>'',
	'statements'=>{},
    };

    for(keys %oo) {
	$self->{$_}=$oo{$_} if(exists($self->{$_}));
    }

    if(!$self->{'name'} && $class =~ /::([^:]+)$/) {
	$self->{'name'}=$1;
    }	

    bless($self,$class);

    $self->define_statements;
    $self->version_check;

    return $self;
}

sub dbh {
    my ($self)=@_;
    return $self->{'data'}->dbh;
}

sub table {
    my ($self,$table_subname)=@_;
    return($self->{'name'}.".".$self->{'name'}."_".$table_subname);
}

sub sql_quote {
    my ($self,$string)=@_;
    return($self->{'data'}->sql_quote($string));
}

sub sql_do {
    my ($self,$sql)=@_;
    $self->{'data'}->sql_do($sql);
}

sub sql_single {
    my ($self,$sql,@bind)=@_;
    my $x=$self->dbh->selectrow_arrayref($sql,{},@bind);
    if($x) {
	return($x->[0]);
    } else {
	return(undef);
    }
}

sub sql_single_embedded {
    my ($self,$sql,@bind)=@_;
    $self->begin_read_transaction;
    my $r=$self->sql_single($sql,@bind);
    $self->end_transaction;
    return($r);
}

sub sql_list {
    my ($self,$sql,@bind)=@_;
    my $x=$self->dbh->selectcol_arrayref($sql,{},@bind);
    if($x) {
	return(@$x);
    } else {
	return(undef);
    }
}

sub sql_list_embedded {
    my ($self,$sql,@bind)=@_;
    $self->begin_read_transaction;
    my @r=$self->sql_list($sql,@bind);
    $self->end_transaction;
    return(@r);
}

sub begin_transaction {
    my ($self)=@_;
    $self->{'data'}->begin_transaction;
}

sub begin_read_transaction {
    my ($self)=@_;
    $self->{'data'}->begin_read_transaction;
}

sub end_transaction {
    my ($self)=@_;
    $self->{'data'}->end_transaction;
}

sub variable {
    my ($self,$name,$value)=@_;
    my $vt=$self->table("variables");
    my $x=$self->dbh->selectrow_arrayref("SELECT value FROM $vt WHERE name=".
					 $self->sql_quote($name));
    if(defined($value)) {
	if($x) {
	    $self->sql_do("UPDATE $vt SET value=".
			  $self->sql_quote($value)." WHERE name=".
			  $self->sql_quote($name));
	} else {
	    $self->sql_do("INSERT INTO $vt VALUES (".
			  $self->sql_quote($name).",".
			  $self->sql_quote($value).")");
	}
    } else {
	return($x->[0]);
    }
}

sub version_check {
    my ($self)=@_;
    my $vt=$self->table("variables");

    $self->begin_transaction;
    my @vt=$self->{'data'}->sql_tables("%".$self->{'name'}."_variables");
    if(!@vt) {
	$self->sql_do("CREATE TABLE $vt (name TEXT, value TEXT)");
	$self->variable('version','0');
    }
    $self->end_transaction;

    $self->begin_transaction;
    my $vu=$self->variable('version');
    my $v;
    do {
	$v=$vu;
	$vu=$self->version_upgrade($v);
	debug("Updated data module ".$self->{'name'}." from version $v to $vu");
    } while($vu);
    $self->variable('version',$v);
    $self->end_transaction;

    debug("Database version: $v");
}

sub define_statements {
}

sub statement {
    my ($self,$sid)=@_;
    my $s=$self->{'statements'}->{$sid};
    if($s->{'s'}) {
	return($s->{'s'});
    } elsif($s->{'sql'}) {
	$s->{'s'}=$self->dbh->prepare($s->{'sql'});
	return($s->{'s'});
    } else {
	debug_and_stderr("Undefined SQL statement: $sid");
    }
}

sub version_upgrade {
    my ($self,$old_version)=@_;
    return('');
}

1;

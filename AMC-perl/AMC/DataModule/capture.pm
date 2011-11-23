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

package AMC::DataModule::capture;

# AMC capture data management.

# This module is used to store (in a SQLite database) and handle all
# data concerning data capture (automatic and manual).

# TABLES:
#

use Exporter qw(import);

use constant {
  ZONE_FRAME=>1,
  ZONE_NAME=>2,
  ZONE_DIGIT=>3,
  ZONE_BOX=>4,

  POSITION_BOX=>1,
  POSITION_MEASURE=>2,
};

our @EXPORT_OK = qw(ZONE_FRAME ZONE_NAME ZONE_DIGIT ZONE_BOX
		  POSITION_BOX POSITION_MEASURE);
our %EXPORT_TAGS = ( 'zone' => [ qw/ZONE_FRAME ZONE_NAME ZONE_DIGIT ZONE_BOX/ ],
		     'position'=> [ qw/POSITION_BOX POSITION_MEASURE/ ],
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

	debug "Creating capture tables...";
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("page")
		      ." (src TEXT, student INTEGER, page INTEGER, copy INTEGER DEFAULT 0, timestamp_auto INTEGER DEFAULT 0, timestamp_manual INTEGER DEFAULT 0, a REAL, b REAL, c REAL, d REAL, e REAL, f REAL, mse REAL, annotated TEXT, timestamp_annotate INTEGER, PRIMARY KEY (student,page,copy))");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("zone")
		      ." (zoneid INTEGER PRIMARY KEY, student INTEGER, page INTEGER, copy INTEGER, type INTEGER, id_a INTEGER, id_b INTEGER, total INTEGER DEFAULT -1, black INTEGER DEFAULT -1, manual REAL DEFAULT -1, image TEXT)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("position")
		      ." (zoneid INTEGER, corner INTEGER, x REAL, y REAL, type INTEGER)");
	$self->populate_from_xml;

	return(1);
    }
    return('');
}

# Internal function used by populate_from_xml to put all corners
# coordinates of a particular box

sub populate_position {
  my ($self,$xml,$zoneid,$type)=@_;

  return if(!$xml);

  for my $corner (keys %$xml) {
    $self->statement('NEWPosition')
      ->execute($zoneid,
		$corner,
		$xml->{$corner}->{'x'},
		$xml->{$corner}->{'y'},
		$type);
  }
}

# populate_from_xml read the old format XML files (if any) and inserts
# them in the new SQLite database

sub populate_from_xml {
  my ($self)=@_;
  my $cr=$self->{'data'}->directory;
  $cr =~ s/\/[^\/]+\/?$/\/cr/;
  return if(!-d $cr);

  my $cordir="$cr/corrections/jpg/";

  opendir(DIR, $cr) || die "can't opendir $cr: $!";
  @xmls = grep { /\.xml$/ && -s "$cr/".$_ } readdir(DIR);
  closedir DIR;

 XML: for my $f (@xmls) {
    my $anx=XMLin("$cr/".$f,
		  ForceArray => ["analyse","chiffre","case","id"],
		  KeepRoot=>1,
		  KeyAttr=> [ 'id' ]);
    next XML if(!$anx->{'analyse'});
  ID: for my $id (keys %{$anx->{'analyse'}}) {
      my $an=$anx->{'analyse'}->{$id};
      my @ep=get_ep($id);
      my %oo;

      my @st=stat("$cr/".$f);
      $oo{'timestamp'}=$st[9];

      if ($an->{'manuel'}) {
	# This is a XML description of a manual data capture: no
	# position information, only ticked-or-not for all
	# boxes
	$self->set_page_manual(@ep,0,$oo{'timestamp'});

	for my $c (keys %{$an->{'case'}}) {
	  my $case=$an->{'case'}->{$c};
	  $self->set_zone_manual(@ep,0,ZONE_BOX,
				 $case->{'question'},$case->{'reponse'},
				 $case->{'r'});
	}
      } else {
	# This is a XML description of an automatic data
	# capture: contains full information about darkness and
	# positions of the oxes
	$oo{'mse'}=$an->{'transformation'}->{'mse'};
	for my $k (qw/a b c d e f/) {
	  $oo{$k}=$an->{'transformation'}->{'parametres'}->{$k};
	}

	$self->set_page_auto($an->{'src'},@ep,0,
			     map { $oo{$_} } (qw/timestamp a b c d e f mse/));

	if($an->{'cadre'}) {
	  my $zoneid=$self->get_zoneid(@ep,0,ZONE_FRAME,0,0,1);
	  $self->populate_position($an->{'cadre'}->{'coin'},
				   $zoneid,POSITION_BOX);
	}
	if($an->{'nom'}) {
	  my $zoneid=$self->get_zoneid(@ep,0,ZONE_NAME,0,0,1);
	  $self->populate_position($an->{'nom'}->{'coin'},
				   $zoneid,POSITION_BOX);
	}

	for my $c (keys %{$an->{'case'}}) {
	  my $case=$an->{'case'}->{$c};
	  my $zoneid=$self->get_zoneid(@ep,0,ZONE_BOX,
				       $case->{'question'},$case->{'reponse'},1);
	  $self->statement('setZoneAuto')
	    ->execute($case->{'pixels'},$case->{'pixelsnoirs'},'',
		      $zoneid);

	  $self->populate_position($case->{'coin'},$zoneid,POSITION_BOX);
	  $self->populate_position($an->{'casetest'}->{$c}->{'coin'},
				   $zoneid,POSITION_MEASURE);
	}

	# Look if annotated scan is present...
	my $af="page-".id2idf($id).".jpg";
	if(-f $cordir.$af) {
	  my @sta=stat($cordir.$af);
	  $self->set_annotated(@ep,0,$af,$sta[9]);
	}
      }
    }
  }
}

# defines all the SQL statements that will be used

sub define_statements {
  my ($self)=@_;
  $self->{'statements'}=
    {
     'NEWPageAuto'=>{'sql'=>"INSERT INTO ".$self->table("page")
		     ." (src,student,page,copy,timestamp_auto,a,b,c,d,e,f,mse)"
		     ." VALUES (?,?,?,?,?,?,?,?,?,?,?,?)"},
     'NEWPageManual'=>{'sql'=>"INSERT INTO ".$self->table("page")
		       ." (student,page,copy,timestamp_manual)"
		       ." VALUES (?,?,?,?)"},
     'SetPageAuto'=>{'sql'=>"UPDATE ".$self->table("page")
		     ." SET src=?, timestamp_auto=?, a=?, b=?, c=?, d=?, e=?, f=?, mse=?"
		     ." WHERE student=? AND page=? AND copy=?"},
     'SetPageManual'=>{'sql'=>"UPDATE ".$self->table("page")
		       ." SET timestamp_manual=?"
		       ." WHERE student=? AND page=? AND copy=?"},
     'NEWZone'=>{'sql'=>"INSERT INTO ".$self->table("zone")
		 ." (student,page,copy,type,id_a,id_b)"
		 ." VALUES (?,?,?,?,?,?)"},
     'getZoneID'=>{'sql'=>"SELECT zoneid FROM ".$self->table("zone")
		   ." WHERE student=? AND page=? AND copy=? AND type=? AND id_a=? AND id_b=?"},
     'zonesCount'=>{'sql'=>"SELECT COUNT(*) FROM ".$self->table("zone")
		    ." WHERE student=? AND page=? AND copy=? AND type=?"},
     'zone'=>{'sql'=>"SELECT COUNT(*) FROM ".$self->table("zone")
	      ." WHERE student=? AND page=? AND copy=? AND type=?"
	      ." AND id_a=? AND id_b=?"},
     'NEWPosition'=>{'sql'=>"INSERT INTO ".$self->table("position")
		     ." (zoneid,corner,x,y,type)"
		     ." VALUES (?,?,?,?,?)"},
     'setPosition'=>{'sql'=>"UPDATE ".$self->table("position")
		     ." SET x=?, y=? WHERE zoneid=? AND corner=? AND type=?"},
     'getPage'=>{'sql'=>"SELECT * FROM ".$self->table("page")
		 ." WHERE student=? AND page=? AND copy=?"},
     'setZoneManual'=>{'sql'=>"UPDATE ".$self->table("zone")
		       ." SET manual=? WHERE zoneid=?"},
     'setZoneAuto'=>{'sql'=>"UPDATE ".$self->table("zone")
		     ." SET total=?, black=?, image=? WHERE zoneid=?"},
     'nPages'=>{'sql'=>"SELECT COUNT(*) FROM ".$self->table("page")
		." WHERE timestamp_auto>0 OR timestamp_manual>0"},
     'nPagesAuto'=>{'sql'=>"SELECT COUNT(*) FROM ".$self->table("page")
		   ." WHERE timestamp_auto>0"},
     'students'=>{'sql'=>"SELECT student FROM ".$self->table("page")
		 ." WHERE timestamp_auto>0 OR timestamp_manual>0 GROUP BY student ORDER BY student"},
     'studentCopies'=>{'sql'=>"SELECT student,copy FROM ".$self->table("page")
		       ." WHERE timestamp_auto>0 OR timestamp_manual>0"
		       ." GROUP BY student,copy ORDER BY student,copy"},
     'pageLastCopy'=>{'sql'=>"SELECT MAX(copy) FROM ".$self->table("page")
		      ." WHERE student=? AND page=?"},
     'pagesChanged'=>{'sql'=>"SELECT student,page,copy FROM ".$self->table("page")
		      ." WHERE timestamp_auto>? OR timestamp_manual>?"},
     'pages'=>{'sql'=>"SELECT * FROM ".$self->table("page")
	       ." WHERE timestamp_auto>0 OR timestamp_manual>0"},
     'studentPageMissing'=>
     {'sql'=>"SELECT COUNT(*) FROM ("
      ."SELECT student,page FROM ".$self->table("box","layout")." UNION "
      ."SELECT student,page FROM ".$self->table("namefield","layout")
      .") AS enter"
      ." WHERE student=? AND page NOT IN ("
      ." SELECT page FROM ".$self->table("page"). " WHERE student=? AND copy=?"
      ." )"},
     'pageNearRatio'=>{'sql'=>"SELECT MIN(ABS(1.0*black/total-?))"
		       ." FROM ".$self->table("zone")
		       ." WHERE student=? AND page=? AND copy=? AND total>0"},
     'pageZones'=>{'sql'=>"SELECT * FROM ".$self->table("zone")
		   ." WHERE student=? AND page=? AND copy=? AND type=?"},
     'pageZonesD'=>{'sql'=>"SELECT * FROM ".$self->table("zone")
		    ." WHERE student=? AND page=? AND copy=? AND type=?"
		    ." AND total>0"
		    ." ORDER BY 1.0*black/total"},
     'zoneDarkness'=>{'sql'=>"SELECT 1.0*black/total FROM ".$self->table("zone")
		      ." WHERE zoneid=? AND total>0"},
     'setManualPage'=>{'sql'=>"UPDATE ".$self->table("page")
		       ." SET timestamp_manual=?"
		       ." WHERE student=? AND page=? AND copy=?"},
     'setManual'=>{'sql'=>"UPDATE ".$self->table("zone")
		   ." SET manual=?"
		   ." WHERE student=? AND page=? AND copy=?"
		   ." AND type=? AND id_a=? AND id_b=?"},
     'setManualPageZones'=>{'sql'=>"UPDATE ".$self->table("zone")
			    ." SET manual=?"
			    ." WHERE student=? AND page=? AND copy=?"},
     'ticked'=>{'sql'=>"SELECT CASE"
		." WHEN manual >= 0 THEN manual"
		." WHEN total<=0 THEN -1"
		." WHEN black >= ? * total THEN 1"
		." ELSE 0"
		." END FROM ".$self->table("zone")
		." WHERE student=? AND copy=? AND type=? AND id_a=? AND id_b=?"},
     'tickedList'=>{'sql'=>"SELECT CASE"
		    ." WHEN manual >= 0 THEN manual"
		    ." WHEN total<=0 THEN -1"
		    ." WHEN black >= ? * total THEN 1"
		    ." ELSE 0"
		    ." END FROM ".$self->table("zone")
		    ." WHERE student=? AND copy=? AND type=? AND id_a=?"
		    ." ORDER BY id_b"},
     'tickedPage'=>{'sql'=>"SELECT CASE"
		    ." WHEN manual >= 0 THEN manual"
		    ." WHEN total<=0 THEN -1"
		    ." WHEN black >= ? * total THEN 1"
		    ." ELSE 0"
		    ." END,id_a,id_b FROM ".$self->table("zone")
		    ." WHERE student=? AND page=? AND copy=? AND type=?"},
     'zoneCorner'=>{'sql'=>"SELECT x,y FROM ".$self->table("position")
		    ." WHERE zoneid=? AND type=? AND corner=?"},
     'zoneCenter'=>{'sql'=>"SELECT AVG(x),AVG(y) FROM ".$self->table("position")
		    ." WHERE zoneid=? AND type=?"},
     'zoneDist'=>{'sql'=>"SELECT AVG((x-?)*(x-?)+(y-?)*(y-?))"
		  ." FROM ".$self->table("position")
		  ." WHERE zoneid=? AND TYPE=?"},
     'getAnnotated'=>{'sql'=>"SELECT annotated,timestamp_annotate,student,page,copy"
		      ." FROM ".$self->table("page")
		      ." WHERE timestamp_annotate>0"
		      ." ORDER BY student,copy,page"},
     'getAnnotatedPage'=>{'sql'=>"SELECT annotated"
			  ." FROM ".$self->table("page")
			  ." WHERE timestamp_annotate>0"
			  ." AND student=? AND page=? AND copy=?"},
     'setAnnotated'=>{'sql'=>"UPDATE ".$self->table("page")
		      ." SET annotated=?, timestamp_annotate=?"
		      ." WHERE student=? AND page=? AND copy=?"},
    };
}

# get_page($student,$page,$copy) returns all columns from the row with
# given ($student,$page,$copy) in table capture_page. If such a row
# exists, a hashref is returned. If not, undef is returned.

sub get_page {
  my ($self,$student,$page,$copy)=@_;
  return($self->dbh->selectrow_hashref($self->statement('getPage'),{},
				       $student,$page,$copy));
}

sub set_page_auto {
  my ($self,$src,$student,$page,$copy,
      $timestamp,$a,$b,$c,$d,$e,$f,$mse)=@_;
  if($self->get_page($student,$page,$copy)) {
    $self->statement('SetPageAuto')->execute($src,
					     $timestamp,$a,$b,$c,$d,$e,$f,
					     $mse,
					     $student,$page,$copy);
  } else {
    $self->statement('NEWPageAuto')->execute($src,$student,$page,$copy,
					     $timestamp,$a,$b,$c,$d,$e,$f,
					     $mse);
  }
}

sub set_page_manual {
  my ($self,$student,$page,$copy,
      $timestamp)=@_;
  if($self->get_page($student,$page,$copy)) {
    $self->statement('SetPageManual')->execute($timestamp,
					       $student,$page,$copy);
  } else {
    $self->statement('NEWPageManual')->execute($student,$page,$copy,
					       $timestamp);
  }
}

sub get_zoneid {
  my ($self,$student,$page,$copy,$type,$id_a,$id_b,$create)=@_;
  my $r=$self->dbh->selectrow_arrayref($self->statement('getZoneID'),{},
				       $student,$page,$copy,$type,$id_a,$id_b);
  if($r) {
    return($r->[0]);
  } else {
    if($create) {
      $self->statement('NEWZone')->execute($student,$page,$copy,$type,$id_a,$id_b);
      return($self->dbh->sqlite_last_insert_rowid());
    } else {
      return(undef);
    }
  }
}

sub set_zone_manual {
  my ($self,$student,$page,$copy,$type,$id_a,$id_b,$manual)=@_;
  my $zoneid=$self->get_zoneid($student,$page,$copy,$type,$id_a,$id_b,1);
  $self->statement('setZoneManual')->execute($manual,$zoneid);
}

sub set_zone_auto {
  my ($self,$student,$page,$copy,$type,$id_a,$id_b,$total,$black,$image)=@_;
  $self->statement('setZoneAuto')->execute($total,$black,$image,
					   $self->get_zoneid($student,$page,$copy,$type,$id_a,$id_b,1));
}

sub n_pages {
  my ($self)=@_;
  return($self->sql_single($self->statement('nPages')));
}

sub n_pages_transaction {
  my ($self)=@_;
  $self->begin_read_transaction;
  my $n=$self->n_pages;
  $self->end_transaction;
  return($n);
}

sub students {
  my ($self)=@_;
  return($self->sql_list($self->statement('students')));
}

sub students_transaction {
  my ($self)=@_;
  $self->begin_read_transaction;
  my @r=$self->students;
  $self->end_transaction;
  return(@r);
}

sub n_pages_auto {
  my ($self)=@_;
  return($self->sql_list($self->statement('nPagesAuto')));
}

sub page_sensitivity {
  my ($self,$student,$page,$copy,$threshold)=@_;
  my $delta=$self->sql_single($self->statement('pageNearRatio'),
			      $threshold,$student,$page,$copy);
  return(defined($delta) ? 10*($threshold-$delta)/$threshold : undef);
}

sub page_summary {
  my ($self,$student,$page,$copy,%oo)=@_;
  my %s=();
  my $p=$self->get_page($student,$page,$copy);

  if($p) {

    $s{'mse'}=($p->{'timestamp_auto'}>0 ?
	       sprintf($p->{'timestamp_manual'}>0 ? "(%.01f)" : "%.01f",
		       $p->{'mse'})
	       : "---");
    $s{'mse_color'}=($p->{'timestamp_auto'}>0 && $p->{'mse'}>$oo{'mse_threshold'} ? 'red' : undef);

    $s{'color'}=($p->{'timestamp_auto'}>0 ? 'lightblue'
		 : ($p->{'timestamp_manual'}>0 ? 'lightgreen' : undef));

    $s{'update'}=($p->{'timestamp_manual'}>0 ? format_date($p->{'timestamp_manual'})
		  : ($p->{'timestamp_auto'}>0 ? format_date($p->{'timestamp_auto'}) : '---'));

    my $sens=$self->page_sensitivity($student,$page,$copy,
				     $oo{'blackness_threshold'});
    $s{'sensitivity'}=(defined($sens) ? sprintf("%.01f",$sens) : '---');

    $s{'sensitivity_color'}=(defined($sens) ?
			     ($s{'sensitivity'} > $oo{'sensitivity_threshold'}
			      ? 'red' : undef) : undef);
  } else {
    %s=('mse'=>'---','update'=>'---','sensitivity'=>'---');
  }
  return(%s);
}

sub zone_darkness {
  my ($self,$zoneid)=@_;

  return($self->sql_single($self->statement('zoneDarkness'),
			   $zoneid));
}

sub ticked {
  my ($self,$student,$copy,$question,$answer,$darkness_threshold)=@_;
  return($self->sql_single($self->statement('ticked'),$darkness_threshold,
			   $student,$copy,ZONE_BOX,$question,$answer));
}

sub ticked_list {
  my ($self,$student,$copy,$question,$darkness_threshold)=@_;
  return($self->sql_list($self->statement('tickedList'),$darkness_threshold,
			 $student,$copy,ZONE_BOX,$question));
}

sub zones_count {
  my ($self,$student,$page,$copy,$type)=@_;
  $type=POSITION_BOX if(!$type);
  return($self->sql_single($self->statement('zonesCount'),
			   $student,$page,$copy,$type));
}

sub zone_dist2 {
  my ($self,$zoneid,$x,$y,$type)=@_;
  $type=POSITION_BOX if(!$type);
  return($self->sql_single($self->statement('zoneDist'),
			   $x,$x,$y,$y,$zoneid,$type));
}

sub zone_corner {
  my ($self,$zoneid,$corner,$type)=@_;
  $type=POSITION_BOX if(!$type);
  return($self->sql_row($self->statement('zoneCorner'),
			$zoneid,$type,$corner));
}

sub set_corner {
  my ($self,$zoneid,$corner,$type,$x,$y)=@_;
  if($self->zone_corner($zoneid,$corner,$type)) {
    $self->statement('setPosition')
      ->execute($x,$y,$zoneid,$corner,$type);
  } else {
    $self->statement('NEWPosition')
      ->execute($zoneid,$corner,$x,$y,$type);
  }
}

sub set_annotated {
  my ($self,$student,$page,$copy,$file,$timestamp)=@_;
  $timestamp=time() if(!$timestamp);
  $self->statement('setAnnotated')
    ->execute($file,$timestamp,$student,$page,$copy);
}

sub get_annotated_page {
  my ($self,$student,$page,$copy)=@_;
  my $f=$self->sql_single($self->statement('getAnnotatedPage'),
			  $student,$page,$copy);
  return($f);
}

sub new_page_copy {
  my ($self,$student,$page)=@_;
  my $c=$self->sql_single($self->statement('pageLastCopy'),
			  $student,$page);
  if($c) {
    return($c+1);
  } else {
    return(1);
  }
}

sub set_manual {
  my ($self,$student,$page,$copy,$type,$id_a,$id_b,$manual)=@_;
  if(!$self->sql_single($self->statement('zone'),
			$student,$page,$copy,$type,$id_a,$id_b)) {
    $self->statement('NEWZone')->execute($student,$page,$copy,$type,$id_a,$id_b);
  }
  $self->statement('setManual')->execute($manual,$student,$page,$copy,$type,$id_a,$id_b);
}

sub remove_manual {
  my ($self,$student,$page,$copy)=@_;
  $self->statement('setManualPage')->execute(-1,$student,$page,$copy);
  $self->statement('setManualPageZones')->execute(-1,$student,$page,$copy);
}

sub counts {
  my ($self)=@_;
  my %r=();
  $self->{'data'}->require_module('layout');
  my $sth=$self->statement('studentCopies');
  $sth->execute;
  while(my $p=$sth->fetchrow_hashref) {
    if($self->sql_single($self->statement('studentPageMissing'),
			 $p->{'student'},$p->{'student'},$p->{'copy'})) {
      $r{'incomplete'}++;
    } else {
      $r{'complete'}++;
    }
  }
  return(%r);
}

1;

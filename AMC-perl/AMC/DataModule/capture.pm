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
# page describes how a page scan fits with a question document page.
#
# * src is the scan file name (this is a raster image file, like
#   tiff. Usualy a each scan file contains only one page).
#
# * student is the student number of the question page corresponding
#   to the scan
#
# * page is the page number of the question page corresponding
#   to the scan (the page number starts from 1 for eevery student)
#
# * copy is the copy number of this page. When each student has his
#   own student number (question paper is printed from AMC and not
#   photocopied), copy is null. When all the question papers are
#   photocopied from, say, the three first versions of the subject,
#   student is the number from 1 to 3 identifying the original
#   question paper student number, and copy is an integer used to
#   differentiate the completed answer sheets coming from the
#   photocopied answer sheets from the same question paper.
#
# * timestamp_auto is the time when the scan processing was done
#   (using time function: seconds from Jan 1 1970), or -1 if there is
#   no automatic data capture for this page.
#
# * timestamp_manual is the time when the last manual data capture was
#   done (set to -1 if none).
#
# * a,b,c,d,e,f are the 6 parameters describing the linear transform
#   that taked the positions from the question paper to the positions
#   from the scan. Thus, if (x,y) are coordinates of a point on the
#   question paper, the corresponding pixel on the scan file should be
#   near coordinates (x',y'), with
#
#     x' = a*x + b*y + e
#     y' = c*x + d*y + f
#
# * mse is the mean square error for the four corner marks on the page
#   to be perfectly transported from the question paper to the scan by
#   the linear transform defined by (a,b,c,d,e,f).
#
# * annotated is the filename of the annotated jpeg of the page, when
#   available.
#
# * timestamp_annotate is the time the annotated page was produced.

# zone describes the different objects that can be found on the scans
# (corner marks, boxes, name field)
#
# * zoneid is an object identifier, also used for the position table.
#
# * student
# * page
# * copy    are the same as for the page table
#
# * type is the object type: ZONE_FRAME for the zone made from the 4
#   corner centers, ZONE_NAME for the name field zone, ZONE_DIGIT for
#   binary boxes at the top of the page identifying the page, ZONE_BOX
#   for the answers boxes to be filled (or not) by the students. The
#   constants ZONE_* are defined later.
#
# * id_a is the question number for ZONE_BOX, or the number id for
#   ZONE_DIGIT. It does not have any meaning for other objects.
#
# * id_b is the answer number for ZONE_BOX, and the digit number for
#   ZONE_DIGIT.
#
# * total is the total number of pixels from the scan inside the zone,
#   or -1 if not measured.
#
# * black is the number of black pixels from the scan inside the zone,
#   or -1 if not measured.
#
# * manual is 1 if the box is declared to be filled by a manual data
#   capture action, 0 if declared not to be filled, and -1 if no
#   manual data capture occured for this zone.
#
# * image is the name of the zone image file, extracted from the scan.

# position retains the position of the zones corners on the scan
#
# * zoneid is the zone identifier, as used in the zone table.
#
# * corner is the corner number (1=TL, 2=TR, 3=BR, 4=BL)
#
# * x
# * y  are the coordinates of the zone corner on the scan.
#
# * type is the type of the considered corner: POSITION_BOX if one
#   considers the corner of the box/zone, and POSITION_MEASURE if one
#   considers the corner of the measuring zone (a zone slightly
#   reduced from the box zone, so as not to consider box contours when
#   measuring the number of black pixels).

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
	  # Look if the namefield image is present...
	  my $nf="nom-".id2idf($id).".jpg";
	  if(-f "$cr/$nf") {
	    $self->statement('setZoneAuto')
	      ->execute(-1,-1,$nf,$zoneid);
	  }
	}

	for my $c (keys %{$an->{'case'}}) {
	  my $case=$an->{'case'}->{$c};
	  my $zoneid=$self->get_zoneid(@ep,0,ZONE_BOX,
				       $case->{'question'},$case->{'reponse'},1);

	  my $zf=sprintf("%d-%d/%d-%d.png",
			 @ep,
			 $case->{'question'},$case->{'reponse'});
	  $zf='' if(!-f "$cr/zooms/$zf");

	  $self->statement('setZoneAuto')
	    ->execute($case->{'pixels'},$case->{'pixelsnoirs'},$zf,
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

# set_page_auto(...) fills one row of the page table.

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

# sep_page_manual($student,$page,$copy,$timestamp) sets the timestamp
# for a manual data capture for a particular page. With no $timestamp
# argument, present time is used.

sub set_page_manual {
  my ($self,$student,$page,$copy,
      $timestamp)=@_;
  $timestamp=time() if(!defined($timestamp));
  if($self->get_page($student,$page,$copy)) {
    $self->statement('SetPageManual')->execute($timestamp,
					       $student,$page,$copy);
  } else {
    $self->statement('NEWPageManual')->execute($student,$page,$copy,
					       $timestamp);
  }
}

# get_zoneid($student,$page,$copy,$type,$id_a,$id_b,$create) gets the
# zone identifier corresponding to a particular zone. If $create is
# true, the identifier is created if not yet present in the database.

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

# set_zone_manual($student,$page,$copy,$type,$id_a,$id_b,$manual) sets
# the manual value (ticked or not) for a particular zone

sub set_zone_manual {
  my ($self,$student,$page,$copy,$type,$id_a,$id_b,$manual)=@_;
  my $zoneid=$self->get_zoneid($student,$page,$copy,$type,$id_a,$id_b,1);
  $self->statement('setZoneManual')->execute($manual,$zoneid);
}

# set_zone_auto(...,$total,$black,$image) sets automated data capture
# results for a particular zone.

sub set_zone_auto {
  my ($self,$student,$page,$copy,$type,$id_a,$id_b,$total,$black,$image)=@_;
  $self->statement('setZoneAuto')->execute($total,$black,$image,
					   $self->get_zoneid($student,$page,$copy,$type,$id_a,$id_b,1));
}

# n_pages returns the number of pages for which a data capture (manual
# or auto) is declared.

sub n_pages {
  my ($self)=@_;
  return($self->sql_single($self->statement('nPages')));
}

# n_pages_transaction calls n_pages inside a SQLite transaction.

sub n_pages_transaction {
  my ($self)=@_;
  $self->begin_read_transaction;
  my $n=$self->n_pages;
  $self->end_transaction;
  return($n);
}

# students returns the list of students numbers for which a data
# capture is declared.

sub students {
  my ($self)=@_;
  return($self->sql_list($self->statement('students')));
}

# students_transaction calls students inside a SQLite transaction.

sub students_transaction {
  my ($self)=@_;
  $self->begin_read_transaction;
  my @r=$self->students;
  $self->end_transaction;
  return(@r);
}

# n_pages_auto returns the number of pages for which a automated data
# capture occured.

sub n_pages_auto {
  my ($self)=@_;
  return($self->sql_list($self->statement('nPagesAuto')));
}

# page_sensitivity($student,$page,$copy,$threshold) returns a
# sensitivity value for the page automated data capture. When this
# value is low (near 0), black and white boxes have darkness values
# far away from the threshold, and thus one can think that it is well
# recognized if the boxes are ticked or not. With high values of the
# sensitivity (the maximal value is 10), ticked boxes are not robustly
# detected: if one changes a little the darkness threshold, boxes can
# pass from the ticked to not-ticked state or vice versa.

sub page_sensitivity {
  my ($self,$student,$page,$copy,$threshold)=@_;
  my $delta=$self->sql_single($self->statement('pageNearRatio'),
			      $threshold,$student,$page,$copy);
  return(defined($delta) ? 10*($threshold-$delta)/$threshold : undef);
}

# page_summary($student,$page,$copy,%options) returns a hash %s giving
# some summarized information about the page automated data capture
# process:
#
# $s{'mse'} is the mean square error of the transform from question
# paper coordinates to scan coordinates
#
# $s{'mse_color'} is 'red' if the MSE exceeds
# $options{'mse_threshold'}, and undef otherwise
#
# $s{'color'} is blue if some automated data capture occured for this
# page, green if some manual data capture occured, and undef
# otherwise.
#
# $s{'update'} is a textual reprsentation of the date when the last
# data capture occured.
#
# $s{'sensitivity'} is the sensitivity (see function page_sensitivity).
#
# $s{'sensitivity'} is 'red' is the sensitivity exceeds
# $options{'sensitivity_threshold'}, undef otherwise.

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

# zone_drakness($zoneid) return the darkness (from 0 to 1) for a
# particular zone.

sub zone_darkness {
  my ($self,$zoneid)=@_;

  return($self->sql_single($self->statement('zoneDarkness'),
			   $zoneid));
}

# ticked($student,$copy,$question,$answer,$darkness_threshold) returns
# 1 if the darkness of a particular zone exceeds $darkness_threshold,
# and 0 otherwise. If a manual data capture occured for this zone, the
# darkness is not considered and the manual result is given instead.

sub ticked {
  my ($self,$student,$copy,$question,$answer,$darkness_threshold)=@_;
  return($self->sql_single($self->statement('ticked'),$darkness_threshold,
			   $student,$copy,ZONE_BOX,$question,$answer));
}

# ticked_list($student,$copy,$question,$darkness_threshold) returns a
# list with the ticked results for all the answers boxes from a
# particular question.

sub ticked_list {
  my ($self,$student,$copy,$question,$darkness_threshold)=@_;
  return($self->sql_list($self->statement('tickedList'),$darkness_threshold,
			 $student,$copy,ZONE_BOX,$question));
}

# zones_count($student,$page,$copy,$type) returns the number of zones
# of type $type from a particular page.

sub zones_count {
  my ($self,$student,$page,$copy,$type)=@_;
  $type=POSITION_BOX if(!$type);
  return($self->sql_single($self->statement('zonesCount'),
			   $student,$page,$copy,$type));
}

# zone_dist2($zoneid,$x,$y,$type) returns the mean of the square
# distance from the point ($x,$y) to the corners of a particular zone.

sub zone_dist2 {
  my ($self,$zoneid,$x,$y,$type)=@_;
  $type=POSITION_BOX if(!$type);
  return($self->sql_single($self->statement('zoneDist'),
			   $x,$x,$y,$y,$zoneid,$type));
}

# zone_corner($zoneid,$corner,$type) returns the coordinates of a zone
# corner as a list (with two values).

sub zone_corner {
  my ($self,$zoneid,$corner,$type)=@_;
  $type=POSITION_BOX if(!$type);
  return($self->sql_row($self->statement('zoneCorner'),
			$zoneid,$type,$corner));
}

# set_corner($zoneid,$corner,$type,$x,$y) sets the coordinates of a
# corner of a zone (or the corner measuring zone, reduced from the
# original zone, depending on the $type parameter).

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

# set_annotated($student,$page,$copy,$file,$timestamp) sets the name
# of the annotated image file, and the time when it wad made.

sub set_annotated {
  my ($self,$student,$page,$copy,$file,$timestamp)=@_;
  $timestamp=time() if(!$timestamp);
  $self->statement('setAnnotated')
    ->execute($file,$timestamp,$student,$page,$copy);
}

# get_annotated_page($student,$page,$copy) returns the annotated image
# filename of a particular page.

sub get_annotated_page {
  my ($self,$student,$page,$copy)=@_;
  my $f=$self->sql_single($self->statement('getAnnotatedPage'),
			  $student,$page,$copy);
  return($f);
}

# new_page_copy($student,$page) creates a new (unused) copy number for
# a given question page.

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

# set_manual(...,$type,$id_a,$id_b,$manual) sets the manual value for
# a particular zone.

sub set_manual {
  my ($self,$student,$page,$copy,$type,$id_a,$id_b,$manual)=@_;
  if(!$self->sql_single($self->statement('zone'),
			$student,$page,$copy,$type,$id_a,$id_b)) {
    $self->statement('NEWZone')->execute($student,$page,$copy,$type,$id_a,$id_b);
  }
  $self->statement('setManual')->execute($manual,$student,$page,$copy,$type,$id_a,$id_b);
}

# remove_manual($student,$page,$copy) deletes all manual data capture
# information for a particular page.

sub remove_manual {
  my ($self,$student,$page,$copy)=@_;
  $self->statement('setManualPage')->execute(-1,$student,$page,$copy);
  $self->statement('setManualPageZones')->execute(-1,$student,$page,$copy);
}

# counts returns a hash %r giving the %r{'complete'} number of
# complete sheets captured, and the %r{'incomplete'} number of student
# sheets for which one part has been captured (with manual or
# automated data capture), and one other part needs capturing.

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

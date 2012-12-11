#! /usr/bin/perl
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

use Getopt::Long;

use AMC::Basic;
use AMC::NamesFile;
use AMC::Data;
use AMC::DataModule::report ':const';
use AMC::Gui::Avancement;
use AMC::Substitute;

use Module::Load;

use Email::MIME;
use Email::Address;
use Email::Sender;
use Email::Sender::Simple qw(sendmail);

my $project_dir='';
my $data_dir='';
my $students_list='';
my $list_encoding='UTF-8';
my $csv_build_name='';
my $ids_file='';
my $email_column='';
my $sender='';
my $transport='sendmail';
my $sendmail_path='/usr/sbin/sendmail';
my $smtp_host='smtp';
my $smtp_port=25;
my $text='';
my $subject='';
my $project_name='';
my $cc='';
my $bcc='';
my @attach_files=();

@ARGV=unpack_args(@ARGV);
@ARGV_ORIG=@ARGV;

GetOptions("project=s"=>\$project_dir,
	   "project-name=s"=>\$project_name,
	   "data=s"=>\$data_dir,
	   "students-list=s"=>\$students_list,
	   "list-encoding=s"=>\$list_encoding,
	   "csv-build-name=s"=>\$csv_build_name,
	   "ids-file=s"=>\$ids_file,
	   "email-column=s"=>\$email_column,
	   "sender=s"=>\$sender,
	   "text=s"=>\$text,
	   "subject=s"=>\$subject,
	   "transport=s"=>\$transport,
	   "sendmail-path=s"=>\$sendmail_path,
	   "smtp-host=s"=>\$smtp_host,
	   "smtp-port=s"=>\$smtp_port,
	   "debug=s"=>\$debug,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "attach=s"=>\@attach_files,
	   "cc=s"=>\$cc,
	   "bcc=s"=>\$bcc,
	   );

set_debug($debug);

debug "Parameters: ".join(" ",map { "<$_>" } @ARGV_ORIG);

sub error {
  my ($text)=@_;
  debug "AMC-sendmail ERROR: $text";
  print "ERROR: $text\n";
  exit(1);
}

sub parse_add {
  my ($s)=@_;
  return(map { $_->address(); }
	 (Email::Address->parse($s)));
}

$data_dir="$project_dir/data" if($project_dir && !$data_dir);

error("students list not found:$students_list") if(!-f $students_list);

my $students=AMC::NamesFile::new($students_list,
				 'encodage'=>$list_encoding,
				 "identifiant"=>$csv_build_name);

error("data directory not found: $data_dir") if(!-d $data_dir);

my %ids=();
if(-f $ids_file) {
  debug "provided IDS:";
  open(IDS,$ids_file);
  while(<IDS>) {
    chomp;
    debug "[$_]";
    $ids{$_}=1;
  }
  close(IDS);
} else {
  debug "IDS file $ids_file not found";
}

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $data=AMC::Data->new($data_dir);
my $report=$data->module('report');
my $assoc=$data->module('association');
my $scoring=$data->module('scoring');

my $subst=AMC::Substitute::new('assoc'=>$assoc,'scoring'=>$scoring,
			       'names'=>$students,
			       'name'=>$project_name);

$data->begin_read_transaction('Mail');
my $subdir=$report->get_dir(REPORT_ANNOTATED_PDF);

my $pdf_dir="$project_dir/$subdir";

error("PDF directory not found: $pdf_dir") if(!-d $pdf_dir);

my $key=$assoc->variable('key_in_list');
my $r=$report->get_associated_type(REPORT_ANNOTATED_PDF);

my $t;
if($transport eq 'sendmail') {
  load Email::Sender::Transport::Sendmail;
  $t=Email::Sender::Transport::Sendmail->new({ sendmail => $sendmail_path });;
} elsif($transport eq 'SMTP') {
  load Email::Sender::Transport::SMTP;
  $t=Email::Sender::Transport::SMTP
    ->new({'host'=>$smtp_host,
	   'port'=>$smtp_port,
	   });
} else {
  error("Unknown transport: $transport");
}

my $nn=1+$#$r;
if($ids_file) {
  my @i=(keys %ids);
  $nn=1+$#i;
}
my $delta=($nn>0 ? 1/$nn : 1);

my @attachments=();

for my $f (@attach_files) {
  if(-f $f) {
    my $name=$f;
    $name =~ s/.*\///;
    my $body='';
    open(ATT,$f);
    while(<ATT>) { $body.=$_; }
    close(ATT);
    push @attachments,
      Email::MIME->create(attributes=>
			  {filename     => $name,
			   content_type => file_mimetype($f),
			   encoding     => "base64",
			   name         => $name,
			   disposition  => "attachment",
			  },
			  body => $body,
			    );
  } else {
    debug "ERROR: Cannot attach inexistant file $f";
  }
}

STUDENT: for my $i (@$r) {
  my ($s)=$students->data($key,$i->{'id'});
  my $dest=$s->{$email_column};
  debug "Loop: ID $i->{'id'} DEST [$dest]";
  if($ids_file && !$ids{$i->{'id'}}) {
    debug "Skipped";
    next STUDENT;
  }
  if($dest) {
    my $file=$pdf_dir.'/'.$i->{'file'};
    debug "  FILE=$file";
    if(-f $file) {
      my $body='';
      open(PDF,$file);
      while(<PDF>) { $body.=$_; }
      close(PDF);

      my @sc=$assoc->real_back($i->{'id'});
      my @parts=
	(
	 Email::MIME->create(attributes=>
			     {content_type => "text/plain",
			      encoding     => "base64",
			      charset      => "UTF-8",
			     },
			     body_str => $subst->substitute($text,@sc),
			    ),
	 Email::MIME->create(attributes=>
			     {filename     => "corrected.pdf",
			      content_type => "application/pdf",
			      encoding     => "base64",
			      name         => "corrected.pdf",
			      disposition  => "attachment",
			     },
			     body => $body,
			    ),
	);

      my $email = Email::MIME
	->create(header_str => [ From=>$sender, To=>$dest,
				 Subject=>$subst->substitute($subject,@sc) ],
		 parts      => [ @parts,@attachments ],
		);
      $email->header_str_set(Cc=>$cc) if($cc);

      my @all_dests=($dest);
      push @all_dests,parse_add($cc) if($cc);
      push @all_dests,parse_add($bcc) if($bcc);
      my $b=eval {
	sendmail($email,{'transport'=>$t,to=>\@all_dests});
      } || $@;
      if($b) {
	my $status='OK';
	my $m='';
	if($b->isa('Email::Sender::Failure')) {
	  $status='FAILED';
	  $m=$b->message;
	  $m =~ s/[\n\r]+/ | /g;
	}
	print "$status [$i->{'id'}] $m\n";
	debug "$status [$i->{'id'}] $m";
      } else {
	debug "sendmail failed";
	print "FAIL [$i->{'id'}] Email::Sender error\n";
      }
    } else {
      debug "No file: $file";
    }
  } else {
    debug "No dest";
  }
  $avance->progres($delta);
}

$data->end_transaction('Mail');

$avance->fin();


#! /usr/bin/perl
#
# Copyright (C) 2008-2021 Alexis Bienvenüe <paamc@passoire.fr>
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

use warnings;
use 5.012;

use Getopt::Long;
use File::Spec::Functions qw/tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use File::Copy;

use Module::Load;
use Module::Load::Conditional qw/check_install/;

use AMC::Basic;
use AMC::Exec;
use AMC::Data;
use AMC::Gui::Avancement;
use AMC::NamesFile;

my $data_dir            = "";
my $sujet               = '';
my $print_cmd           = 'cupsdoprint %f';
my $progress            = '';
my $progress_id         = '';
my $fich_nums           = '';
my $methode             = 'CUPS';
my $imprimante          = '';
my $options             = 'number-up=1';
my $output_file         = '';
my $output_answers_file = '';
my $split               = '';
my $answer_first        = '';
my $extract_with        = 'pdftk';
my $password            = '';
my $students_list       = '';
my $students_list_key   = '';
my $password_key        = '';

unpack_args();

GetOptions(
    "data=s"           => \$data_dir,
    "sujet=s"          => \$sujet,
    "fich-numeros=s"   => \$fich_nums,
    "progression=s"    => \$progress,
    "progression-id=s" => \$progress_id,
    "print-command=s"  => \$print_cmd,
    "methode=s"        => \$methode,
    "imprimante=s"     => \$imprimante,
    "output=s"         => \$output_file,
    "split!"           => \$split,
    "answer-first!"    => \$answer_first,
    "options=s"        => \$options,
    "extract-with=s"   => \$extract_with,
    "password=s"       => \$password,
    "students-list=s"  => \$students_list,
    "list-key=s"       => \$students_list_key,
    "password-key=s"   => \$password_key,
);

my $commandes = AMC::Exec::new('AMC-imprime');
$commandes->signalise();

die "Needs data directory" if ( !$data_dir );
die "Needs subject file"   if ( !$sujet );

die "Needs print command" if ( $methode =~ /^command/i && !$print_cmd );
die "Needs output file"   if ( $methode =~ /^file/i    && !$output_file );

my @available_extracts = ( 'pdftk', 'pdftk+NA', 'gs', 'qpdf', 'sejda-console' );

die "Invalid value for extract_with: $extract_with"
  if ( !grep( /^\Q$extract_with\E$/, @available_extracts ) );

@available_extracts =
  grep { my $c = $_; $c =~ s/\+.*//; commande_accessible($c) }
  @available_extracts;

die "No available extract engine" if ( !@available_extracts );

if ( !grep( /^\Q$extract_with\E$/, @available_extracts ) ) {
    debug( "Extract engines available: " . join( " ", @available_extracts ) );
    $extract_with = $available_extracts[0];
    debug("Switching to extract engine $extract_with");
}

my $avance = AMC::Gui::Avancement::new( $progress, id => $progress_id );

my $data   = AMC::Data->new($data_dir);
my $layout = $data->module('layout');
my $report = $data->module('report');

my $students = '';

if ( -f $students_list ) {
    $students =
      AMC::NamesFile::new( $students_list, identifiant => $students_list_key );
}

my @es;

if ($fich_nums) {
    open( NUMS, $fich_nums );
    while (<NUMS>) {
        push @es, $1 if (/^([0-9]+)$/);
    }
    close(NUMS);
} else {
    $layout->begin_read_transaction('prST');
    @es = $layout->query_list('students');
    $layout->end_transaction('prST');
}

debug( @es . " sheets to print" );

my $cups;

if ( $methode =~ /^cups/i ) {
    my $mod = "AMC::Print::" . lc($methode);
    load($mod);
    my $error = $mod->check_available();
    if ($error) {
        die $error;
    }

    $cups = $mod->new();
    $cups->select_printer($imprimante);

    # record options (so that if given multiple times, the last value
    # is considered)
    my %opts = ();
    for my $o ( split( /\s*,+\s*/, $options ) ) {
        my $on = $o;
        my $ov = 1;
        if ( $o =~ /([^=]+)=(.*)/ ) {
            $on = $1;
            $ov = $2;
        }
        $opts{$on} = $ov;
    }

    for my $o ( keys %opts ) {
        debug "Option : $o=$opts{$o}";
        $cups->set_option( $o, $opts{$o} );
    }
}

sub process_pages {
    my ( $slices, $f_dest, $e, $suggested_filename, $student_id, $suffix ) = @_;

    my $elong = sprintf( "%04d", $e );
    my $tmp = File::Temp->new( DIR => tmpdir(), UNLINK => 1, SUFFIX => '.pdf' );
    my $fn  = $tmp->filename();
    my $n_slices = 1 + $#{$slices};
    my $suffixed_elong = $elong;
    if ($suffix) {
        $suffixed_elong .= "-" . $suffix;
    } else {
        $suffix='';
    }

    print "Student $elong [$suffix]: $n_slices slices to file $fn...\n";
    return () if ( $n_slices == 0 );

    my $user_password  = '';
    my $owner_password = '';
    if ($password) {
        $user_password = $password;
        debug "PDF file locked with password (ID=$student_id)";
        if ( $students && defined($student_id) ) {
            debug "Looking for personal password...";
            my ($s) = $students->data( $students_list_key, $student_id );
            $owner_password = $s->{$password_key};
            $owner_password = '' if ( !defined($owner_password) );
            debug "Found $owner_password";
        }
    }

    if ( $extract_with eq 'gs' ) {
        die
"Can't use <gs> to build multiple-slices PDF file. Please switch to <qpdf>."
          if ( $n_slices > 1 );
        my @gscommand =
          ( "gs", "-dBATCH", "-dNOPAUSE", "-q", "-sDEVICE=pdfwrite" );
        $owner_password = $user_password if ( !$owner_password );
        if ($user_password) {
            push @gscommand, "-sUserPassword=$user_password";
        }
        if ($owner_password) {
            push @gscommand, "-sOwnerPassword=$owner_password";
        }
        $commandes->execute(
            @gscommand, "-sOutputFile=$fn",
            "-dFirstPage=" . $slices->[0]->{first},
            "-dLastPage=" . $slices->[0]->{last}, $sujet
        );
    } elsif ( $extract_with eq 'pdftk' ) {
        my @pdftkcommand = (
            "pdftk", $sujet, "cat",
            ( map { $_->{first} . "-" . $_->{last} } @$slices ),
            "output", $fn
        );
        if ($user_password) {
            push @pdftkcommand, "user_pw", $user_password;
        }
        if ($owner_password) {
            push @pdftkcommand, "owner_pw", $owner_password;
        }
        $commandes->execute(@pdftkcommand);
    } elsif ( $extract_with eq 'pdftk+NA' ) {

        # Use pdftk with a workaround to keep PDF forms.
        # See https://bugs.debian.org/792168
        my $fn_step = "$fn.1.pdf";
        $commandes->execute( "pdftk", $sujet, "cat",
            ( map { $_->{first} . "-" . $_->{last} } @$slices ),
            "output", $fn_step );
        my @pdftkcommand =
          ( "pdftk", $fn_step, "output", $fn, "need_appearances" );
        if ($user_password) {
            push @pdftkcommand, "user_pw", $user_password;
        }
        if ($owner_password) {
            push @pdftkcommand, "owner_pw", $owner_password;
        }
        $commandes->execute(@pdftkcommand);
    } elsif ( $extract_with eq "qpdf" ) {

        # Cmd: qpdf input.pdf --pages input.pdf 3,4-7,10 -- output.pdf
        $owner_password = $user_password if ( !$owner_password );
        my @qpdfcommand = ("qpdf");
        if ($password) {
            push @qpdfcommand, "--encrypt", $user_password, $owner_password,
              128, "--";
        }
        push @qpdfcommand, $sujet, "--pages", $sujet,
          join( ",", map { $_->{first} . "-" . $_->{last} } @$slices ),
          "--";
        $commandes->execute( @qpdfcommand, $fn );

    } elsif ( $extract_with eq 'sejda-console' ) {

        my $fn_step   = "$fn.1.pdf";
        my $extracted = ( $password ? $fn_step : $fn );

        # First extract pages
        my @sejdacommand = (
            "sejda-console", "extractpages", "-f", $sujet, "-o", $extracted,
            "--overwrite"
        );
        push @sejdacommand, "-s",
          join( ",", map { $_->{first} . "-" . $_->{last} } @$slices );
        $commandes->execute(@sejdacommand);

        if ($password) {
            @sejdacommand = (
                "sejda-console", "encrypt", "-f", $fn_step, "-o", $fn,
                "--overwrite"
            );
            if ($user_password) {
                push @sejdacommand, "-u", $user_password;
            }
            if ($owner_password) {
                push @sejdacommand, "-a", $owner_password;
            }
            $commandes->execute(@sejdacommand);

            unlink $fn_step;
        }
    }

    if ( $methode =~ /^cups/i ) {
        $cups->print_file( $fn, "QCM : sheet $elong [$suffix]" );
    } elsif ( $methode =~ /^file/i ) {
        $f_dest .= "-%e.pdf" if ( $f_dest !~ /[%]e/ );
        if ($suggested_filename) {
            debug "FDEST=".show_utf8($f_dest)."\n";
            debug "SUGG=".show_utf8($suggested_filename)."\n";
            $f_dest =~ s/[%]e/$suggested_filename/g;
        } else {
            $f_dest =~ s/[%]e/$suffixed_elong/g;
        }
        debug "Moving to " . show_utf8($f_dest);
        if ( move( $fn, $f_dest ) ) {
            $report->begin_transaction("prtS");
            $report->printed_filename( $e, $f_dest );
            $report->end_transaction("prtS");
        } else {
            debug "MOVE FAILED!";
        }
    } elsif ( $methode =~ /^command/i ) {
        my @c =
          map { s/[%]f/$fn/g; s/[%]e/$suffixed_elong/g; $_; } split( /\s+/, $print_cmd );

        #print STDERR join(' ',@c)."\n";
        $commandes->execute(@c);
    } else {
        die "Unknown method: $methode";
    }

    close($tmp);
}

for my $e (@es) {
    my ( $debut, $fin, $debutA, $finA, $suggested_filename, $student_id );
    $layout->begin_read_transaction('prSP');
    ( $debut,  $fin )  = $layout->query_row( 'subjectpageForStudent',  $e );
    ( $debutA, $finA ) = $layout->query_row( 'subjectpageForStudentA', $e )
      if ( $split || $answer_first );
    $suggested_filename = $layout->get_associated_filename($e);
    $student_id = $layout->get_associated_id($e);
    $layout->end_transaction('prSP');

    my @sl_all = ();
    if ( $debut && $fin ) {
        push @sl_all, { first => $debut, last => $fin };
    }

    my @sl_answer = ();
    if ( $debutA && $finA ) {
        push @sl_answer, { first => $debutA, last => $finA };
    }
    my @sl_preanswer = ();
    if ( $debut && $debutA && $debut < $debutA ) {
        push @sl_preanswer, { first => $debut, last => $debutA - 1 };
    }
    my @sl_postanswer = ();
    if ( $fin && $finA && $fin > $finA ) {
        push @sl_postanswer, { first => $finA + 1, last => $fin };
    }

    if ($split) {
        process_pages( \@sl_preanswer, $output_file, $e,
            $suggested_filename, $student_id, "0S" );
        process_pages( \@sl_answer, $output_file, $e, $suggested_filename,
            $student_id, "1A" );
        process_pages( \@sl_postanswer, $output_file, $e,
            $suggested_filename, $student_id, "2S" );
    } else {
        if ($answer_first) {
            process_pages( [ @sl_answer, @sl_postanswer, @sl_preanswer ],
                $output_file, $e, $suggested_filename, $student_id );
        } else {
            process_pages( \@sl_all, $output_file, $e, $suggested_filename,
                $student_id );
        }
    }

    $avance->progres( 1 / ( 1 + $#es ) );
}

$avance->fin();


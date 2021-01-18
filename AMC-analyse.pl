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

use File::Spec::Functions qw/tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use Getopt::Long;

use AMC::Path;
use AMC::Basic;
use AMC::Exec;
use AMC::Queue;
use AMC::Calage;
use AMC::Subprocess;
use AMC::Boite qw/min max/;
use AMC::Data;
use AMC::DataModule::capture qw/:zone :position/;
use AMC::DataModule::layout qw/:flags/;
use AMC::Gui::Avancement;

my $pid   = '';
my $queue = '';

sub catch_signal {
    my $signame = shift;
    debug "*** AMC-analyse : signal $signame, transfered to $pid...";
    kill 2, $pid if ($pid);
    $queue->killall() if ($queue);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

my $data_dir        = "";
my $cr_dir          = "";
my $debug_image_dir = '';
my $debug_image     = '';
my $debug_pixels    = 0;
my $progress        = 0;
my $progress_id     = 0;
my $scans_list;
my $n_procs              = 0;
my $project_dir          = '';
my $tol_mark             = '';
my $prop                 = 0.8;
my $bw_threshold         = 0.6;
my $blur                 = '1x1';
my $threshold            = '60%';
my $multiple             = '';
my $ignore_red           = 1;
my $pre_allocate         = 0;
my $try_three            = 1;
my $tag_overwritten      = 1;
my $unlink_on_global_err = 0;

unpack_args();

GetOptions(
    "data=s"                => \$data_dir,
    "cr=s"                  => \$cr_dir,
    "tol-marque=s"          => \$tol_mark,
    "prop=s"                => \$prop,
    "bw-threshold=s"        => \$bw_threshold,
    "debug-pixels!"         => \$debug_pixels,
    "progression=s"         => \$progress,
    "progression-id=s"      => \$progress_id,
    "liste-fichiers=s"      => \$scans_list,
    "projet=s"              => \$project_dir,
    "n-procs=s"             => \$n_procs,
    "debug-image-dir=s"     => \$debug_image_dir,
    "multiple!"             => \$multiple,
    "ignore-red!"           => \$ignore_red,
    "pre-allocate=s"        => \$pre_allocate,
    "try-three!"            => \$try_three,
    "tag-overwritten!"      => \$tag_overwritten,
    "unlink-on-global-err!" => \$unlink_on_global_err,
);

$tag_overwritten = 0 if ($multiple);

use_gettext;

my %error_text = (
    NMARKS      => __("Not enough corner marks detected"),
    MAYBE_BLANK => __("This page seems to be blank"),
);

sub translate_error {
    my ($s, $txt) = @_;
    return ( $error_text{$s} || $txt );
}

my $progress_h = AMC::Gui::Avancement::new( $progress, id => $progress_id );

my $data;
my $layout;

my $max_enter;

# Reads scan files from command line

my @scans = @ARGV;

# Adds scan files from a list file

if ( $scans_list && open( LISTE, '<:utf8', $scans_list ) ) {
    while (<LISTE>) {
        chomp;
        if ( -f $_ ) {
            debug "Scan from list : $_";
            push @scans, $_;
        } else {
            debug_and_stderr "WARNING. File does not exist : $_";
        }
    }
    close(LISTE);
}

exit(0) if ( $#scans < 0 );

sub error {
    my ( $e, %opts ) = @_;
    if ( $opts{process} ) {
        if ($debug_image) {
            $opts{process}->commande( "output " . $debug_image );
            $opts{process}->ferme_commande;
        }
    }
    if ( $opts{silent} ) {
        debug $e;
    } else {
        debug "ERR: Scan $opts{scan}: $e\n";
        print "ERR: Scan $opts{scan}: $e\n";
    }
    if ( $opts{register_failed} ) {
        my $capture = AMC::Data->new($data_dir)->module('capture');
        $capture->begin_transaction('CFLD');
        $capture->failed( $opts{register_failed} );
        $capture->end_transaction('CFLD');
    }
}

sub check_rep {
    my ( $r, $create ) = (@_);
    if ( $create && $r && !-x $r ) {
        mkdir($r);
    }

    die "ERROR: directory does not exist: $r" if ( !-d $r );
}

$data_dir = $project_dir . "/data" if ( $project_dir && !$data_dir );
$cr_dir   = $project_dir . "/cr"   if ( $project_dir && !$cr_dir );

check_rep($data_dir);
check_rep( $cr_dir, 1 );

my $delta = $progress / ( 1 + $#scans );

my $tol_mark_plus  = 1 / 5;
my $tol_mark_moins = 1 / 5;

if ($tol_mark) {
    if ( $tol_mark =~ /(.*),(.*)/ ) {
        $tol_mark_moins = $1;
        $tol_mark_plus  = $2;
    } else {
        $tol_mark_moins = $tol_mark;
        $tol_mark_plus  = $tol_mark;
    }
}

########################################
# Gets layout data from a (random) page

sub code_cb {
    my ( $nombre, $chiffre ) = (@_);
    return ("$nombre:$chiffre");
}

sub detecte_cb {
    my $k = shift;
    if ( $k =~ /^([0-9]+):([0-9]+)$/ ) {
        return ( $1, $2 );
    } else {
        return ();
    }
}

sub get_layout_data {
    my ( $layout, $student, $page, $all ) = @_;
    my $r = {
        'corners.test'  => {},
        'zoom.file'     => {},
        'darkness.data' => {},
        boxes           => {},
        flags           => {}
    };

    ( $r->{width}, $r->{height}, $r->{markdiameter}, undef ) =
      $layout->dims( $student, $page );
    $r->{frame} =
      AMC::Boite::new_complete( $layout->all_marks( $student, $page ) );

    for my $c ( $layout->type_info( 'digit', $student, $page ) ) {
        my $k = code_cb( $c->{numberid}, $c->{digitid} );
        $r->{boxes}->{$k} =
          AMC::Boite::new_MN( map { $c->{$_} } (qw/xmin ymin xmax ymax/) );
        $r->{flags}->{$k} = 0;
    }

    if ($all) {
        for my $c ( $layout->type_info( 'box', $student, $page ) ) {
            $r->{boxes}->{ $c->{question} . "." . $c->{answer} } =
              AMC::Boite::new_MN( map { $c->{$_} } (qw/xmin ymin xmax ymax/) );
            $r->{flags}->{ $c->{question} . "." . $c->{answer} } =
              $c->{flags};
        }
        for my $c ( $layout->type_info( 'namefield', $student, $page ) ) {
            $r->{boxes}->{namefield} =
              AMC::Boite::new_MN( map { $c->{$_} } (qw/xmin ymin xmax ymax/) );
        }
    }

    return ($r);
}

my $t_type = 'lineaire';
my $cale   = AMC::Calage::new( type => $t_type );

$data   = AMC::Data->new($data_dir);
$layout = $data->module('layout');

$layout->begin_read_transaction('cRLY');

$max_enter = $layout->max_enter();

if ( $layout->pages_count() == 0 ) {
    $layout->end_transaction('cRLY');
    error("No layout");
    exit(1);
}
debug "" . $layout->pages_count() . " layouts\n";

my @ran           = $layout->random_studentPage;
my $random_layout = get_layout_data($layout, @ran);

$layout->end_transaction('cRLY');

########################################
# Fits marks on scan to layout data

sub command_transf {
    my ( $process, $cale, @args ) = @_;

    my @r = $process->commande(@args);
    for (@r) {
        $cale->{ 't_' . $1 } = $2 if (/([a-f])=(-?[0-9.]+)/);
        $cale->{MSE} = $1 if (/MSE=([0-9.]+)/);
    }
}

sub marks_fit {
    my ( $process, $ld, $three ) = @_;

    $cale = AMC::Calage::new( type => 'lineaire' );
    command_transf(
        $process, $cale,
        join( ' ',
            "optim" . ( $three ? "3" : "" ),
            $ld->{frame}->draw_points() )
    );

    debug "MSE=" . $cale->mse();

    $ld->{transf} = $cale;
}

sub get_shape {
    my ($flags) = @_;
    if ( $flags & BOX_FLAGS_SHAPE_OVAL ) {
        return ('oval');
    }
    return ('square');
}

##################################################
# Reads darkness of a particular box

sub measure_box {
    my ( $process, $ld, $k, @spc ) = (@_);
    my $r     = 0;
    my $flags = $ld->{flags}->{$k};

    $ld->{'corners.test'}->{$k} = AMC::Boite::new();

    if (@spc) {
        if ( $k =~ /^([0-9]+)\.([0-9]+)$/ ) {
            $process->commande( join( ' ', "id", @spc[ 0, 1 ], $1, $2 ) );
        }
    } else {
        $flags = 0 if ( !defined($flags) );
    }

    if ( !( $flags & BOX_FLAGS_DONTSCAN ) ) {
        $ld->{'boxes.scan'}->{$k} = AMC::Boite::new();
    } else {
        $ld->{'boxes.scan'}->{$k} = $ld->{boxes}->{$k}->clone;
        $ld->{'boxes.scan'}->{$k}->transforme( $ld->{transf} );
    }

    if ( !( $flags & BOX_FLAGS_DONTSCAN ) ) {
        my $pc;

        $pc = $ld->{boxes}->{$k}->commande_mesure0( $prop, get_shape($flags) );

        for ( $process->commande($pc) ) {
            if (/^TCORNER\s+(-?[0-9\.]+),(-?[0-9\.]+)$/) {
                $ld->{'boxes.scan'}->{$k}->def_point_suivant( $1, $2 );
            }
            if (/^COIN\s+(-?[0-9\.]+),(-?[0-9\.]+)$/) {
                $ld->{'corners.test'}->{$k}->def_point_suivant( $1, $2 );
            }
            if (/^PIX\s+([0-9]+)\s+([0-9]+)$/) {
                $r = ( $2 == 0 ? 0 : $1 / $2 );
                debug sprintf( "Binary box $k: %d/%d = %.4f\n", $1, $2, $r );
                $ld->{'darkness.data'}->{$k} = [ $2, $1 ];
            }
            if (/^ZOOM\s+(.*)/) {
                $ld->{'zoom.file'}->{$k} = $1;
            }
        }
    }

    return ($r);
}

########################################
# Reads ID (student/page/check) from binary boxes

sub decimal {
    my @ch = (@_);
    my $r  = 0;
    for (@ch) {
        $r = 2 * $r + $_;
    }
    return ($r);
}

sub get_binary_number {
    my ( $process, $ld, $i ) = @_;

    my @ch  = ();
    my $a   = 1;
    my $fin = '';
    do {
        my $k = code_cb( $i, $a );
        if ( $ld->{boxes}->{$k} ) {
            push @ch, ( measure_box( $process, $ld, $k ) > .5 ? 1 : 0 );
            $a++;
        } else {
            $fin = 1;
        }
    } while ( !$fin );
    return ( decimal(@ch) );
}

sub get_id_from_boxes {
    my ( $process, $ld, $data_layout ) = @_;

    my @epc     = map { get_binary_number( $process, $ld, $_ ) } ( 1, 2, 3 );
    my $id_page = "+" . join( '/', @epc ) . "+";
    print "Page : $id_page\n";
    debug("Found binary ID: $id_page");

    $data_layout->begin_read_transaction('cFLY');
    my $ok = $data_layout->exists(@epc);
    $data_layout->end_transaction('cFLY');

    return ( $ok, @epc );
}

sub marks_fit_and_id {
    my ( $process, $ld, $data_layout, $three ) = @_;
    marks_fit( $process, $ld, $three );
    return ( get_id_from_boxes( $process, $ld, $data_layout ) );
}

my $process;
my $temp_loc;
my $temp_dir;
my $commands;

sub one_scan {
    my ( $scan, $allocate, $id_only ) = @_;
    my $sf = $scan;
    if ($project_dir) {
        $sf = abs2proj(
            {
                '%PROJET', $project_dir,
                '%HOME' => $ENV{HOME},
                ''      => '%PROJET',
            },
            $sf
        );
    }

    my $sf_file = $sf;
    $sf_file =~ s:.*/::;
    if ($debug_image_dir) {
        $debug_image = $debug_image_dir . "/$sf_file.png";
    }

    debug "Analysing scan $scan";

    my $data   = AMC::Data->new($data_dir);
    my $layout = $data->module('layout');
    my $capture = $data->module('capture');

    $commands = AMC::Exec::new('AMC-analyse');
    $commands->signalise();

    ##########################################
    # Marks detection
    ##########################################

    my @r;
    my @args = (
        '-x', $random_layout->{width},
        '-y', $random_layout->{height},
        '-d', $random_layout->{markdiameter},
        '-p', $tol_mark_plus,
        '-m', $tol_mark_moins,
        '-c', ( $try_three ? 3 : 4 ),
        '-t', $bw_threshold,
        '-o', ( $debug_image ? $debug_image : 1 )
    );

    push @args, '-P' if ($debug_image);
    push @args, '-r' if ($ignore_red);
    push @args, '-k' if ($debug_pixels);

    $process = AMC::Subprocess::new( mode => 'detect', args => \@args );

    @r = $process->commande( "load " . $scan );
    my @c = ();
    my %warns=();

    for my $l (@r) {
        if ( $l =~ /Frame\[([0-9]+)\]:\s*(-?[0-9.]+)\s*[,;]\s*(-?[0-9.]+)/ ) {
            push @c, $2, $3;
        }
        if ( $l =~ /^\! ([A-Z_]+)/ ) {
            my $k = $1;
            $l =~ s/^\!\s*//;
            $l =~
s/^([A-Z_]+)(.*):\s([^\[]+)( \[.*\]|\.)$/"[$1$2] " . translate_error($1, $3) . $4/e;
            $warns{$k} = $l;
        }
    }

    # if not enough marks are detected, stop the process and report
    # the error (with a different message if the page seems to be
    # blank).
    if ( my $m = $warns{MAYBE_BLANK} || $warns{NMARKS} ) {
        if ($id_only) {
            $process->ferme_commande;
            return (
                {
                    error => $warns{NMARKS},
                    blank => ( $warns{MAYBE_BLANK} ? 1 : 0 )
                }
            );
        } else {
            error(
                $m,
                process         => $process,
                scan            => $scan,
                register_failed => ( $warns{NMARKS} ? $sf : '' ),
            );
            return ();
        }
    }

    my $cadre_general = AMC::Boite::new_complete(@c);

    debug "Global frame:", $cadre_general->txt();

    ##########################################
    # ID detection
    ##########################################

    my @epc;
    my @spc;
    my $upside_down = 0;
    my $ok;

    ( $ok, @epc ) = marks_fit_and_id( $process, $random_layout, $layout );

    if ( $try_three && !$ok ) {

        # now tries with only 3 corner marks:
        ( $ok, @epc ) =
          marks_fit_and_id( $process, $random_layout, $layout, 1 );
    }

    if ( !$ok ) {

        # Unknown ID: tries again upside down
        $process->commande("rotate180");
        ( $ok, @epc ) = marks_fit_and_id( $process, $random_layout, $layout );

        if ( $try_three && !$ok ) {

            # now tries with only 3 corner marks:
            ( $ok, @epc ) =
              marks_fit_and_id( $process, $random_layout, $layout, 1 );
        }

        $upside_down = 1;
    }

    if ( !$ok ) {

        # Failed!

        if ($id_only) {
            $process->ferme_commande;
            return ( { error => 'No layout' } );
        } else {
            error(
                sprintf( "No layout for ID +%d/%d/%d+", @epc ),
                process         => $process,
                scan            => $scan,
                register_failed => $sf,
            );
            return ();
        }
    }

    if ( $ok && $id_only ) {
        $process->ferme_commande;
        return ( { ids => [ $epc[0], $epc[1] ] } );
    }

    command_transf( $process, $random_layout->{transf}, "rotateOK" );

    ##########################################
    # Get all boxes positions from the right page
    ##########################################

    $layout->begin_read_transaction('cELY');
    my $ld = get_layout_data( $layout, @epc[ 0, 1 ], 1 );
    $layout->end_transaction('cELY');

    # But keep all results from binary boxes analysis

    for my $cat (qw/boxes boxes.scan corners.test darkness.data zoom.file/) {
        for my $k ( %{ $random_layout->{$cat} } ) {
            $ld->{$cat}->{$k} = $random_layout->{$cat}->{$k}
              if ( !$ld->{$cat}->{$k} );
        }
    }

    $ld->{transf} = $random_layout->{transf};

    ##########################################
    # Get a free copy number
    ##########################################

    @spc = @epc[ 0, 1 ];
    if ( !$debug_image ) {
        if ($multiple) {
            $capture->begin_transaction('cFCN');
            push @spc, $capture->new_page_copy( @epc[ 0, 1 ], $allocate );
            debug "WARNING: pre-allocation failed. $allocate -> "
              . pageids_string(@spc)
              if ( $pre_allocate && $allocate != $spc[2] );
            $capture->set_page_auto( $sf, @spc, -1, $ld->{transf}->params );
            $capture->end_transaction('cFCN');
        } else {
            push @spc, 0;
        }
    }

    my $zoom_dir = tempdir(
        DIR     => tmpdir(),
        CLEANUP => ( !get_debug() )
    );

    $process->commande("zooms $zoom_dir");

    ##########################################
    # Read darkness data from all boxes
    ##########################################

    for my $k ( keys %{ $ld->{boxes} } ) {
        measure_box( $process, $ld, $k, @spc ) if ( $k =~ /^[0-9]+\.[0-9]+$/ );
    }

    if ($debug_image) {
        error(
            "End of diagnostic",
            silent  => 1,
            process => $process,
            scan    => $scan
        );
        return();
    }

    ##########################################
    # Creates layout image report
    ##########################################

    my $layout_file = "page-" . pageids_string( @spc, path => 1 ) . ".jpg";

    if ($cr_dir) {
        my $out_cadre = "$cr_dir/$layout_file";
        $process->commande( "output " . $out_cadre );
    }

    ##########################################
    # Rotates scan if it is upside-down
    ##########################################

    if ($upside_down) {

        # Rotates the scan file
        print "Rotating...\n";

        $commands->execute( magick_module("convert"),
            "-rotate", "180", $scan, $scan );
    }

    ##########################################
    # Some more image reports
    ##########################################

    my $nom_file =
      "name-" . studentids_string_filename( @spc[ 0, 2 ] ) . ".jpg";

    # Name field sub-image

    if ( $ld->{boxes}->{namefield} ) {
        my $whole_page = magick_perl_module()->new();
        $whole_page->Read($scan);

        my $n = $ld->{boxes}->{namefield}->clone;
        $n->transforme( $ld->{transf} );
        clear_old( 'name image file', "$cr_dir/$nom_file" );

        debug "Name box : " . $n->txt();

        $whole_page->Crop( geometry => $n->etendue_xy( 'geometry', 0 ) );
        debug "Writing to $cr_dir/$nom_file...";
        $whole_page->Write("$cr_dir/$nom_file");
    }

    ##########################################
    # Writes results to the database
    ##########################################

    $capture->begin_transaction('CRSL');
    annotate_source_change($capture);

    if ( $capture->set_page_auto( $sf, @spc, time(), $ld->{transf}->params ) ) {
        debug "Overwritten page data for [SCAN] " . pageids_string(@spc);
        if ($tag_overwritten) {
            $capture->tag_overwritten(@spc);
            print "VAR+: overwritten\n";
        }
    }

    # removes (if exists) old entry in the failed database
    $capture->statement('deleteFailed')->execute($sf);

    $capture->set_layout_image( @spc, $layout_file );

    $cadre_general->to_data( $capture,
        $capture->get_zoneid( @spc, ZONE_FRAME, 0, 0, 1 ), POSITION_BOX );

    for my $k ( keys %{ $ld->{boxes} } ) {
        my $zoneid;
        my ( $n, $i );
        if ( $k =~ /^([0-9]+)\.([0-9]+)$/ ) {
            my $question = $1;
            my $answer   = $2;
            $zoneid =
              $capture->get_zoneid( @spc, ZONE_BOX, $question, $answer, 1 );
            $ld->{'corners.test'}->{$k}
              ->to_data( $capture, $zoneid, POSITION_MEASURE )
              if ( $ld->{'corners.test'}->{$k} );
        } elsif ( ( $n, $i ) = detecte_cb($k) ) {
            $zoneid = $capture->get_zoneid( @spc, ZONE_DIGIT, $n, $i, 1 );
        } elsif ( $k eq 'namefield' ) {
            $zoneid = $capture->get_zoneid( @spc, ZONE_NAME, 0, 0, 1 );
            $capture->set_zone_auto_id( $zoneid, -1, -1, $nom_file, undef );
        }

        if ($zoneid) {
            if ( $k ne 'namefield' ) {
                if ( $ld->{flags}->{$k} & BOX_FLAGS_DONTSCAN ) {
                    debug "Box $k is DONT_SCAN";
                    $capture->set_zone_auto_id( $zoneid, 1, 0, undef, undef );
                } elsif ( $ld->{'darkness.data'}->{$k} ) {
                    $capture->set_zone_auto_id(
                        $zoneid,
                        @{ $ld->{'darkness.data'}->{$k} },
                        undef,
                        (
                            $ld->{'zoom.file'}->{$k}
                            ? file_content(
                                $zoom_dir . "/" . $ld->{'zoom.file'}->{$k}
                              )
                            : undef
                        )
                    );
                } else {
                    debug "No darkness data for box $k";
                }
            }
            if ( $ld->{boxes}->{$k} && !$ld->{'boxes.scan'}->{$k} ) {
                $ld->{'boxes.scan'}->{$k} = $ld->{boxes}->{$k}->clone;
                $ld->{'boxes.scan'}->{$k}->transforme( $ld->{transf} );
            }
            $ld->{'boxes.scan'}->{$k}
              ->to_data( $capture, $zoneid, POSITION_BOX );
        }
    }
    $capture->end_transaction('CRSL');

    $process->ferme_commande();

    $progress_h->progres($delta);
}

sub global_error {
    my ($scans) = @_;
    if ($unlink_on_global_err) {
        for my $s (@$scans) {
            if ( -f $s->{scan} ) {
                debug "Unlink scan: $s->{scan}";
                unlink( $s->{scan} );
            } else {
                debug "Scan to unlink not found: $s->{scan}";
            }
        }
    }
    exit(1);
}

if ( $max_enter > 1 && $multiple ) {

    # photocopy mode, with more than 1 page per student copy: we must
    # check first that we will be able to know which scans belongs to
    # the same student…

    debug "Photocopy mode with $max_enter answers pages";

    my @allocate = ();
    my $scan_i;

    # first read ID from the scans…

    $queue = AMC::Queue::new( 'max.procs', $n_procs, get_returned_values => 1 );

    for my $s (@scans) {
        $queue->add_process( \&one_scan, $s, 0, 1 );
    }

    $queue->run;

    my $scan_ids = $queue->returned_values();

    # merge scan files with result

    for my $i ( 0 .. $#scans ) {
        $scan_ids->[$i]->{scan} = $scans[$i];
    }

    # remove blank scans from list

    $scan_ids = [
        grep {
            if ( $_->{blank} ) {
                debug "Blank page: $_->{scan}";
                if ($unlink_on_global_err) {
                    debug "Unlink scan: $_->{scan}";
                    unlink $_->{scan};
                }
                0;
            } else {
                1;
            }
        } @$scan_ids
    ];

    # Is there any unrecognized scan ? Abort if so.

    my @unrecognized = grep { !defined( $_->{ids} ) } @$scan_ids;
    if (@unrecognized) {
        debug "UNRECOGNIZED:";
        for my $s (@unrecognized) {
            debug $s->{scan};
        }
        print "ERR: "
          # TRANSLATORS: Message displayed when not all scans are recognized (AMC don't know which subject page some scans come from), after automatic data capture.
          . sprintf( __("%d scans are not recognized:"), @unrecognized )."\n";
        for my $i ( 0 .. min( 4, $#unrecognized ) ) {
            print "ERR: " . $unrecognized[$i]->{scan} . "\n";
        }
        print "ERR: ...\n" if ( @unrecognized > 5 );
        global_error($scan_ids);
    }

    # check that the scans are grouped by student copy number, and
    # allocate a copy number.

    my $copy_n       = {};
    my $student_base = {};

    my $capture = $data->module('capture');

    for my $s (@$scan_ids) {
        my ( $student, $page ) = @{ $s->{ids} };
        if ( $copy_n->{$student}->{$page} ) {
            $copy_n->{$student}->{$page}++;
        } else {
            if ( !$student_base->{$student} ) {
                if ($pre_allocate) {
                    $student_base->{$student} = $pre_allocate;
                } else {
                  $capture->begin_read_transaction('StBA');
                  $student_base->{$student} =
                      ($capture->student_last_copy($student) || 0) + 1;
                  $capture->end_transaction('StBA');
                }
            }
            $copy_n->{$student}->{$page} = $student_base->{$student};
        }
        $s->{copy} = $copy_n->{$student}->{$page};
        my $max_for_student = max( values %{ $copy_n->{$student} } );
        debug "Scan $s->{scan} ID="
          . join( "/", @{ $s->{ids} } )
          . " COPY=>$s->{copy}";
        if ( $copy_n->{$student}->{$page} > $max_for_student + 1 ) {
            print "ERR: "
              # TRANSLATORS: Message displayed during automatic data capture with multiple-pages subjects and photocopy mode. AMC encountered another version of page %s but did not see the same number of versions of other pages from the same student.
              . sprintf( __("Too much scans for page %s."), "$student/$page" )
              . "\n";
            print "ERR: $s->{scan}\n";
            global_error($scan_ids);
        }
        if ( $copy_n->{$student}->{$page} < $max_for_student ) {
            print "ERR: "
              . sprintf(
                # TRANSLATORS: Message displayed during automatic data capture with multiple-pages subjects and photocopy mode. AMC encountered another version of page %s but has already processed multiple times other pages from the same student.
                __("One page %s is comming too late."),
                "$student/$page"
              ) . "\n";
            print "ERR: $s->{scan}\n";
            global_error($scan_ids);
        }
    }

    # Chack that we have the same number of copies for each pages of
    # the same student

    my @student_nbfail;
    for my $student ( keys %{$copy_n} ) {
        my $n = undef;
        for my $i ( values %{ $copy_n->{$student} } ) {
            if ( !defined($n) ) {
                $n = $i;
            } elsif ( $i != $n ) {
                push @student_nbfail, $student;
            }
        }
    }
    if (@student_nbfail) {
        print "ERR: "
          # TRANSLATORS: Message displayed during automatic data capture with multiple-pages subjects and photocopy mode.
          . __("You did not provide the same number of copies for all pages.")
          . "\n";
        print "ERR: "
          . __("Student sheet:") . " "
          . join( ',', @student_nbfail ) . "\n";
        global_error($scan_ids);
    }

    # All is OK: we can launch the full data capture!

    $queue = AMC::Queue::new( 'max.procs', $n_procs );

    my $start_copy = max($pre_allocate,0);

    for my $s (@$scan_ids) {
        $queue->add_process( \&one_scan, $s->{scan}, $s->{copy} );
    }

    $queue->run();

} else {

    $queue = AMC::Queue::new( 'max.procs', $n_procs );

    my $scan_i = 0;

    for my $s (@scans) {
        my $a = ( $pre_allocate ? $pre_allocate + $scan_i : 0 );
        debug "Pre-allocate ID=$a for scan $s\n" if ($pre_allocate);
        $queue->add_process( \&one_scan, $s, $a );
        $scan_i++;
    }

    $queue->run();

}

$progress_h->fin();

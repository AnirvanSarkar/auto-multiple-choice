#! /usr/bin/perl
#
# Copyright (C) 2020-2021 Alexis Bienvenüe <paamc@passoire.fr>
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

use AMC::Basic;
use AMC::Data;

use AMC::DataModule::layout ':flags';

my $project_dir  = '.';
my $dest_dir     = '';
my $dpi          = 400;
my $debug        = '';
my $image_format = 'png';
my $get_role     = { BOX_ROLE_QUESTIONTEXT() => 1, BOX_ROLE_ANSWERTEXT() => 1 };
my $get_reponses = 1;
my $margin       = 2;
my $extend       = 6;
my $min_width    = '10cm';

GetOptions(
    "project=s"   => \$project_dir,
    "dpi=s"       => \$dpi,
    "dest=s"      => \$dest_dir,
    "format=s"    => \$image_format,
    "debug=s"     => \$debug,
    "questions!"  => \$get_role->{ BOX_ROLE_QUESTIONTEXT() },
    "answers!"    => \$get_role->{ BOX_ROLE_ANSWERTEXT() },
    "margin=s"    => \$margin,
    "extend=s"    => \$extend,
    "min-width=s" => \$min_width,
);

die "No project dir $project_dir" if ( !-d $project_dir );

my $src_file = "$project_dir/DOC-sujet.pdf";

my %role_name = (
    BOX_ROLE_QUESTIONTEXT() => 'question',
    BOX_ROLE_ANSWERTEXT()   => 'answer',
);

if ( !$dest_dir ) {
    $dest_dir = "$project_dir/text-images";
    mkdir($dest_dir) if ( !-d $dest_dir );
}
die "No dest dir $dest_dir" if ( !-d $dest_dir );

set_debug($debug);

my $data   = AMC::Data->new("$project_dir/data");
my $layout = $data->module('layout');

$layout->begin_read_transaction("TIST");
my @students = $layout->students();
$layout->end_transaction("TIST");

my $tmp_dir = tempdir(
    DIR     => tmpdir(),
    CLEANUP => ( !get_debug() )
);
my $page_file = "$tmp_dir/page.png";

# how much units in one inch ?
my %u_in_one_inch = (
    in => 1,
    cm => 2.54,
    mm => 25.4,
    pt => 72.27,
    sp => 65536 * 72.27,
);

sub read_inches {
    my ($dim) = @_;
    if ( $dim =~ /^\s*([+-]?[0-9]*\.?[0-9]*)\s*([a-zA-Z]+)\s*$/ ) {
        if ( $u_in_one_inch{$2} ) {
            return ( $1 / $u_in_one_inch{$2} );
        } else {
            die "Unknown unity: $2 ($dim)";
        }
    } else {
        die "Unknown dim: $dim";
    }
}

$min_width = read_inches($min_width) * $dpi;

sub image_geometry {
    my ( $i, $mar, $page_dpi, $points ) = @_;
    my $x = {%$i};
    for my $k (qw/xmin xmax ymin ymax/) {
        $x->{$k} = $x->{$k} * $dpi / $page_dpi;
    }
    $mar = $mar * $dpi / $page_dpi;
    if ($points) {
        sprintf(
            "%.2f,%.2f %.2f,%.2f",
            $x->{xmin} - $mar,
            $x->{ymin} - $mar,
            $x->{xmax} + $mar,
            $x->{ymax} + $mar
        );
    } else {
        sprintf(
            "%.2fx%.2f+%.2f+%.2f",
            $x->{xmax} - $x->{xmin} + 2 * $mar,
            $x->{ymax} - $x->{ymin} + 2 * $mar,
            $x->{xmin} - $mar,
            $x->{ymin} - $mar
        );
    }
}

sub enlarge_image {
    my ( $i, $width ) = @_;
    my $w = $i->Get('width');
    if ( $w < $width ) {
        my $h     = $i->Get('height');
        my $white = Graphics::Magick->new();
        $white->Set( size => $width . "x" . $h );
        $white->ReadImage('xc:none');
        $white->Composite( image => $i, compose => "over", gravity => 'West' );
        return ($white);
    } else {
        return ($i);
    }
}

sub extract {
    my ( $base_image, $xy_dpi, $student, $role, $erase, @images ) = @_;
    for my $image (@images) {
        if (   $get_role->{ $image->{role} }
            && $image->{role} == $role )
        {
            my $dest_file =
                $role_name{ $image->{role} } . "-"
              . $student . "-"
              . $image->{question};
            if ( $image->{role} == BOX_ROLE_ANSWERTEXT ) {
                $dest_file .= "-" . $image->{answer};
            }
            $dest_file .= "." . $image_format;

            print
"  - image <$image->{role}> $image->{question} $image->{answer} => $dest_file\n";

            my $i = $base_image->Clone();
            $i->Crop( geometry => image_geometry( $image, $margin, $xy_dpi ) );
            $i->Trim();
            $i->Frame( geometry => $extend . 'x' . $extend, fill => 'white' );
            $i->Set( density => $dpi . "x" . $dpi );
            enlarge_image( $i, $min_width )->Write("$dest_dir/$dest_file");

            if ($erase) {
                $base_image->Draw(
                    primitive => 'rectangle',
                    fill      => 'white',
                    stroke    => 'none',
                    points    => image_geometry( $image, $margin, $xy_dpi, 1 )
                );
            }
        }
    }
}

for my $student (@students) {
    print "Student $student\n";
    $layout->begin_read_transaction("TIPI");
    my @pages = $layout->pages_info_for_student($student);
    $layout->end_transaction("TIPI");
    for my $page (@pages) {
        print "- page $page->{page} => $page->{subjectpage}\n";
        $layout->begin_read_transaction("TIPA");
        my @images = $layout->type_info( 'text', $student, $page->{page} );
        $layout->end_transaction("TIPA");

        if (@images) {
            my @cmd = (
                "gs",
                "-sDEVICE=png16m",
                "-sOutputFile=$page_file",
                "-dFirstPage=$page->{subjectpage}",
                "-dLastPage=$page->{subjectpage}",
                "-r$dpi",
                "-dTextAlphaBits=4",
                "-dGraphicsAlphaBits=4",
                "-dNOPAUSE",
                "-dSAFER",
                "-dBATCH"
            );
            push @cmd, "-dQUIET" if ( !$debug );
            system_debug( cmd => [ @cmd, $src_file ], die_on_error => 1 );

            my $whole_page = magick_perl_module()->new();
            $whole_page->Read($page_file);

            extract( $whole_page, $page->{dpi}, $student, BOX_ROLE_ANSWERTEXT,
                1, @images );
            extract( $whole_page, $page->{dpi}, $student,
                BOX_ROLE_QUESTIONTEXT, 0, @images );

        }
    }
}

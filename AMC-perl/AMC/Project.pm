# -*- perl -*-
#
# Copyright (C) 2021-2022 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::Project;

use File::Temp qw/ tempfile tempdir :seekable /;

use AMC::Basic;
use AMC::Data;
use AMC::NamesFile;

sub new {
    my ( $class, %oo ) = @_;

    my $self = { config=>'', gui=>'' };

    for ( keys %oo ) {
        $self->{$_} = $oo{$_} if ( exists( $self->{$_} ) );
    }

    bless( $self, $class );

    $self->{cmd_id}   = 0;
    $self->{commands} = {};

    return $self;
}

sub set {
    my ($self, $k, $value) = @_;
    $self->{$k} = $value;
}

sub name {
    my ($self) = @_;
    return ( $self->{_name} );
}

sub data {
    my ($self) = @_;
    return ( $self->{_data} );
}

sub layout {
    my ($self) = @_;
    return ( $self->{_layout} );
}

sub capture {
    my ($self) = @_;
    return ( $self->{_capture} );
}

sub scoring {
    my ($self) = @_;
    return ( $self->{_scoring} );
}

sub association {
    my ($self) = @_;
    return ( $self->{_association} );
}

sub report {
    my ($self) = @_;
    return ( $self->{_report} );
}

sub students_list {
    my ($self) = @_;
    return ( $self->{_students_list} );
}

sub set_students_list {
    my ( $self, $path ) = @_;

    $self->{_students_list} = AMC::NamesFile::new(
        $path,
        encodage    => $self->bon_encodage('liste'),
        identifiant => $self->csv_build_name(),
    );

    return ( $self->{_students_list}->errors() );
}

sub open {
    my ( $self, $proj, $texsrc, $progress ) = @_;

    # creates (if missing) project directory structure

    for my $sous ( '',
        qw:cr cr/corrections cr/corrections/jpg cr/corrections/pdf cr/zooms cr/diagnostic data scans exports anonymous:
      )
    {
        my $rep = $self->{config}->get('rep_projets') . "/$proj/$sous";
        if ( !-x $rep ) {
            debug "Creating directory $rep...";
            mkdir($rep);
        }
    }

    $self->{_name} = $proj;
    $self->{config}->{shortcuts}->set( project_name => $proj );

    $self->{config}->open_project($proj);
    $self->{config}->set( 'project:texsrc', $texsrc )
      if ( $texsrc && !$self->{config}->get('project:texsrc') );

    $self->{_name} = $proj;

    $self->{_data} =
      AMC::Data->new( $self->{config}->get_absolute('data'), progress => $progress );
    for (qw/layout capture scoring association report/) {
        $self->{ '_' . $_ } = $self->{_data}->module($_);
    }

    $self->{_students_list} = AMC::NamesFile::new();

}

sub close {
    my ($self) = @_;
    for my $i (qw/name students_list
                  data layout capture scoring association report/) {
        $self->{ "_" . $i } = '';
    }
}

sub project_options {
    my ($self) = @_;
    $self->{config}->save();
    return (
        "--profile-conf", $self->{config}->{global_file},
        "--project-dir",  $self->{config}->{shortcuts}->absolu('%PROJET/')
    );
}

sub commande {
    my ( $self, @opts ) = @_;
    $self->{cmd_id}++;

    my $c = AMC::Gui::Commande::new(
        avancement =>
          ( $self->{gui} ? $self->{gui}->get_ui('avancement') : '' ),
        log  => ( $self->{gui} ? $self->{gui}->get_ui('log_general') : '' ),
        finw => sub {
            my $c = shift;
            if ( $self->{gui} ) {
                $self->{gui}->get_ui('onglets_projet')->set_sensitive(1);
                $self->{gui}->get_ui('commande')->hide();
            }
            delete $self->{commands}->{ $c->{_cmdid} };
        },
        @opts
    );

    $c->{_cmdid} = $self->{cmd_id};
    $self->{commands}->{ $self->{cmd_id} } = $c;

    if ( $self->{gui} ) {
        $self->{gui}->get_ui('onglets_projet')->set_sensitive(0);
        $self->{gui}->get_ui('commande')->show();
    }

    $c->open();
}

sub commande_annule {
    my ($self) = @_;
    for ( values %{ $self->{commands} } ) { $_->quitte(); }
}

sub export {
    my ($self, $opts) = @_;
    $self->commande(
        commande => [
            "auto-multiple-choice",
            "export",
            "--debug",
            debug_file(),
            pack_args(
                $self->project_options(),
                "--module", $opts->{format},
                "--output", $opts->{output},
                @{ $opts->{o} },
              ),
        ],
        texte           => __ "Exporting marks...",
        'progres.id'    => 'export',
        'progres.pulse' => 0.01,
        fin             => $opts->{callback},
        o               => $opts,
    );
}

sub update_document {
    my ( $self, $mode, %oo ) = @_;

    $self->commande(
        commande => [
            "auto-multiple-choice",
            "prepare",
            "--debug",
            debug_file(),
            pack_args(
                $self->project_options(),
                "--mode", $mode,
                "--latex-stdout",
              )
        ],
        signal          => 2,
        texte           => __ "Documents update...",
        'progres.id'    => 'MAJ',
        'progres.pulse' => 0.01,
        fin             => $oo{callback},
        o               => \%oo
    );
}

sub data_capture_detect_pdfform {
    my ( $self, %oo ) = @_;

    # make temporary file with the list of images to analyse
    my $fh = File::Temp->new(
        TEMPLATE => "liste-XXXXXX",
        TMPDIR   => 1,
        UNLINK   => ( get_debug() ? 0 : 1 )
    );
    binmode $fh, ":utf8";
    print $fh join( "\n", sort { $a cmp $b } @{ $oo{f} } ) . "\n";
    $fh->seek( 0, SEEK_END );

    # first try to see if some of the files are PDF forms

    $oo{fh}    = $fh;
    $oo{liste} = $fh->filename;

    $self->commande(
        commande => [
            "auto-multiple-choice",
            "read-pdfform",
            "--debug",
            debug_file(),
            pack_args(
                $self->project_options(),
                "--progression-id", 'analyse',
                "--list", $fh->filename,
            )
        ],
        signal       => 2,
        o            => \%oo,
        fin          => $oo{callback},
        'progres.id' => $oo{progres},
    );
}

sub data_capture_get_images {
    my ( $self, %oo ) = @_;

    # extract individual images scans

    if ( $oo{getimages} ) {
        my @args = (
            $self->project_options(),
            "--progression-id", 'analyse',
            "--list", $oo{fh}->filename,
        );
        push @args, "--copy-to", $oo{copy} if ( $oo{copy} );
        $self->{_layout}->begin_transaction('Orie');
        my $orientation = $self->{_layout}->orientation();
        $self->{_layout}->end_transaction('Orie');
        push @args, "--orientation", $orientation if ($orientation);

        debug "Target orientation: $orientation";

        $self->commande(
            commande => [
                "auto-multiple-choice", "getimages",
                "--debug",              debug_file(),
                pack_args(@args)
            ],
            signal       => 2,
            'progres.id' => $oo{progres},
            o            => \%oo,
            fin          => $oo{callback}
        );
    } else {
        &{ $oo{callback} }( $oo{callback_self}, { o=> \%oo } );
    }
}

sub data_capture_from_images {
    my ( $self, %oo ) = @_;
    my @args = (
        $self->project_options(),
        "--progression-id", 'analyse',
        "--progression", 1,
        "--liste-fichiers", $oo{liste},
    );

    push @args, "--pre-allocate", $oo{allocate} if ( $oo{allocate} );

    push @args, "--unlink-on-global-err" if ( $oo{copy} );

    # Diagnostic image file ?

    if ( $oo{diagnostic} ) {
        push @args, "--debug-image-dir",
          $self->{config}->{shortcuts}->absolu('%PROJET/cr/diagnostic');
        push @args, "--no-tag-overwritten";
    }

    # call AMC-analyse

    $self->commande(
        commande => [
            "auto-multiple-choice", "analyse",
            "--debug",              debug_file(),
            pack_args(@args)
        ],
        signal       => 2,
        texte        => $oo{text},
        'progres.id' => $oo{progres},
        o            => \%oo,
        fin          => $oo{callback},
    );
}

sub decode_name_fields {
    my ( $self, %oo ) = @_;

    $self->commande(
        commande => [
            "auto-multiple-choice",
            "decode",
            "--debug",
            debug_file(),
            pack_args(
                $self->project_options(),
                ( $oo{all} ? "--all" : "--no-all" ),
                "--progression-id", 'decode',
                "--progression", 1,
            ),
        ],
        signal       => 2,
        texte        => __ "Decoding name field images...",
        'progres.id' => 'decode',
        o            => \%oo,
        fin          => $oo{callback},
    );
}

sub bon_encodage {
    my ( $self, $type ) = @_;
    return ( $self->{config}->bon_encodage($type) );
}

sub csv_build_name {
    my ( $self, @args ) = @_;
    return ( $self->{config}->csv_build_name(@args) );
}

# Get the number of copies used to build the working documents
sub original_n_copies {
    my ($self) = @_;
    my $n = $self->{_layout}->variable_transaction('build:ncopies');
    if ( defined($n) && $n ne '' ) {
        $n = 0 if ( $n eq 'default' );
    } else {

        # Documents were built with an older AMC version: use value from GUI
        $n = $self->{config}->get('nombre_copies');
    }
    return ($n);
}

sub moteur_latex {
    my ($self) = @_;
    return ( $self->{config}->moteur_latex() );
}

sub annotate {
    my ( $self, %oo ) = @_;
    my $single_output = '';

    if ( $self->{config}->get('regroupement_type') eq 'ALL' ) {
        $single_output = (
            $oo{id_file}
            ?

              __(
                # TRANSLATORS: File name for single annotated
                # answer sheets with only some selected
                # students. Please use simple characters.
                "Selected_students"
              )
              . ".pdf"
            :

              __(
                # TRANSLATORS: File name for single annotated
                # answer sheets with all students. Please use
                # simple characters.
                "All_students"
              )
              . ".pdf"
        );
    }

    $self->commande(
        commande => [
            "auto-multiple-choice",
            "annotate",
            "--debug",
            debug_file(),
            pack_args(
                $self->project_options(),
                "--single-output", $single_output,
                "--id-file", $oo{id_file},
                "--progression-id", 'annotate',
                "--progression", 1,
                "--changes-only",
                "--n-copies", $self->original_n_copies(),
            )
        ],
        texte        => __ "Annotating papers...",
        'progres.id' => 'annotate',
        o            => \%oo,
        fin          => $oo{callback},
    );
}

sub auto_association {
    my ( $self, %oo ) = @_;

    $self->commande(
        commande => [
            "auto-multiple-choice", "association-auto",
            "--debug",              debug_file(),
            pack_args( $self->project_options() ),
          ],
        texte => __ "Automatic association...",
        o     => \%oo,
        fin   => $oo{callback},
    );
}

sub project_extract_with {
    my ($self) = @_;
    my $conf = $self->{config}->get('print_extract_with');
    if ( $self->{config}->get('project:pdfform') ) {
        if ( $conf =~ /^(qpdf|sejda|pdftk\+NA)/ ) {
            return ($conf);
        } else {
            if ( commande_accessible('sejda-console') ) {
                return ('sejda-console');
            } elsif ( commande_accessible('qpdf') ) {
                return ('qpdf');
            } else {
                return ('pdftk+NA');
            }
        }
    } else {
        return ($conf);
    }
}

sub print_exams {
    my ( $self, %oo ) = @_;

    my $fh = File::Temp->new(
        TEMPLATE => "nums-XXXXXX",
        TMPDIR   => 1,
        UNLINK   => 1
    );
    print $fh join( "\n", @{ $oo{exams} } ) . "\n";
    $fh->seek( 0, SEEK_END );

    my $directory =
      $self->{config}->get_absolute('options_impression/repertoire');
    debug "Directory: " . show_utf8($directory);
    my $prefix = __p("sheet [filename prefix when printing to files]");
    if ( $self->{config}->get('code_examen') ) {
        $prefix = $self->{config}->get('code_examen');
    }
    debug "Prefix: " . show_utf8($prefix);

    $self->commande(
        commande => [
            "auto-multiple-choice",
            "imprime",
            "--debug",
            debug_file(),
            pack_args(
                $self->project_options(),
                "--methode", $oo{printing_method},
                "--options", $oo{options_string},
                "--output", "$directory/$prefix-%e.pdf",
                "--progression-id", 'impression',
                "--progression", 1,
                "--fich-numeros", $fh->filename,
            ),
        ],
        quiet_regex  => 'Discarded not relevant field',
        signal       => 2,
        texte        => __ "Print papers one by one...",
        'progres.id' => 'impression',
        o            => {
            fh            => $fh,
            etu           => $oo{exams},
            printer       => $self->{config}->get('imprimante'),
            method        => $oo{method},
            callback_self => $oo{callback_self},
        },
        fin => $oo{callback},
    );
}

sub detect_layout {
    my ( $self, %oo ) = @_;

    $self->commande(
        commande => [
            "auto-multiple-choice",
            "meptex",
            "--debug",
            debug_file(),
            pack_args(
                $self->project_options(),
                "--progression-id", 'MEP',
                "--progression", 1,
            ),
        ],
        texte        => __ "Detecting layouts...",
        'progres.id' => 'MEP',
        o            => \%oo,
        fin          => $oo{callback},
    );

}

sub scoring_strategy_update {
    my ( $self, $with_indiv_solution, %command_opts ) = @_;

    my $mode          = "b";
    my $pdf_corrected = $self->{config}->get_absolute('doc_indiv_solution');
    if ( $with_indiv_solution && -f $pdf_corrected ) {
        debug "Removing pre-existing $pdf_corrected";
        unlink($pdf_corrected);
    }
    $mode .= 'k' if ( $with_indiv_solution );

    $self->commande(
        commande => [
            "auto-multiple-choice",
            "prepare",
            "--debug",
            debug_file(),
            pack_args(
                $self->project_options(),
                "--n-copies", $self->original_n_copies(),
                "--progression-id", 'bareme',
                "--progression", 1,
                "--mode", $mode,
            ),
        ],
        texte        => __ "Extracting marking scale...",
        'progres.id' => 'bareme',
        %command_opts
    );
}

sub compute_marks {
    my ( $self, %oo ) = @_;

    my $postcorrect_student = '';
    my $postcorrect_copy = '';
    my $postcorrect_set_multiple = '';

    if ( $oo{postcorrect} ) {
        ( $postcorrect_student, $postcorrect_copy, $postcorrect_set_multiple )
          = @{ $oo{postcorrect} };
    }

    debug
"Using sheet $postcorrect_student:$postcorrect_copy to get correct answers"
      if ($postcorrect_student);

    # computes marks.

    $self->commande(
        commande => [
            "auto-multiple-choice",
            "note",
            "--debug",
            debug_file(),
            pack_args(
                $self->project_options(),
                "--postcorrect-student", $postcorrect_student,
                "--postcorrect-copy", $postcorrect_copy,
                (
                    $postcorrect_set_multiple ? "--postcorrect-set-multiple"
                    : "--no-postcorrect-set-multiple"
                ),
                "--progression-id", 'notation',
                "--progression", 1,
            ),
        ],
        signal       => 2,
        texte => ( $oo{gather_multi}
            ? __("Reading codes...")
            : __("Computing marks...") ),
        'progres.id' => 'notation',
        o            => \%oo,
        fin          => $oo{callback},
    );
}

sub gather_multicode {
    my ( $self, %oo ) = @_;
    $self->commande(
        commande => [
            "auto-multiple-choice",
            "gathermulticode",
            "--debug",
            debug_file(),
            pack_args(
                $self->project_options(),
                "--progression-id", 'gathermulticode',
                "--progression",    1,
            ),
        ],
        signal       => 2,
        texte        => __ "Gathering pages with the same code...",
        'progres.id' => 'gathermulticode',
        o            => \%oo,
        fin          => $oo{callback},
    );
}

sub project_email_name {
    my ($self, $markup) = @_;
    my $pn =
      (      $self->{config}->get('nom_examen')
          || $self->{config}->get('code_examen')
          || $self->name );
    if ($markup) {
        return ( $pn eq $self->name ? "<b>$pn</b>" : $pn );
    } else {
        return ($pn);
    }
}

sub mailing {
    my ( $self, %oo ) = @_;

    # writes the list of copies to send in a temporary file
    my $fh = File::Temp->new(
        TEMPLATE => "ids-XXXXXX",
        TMPDIR   => 1,
        UNLINK   => 10
    );
    print $fh join( "\n", @{ $oo{ids} } ) . "\n";
    $fh->seek( 0, SEEK_END );

    my @mailing_args = (
        "--project-name", $self->project_email_name(),
        "--ids-file", $fh->filename,
        "--report", $oo{kind},
        "--subject", $self->{config}->get("project:$oo{kind_s}/email_subject"),
        "--text", $self->{config}->get("project:$oo{kind_s}/email_text"),
        "--text-content-type",
        (
            $self->{config}->get("project:$oo{kind_s}/email_use_html")
            ? 'text/html'
            : 'text/plain'
        ),
    );

    for ( @{ $self->{config}->get("project:$oo{kind_s}/email_attachment") } ) {
        push @mailing_args, "--attach",
          $self->{config}->{shortcuts}->absolu($_);
    }

    $self->commande(
        commande => [
            "auto-multiple-choice",
            "mailing",
            "--debug",
            debug_file(),
            pack_args(
                $self->project_options(),
                @mailing_args,
                "--progression-id", 'mailing',
                "--progression", 1,
                "--log", $self->{config}->{shortcuts}->absolu('mailing.log'),
            ),
        ],
        'progres.id' => 'mailing',
        texte        => __ "Sending emails...",
        o            => { fh => $fh, %oo },
        fin          => $oo{callback}
    );
}

sub anonymize {
    my ( $self, %oo ) = @_;

    $self->commande(
        commande => [
            "auto-multiple-choice",
            "annotate",
            "--debug", debug_file(),
            pack_args(
                $self->project_options(),
                "--progression-id", 'annotate',
                "--progression", 1,
                "--verdict", $self->{config}->get('anonymous_header'),
                ($self->{config}->get('anonymous_header_allpages') ?
                   "--verdict-allpages" : "--no-verdict-allpages"),
                "--changes-only", 1,
                "--n-copies", $self->original_n_copies(),

                "--filename-model", "(aID)",
                "--single-output", '',
                "--compose", 0,
                "--pdf-dir", $self->{config}->{shortcuts}->absolu('%PROJET/anonymous'),
                "--header-only",
                "--anonymous", $self->{config}->get('anonymous_model'),
            ),
        ],
        texte => __ "Anonymizing...",
        o     => \%oo,
        fin   => $oo{callback},
    );
}

sub get_external_scores {
    my ( $self, %oo ) = @_;

    $self->commande(
        commande => [
            "auto-multiple-choice",
            "external",
            "--debug", debug_file(),
            pack_args(
                $self->project_options(),
                "--source", $oo{source}
            ),
        ],
        signal       => 2,
        texte        => __ "Reading external scores...",
        o            => \%oo,
        fin          => $oo{callback},
    );
}

1;

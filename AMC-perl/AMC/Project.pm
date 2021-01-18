# -*- perl -*-
#
# Copyright (C) 2021 Alexis Bienvenue <paamc@passoire.fr>
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
        qw:cr cr/corrections cr/corrections/jpg cr/corrections/pdf cr/zooms cr/diagnostic data scans exports:
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
                "--module",
                $opts->{format},
                "--data",
                $self->{config}->get_absolute('data'),
                "--useall",
                $self->{config}->get('export_include_abs'),
                "--sort",
                $self->{config}->get('export_sort'),
                "--fich-noms",
                $self->{config}->get_absolute('listeetudiants'),
                "--noms-encodage",
                $self->bon_encodage('liste'),
                "--csv-build-name",
                $self->csv_build_name(),
                ( $self->{config}->get('annote_rtl') ? "--rtl" : "--no-rtl" ),
                "--output",
                $opts->{output},
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
                "--with",
                $self->moteur_latex(),
                "--filter",
                $self->{config}->get('filter'),
                "--filtered-source",
                $self->{config}->get_absolute('filtered_source'),
                "--out-sujet",
                $self->{config}->get_absolute('doc_question'),
                "--out-corrige",
                $self->{config}->get_absolute('doc_solution'),
                "--out-corrige-indiv",
                $self->{config}->get_absolute('doc_indiv_solution'),
                "--out-catalog",
                $self->{config}->get_absolute('doc_catalog'),
                "--out-calage",
                $self->{config}->get_absolute('doc_setting'),
                "--mode",
                $mode,
                "--n-copies",
                $self->{config}->get('nombre_copies'),
                $self->{config}->get_absolute('texsrc'),
                "--prefix",
                $self->{config}->{shortcuts}->absolu('%PROJET/'),
                "--latex-stdout",
                "--data",
                $self->{config}->get_absolute('data'),
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
                "--progression-id",
                'analyse',
                "--list",
                $fh->filename,
                (
                    $self->{config}->get('auto_capture_mode')
                    ? "--multiple"
                    : "--no-multiple"
                ),
                "--data",
                $self->{config}->get_absolute('data'),
                "--password",
                $self->{config}->get('pdf_password')
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
            "--progression-id", 'analyse',
            "--list",           $oo{fh}->filename,
            "--vector-density", $self->{config}->get('vector_scan_density'),
            "--password",       $self->{config}->get('pdf_password'),
        );
        push @args, "--copy-to", $oo{copy} if ( $oo{copy} );
        push @args, "--force-convert"
          if ( $self->{config}->get("force_convert") );
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
        (
            $self->{config}->get('auto_capture_mode') ? "--multiple"
            : "--no-multiple"
        ),
        "--tol-marque",
        $self->{config}->get('tolerance_marque_inf') . ','
          . $self->{config}->get('tolerance_marque_sup'),
        "--prop",
        $self->{config}->get('box_size_proportion'),
        "--bw-threshold",
        $self->{config}->get('bw_threshold'),
        "--progression-id",
        'analyse',
        "--progression",
        1,
        "--n-procs",
        $self->{config}->get('n_procs'),
        "--data",
        $self->{config}->get_absolute('data'),
        "--projet",
        $self->{config}->{shortcuts}->absolu('%PROJET/'),
        "--cr",
        $self->{config}->get_absolute('cr'),
        "--liste-fichiers",
        $oo{liste},
        (
            $self->{config}->get('ignore_red') ? "--ignore-red"
            : "--no-ignore-red"
        ),
        (
            $self->{config}->get('try_three') ? "--try-three"
            : "--no-try-three"
        ),
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
                "--data",
                $self->{config}->get_absolute('data'),
                "--cr",
                $self->{config}->get_absolute('cr'),
                "--project",
                $self->{config}->{shortcuts}->absolu('%PROJET/'),
                ( $oo{all} ? "--all" : "--no-all" ),
                "--decoder",
                $self->{config}->get('name_field_type'),
                "--progression-id",
                'decode',
                "--progression",
                1,
            ),
        ],
        signal       => 2,
        texte        => __ "Decoding name field images...",
        'progres.id' => 'decode',
        o            => \%oo,
        fin          => $oo{callback},
    );
}

sub opt_symbole {
    my ( $self, $s ) = @_;
    my $k = $s;

    $k =~ s/-/_/g;
    my $type  = $self->{config}->get( 'symbole_' . $k . '_type',  'none' );
    my $color = $self->{config}->get( 'symbole_' . $k . '_color', 'red' );

    return ("$s:$type/$color");
}

sub bon_encodage {
    my ( $self, $type ) = @_;
    return ( $self->{config}->get("encodage_$type")
          || $self->{config}->get("defaut_encodage_$type")
          || "UTF-8" );
}

sub csv_build_0 {
    my ( $self, $k, @default ) = @_;
    push @default, grep { $_ } map { s/^\s+//; s/\s+$//; $_; }
      split( /,+/, $self->{config}->get( 'csv_' . $k . '_headers' ) );
    return ( "(" . join( "|", @default ) . ")" );
}

sub csv_build_name {
    my ($self) = @_;
    return ($self->csv_build_0( 'surname', 'nom', 'surname' ) . ' '
          . $self->csv_build_0( 'name', 'prenom', 'name' ) );
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
    return ( $self->{config}->get('moteur_latex_b')
          || $self->{config}->get('defaut_moteur_latex_b') );
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
                "--cr",
                $self->{config}->get_absolute('cr'),
                "--project",
                $self->{config}->{shortcuts}->absolu('%PROJET/'),
                "--projects",
                $self->{config}->{shortcuts}->absolu('%PROJETS/'),
                "--data",
                $self->{config}->get_absolute('data'),
                "--subject",
                $self->{config}->get_absolute('doc_question'),
                "--corrected",
                $self->{config}->get_absolute('doc_indiv_solution'),
                "--filename-model",
                $self->{config}->get('modele_regroupement'),
                (
                    $self->{config}->get('ascii_filenames') ? "--force-ascii"
                    : "--no-force-ascii"
                ),
                "--single-output",
                $single_output,
                "--sort",
                $self->{config}->get('export_sort'),
                "--id-file",
                $oo{id_file},
                "--progression-id",
                'annotate',
                "--progression",
                1,
                "--line-width",
                $self->{config}->get('symboles_trait'),
                "--font-name",
                $self->{config}->get('annote_font_name'),
                "--symbols",
                join( ',', map { $self->opt_symbole($_); } (qw/0-0 0-1 1-0 1-1/) ),
                (
                    $self->{config}->get('symboles_indicatives')
                    ? "--indicatives"
                    : "--no-indicatives"
                ),
                "--position",
                $self->{config}->get('annote_position'),
                "--dist-to-box",
                $self->{config}->get('annote_ecart'),
                "--n-digits",
                $self->{config}->get('annote_chsign'),
                "--verdict",
                $self->{config}->get('verdict'),
                "--verdict-question",
                $self->{config}->get('verdict_q'),
                "--verdict-question-cancelled",
                $self->{config}->get('verdict_qc'),
                "--names-file",
                $self->{config}->get_absolute('listeetudiants'),
                "--names-encoding",
                $self->bon_encodage('liste'),
                "--csv-build-name",
                $self->csv_build_name(),
                ( $self->{config}->get('annote_rtl') ? "--rtl" : "--no-rtl" ),
                "--changes-only",
                1, "--sort",
                $self->{config}->get('export_sort'),
                "--compose",
                $self->{config}->get('regroupement_compose'),
                "--n-copies",
                $self->original_n_copies(),
                "--src",
                $self->{config}->get_absolute('texsrc'),
                "--with",
                $self->moteur_latex(),
                "--filter",
                $self->{config}->get('filter'),
                "--filtered-source",
                $self->{config}->get_absolute('filtered_source'),
                "--embedded-max-size",
                $self->{config}->get('embedded_max_size'),
                "--embedded-format",
                $self->{config}->get('embedded_format'),
                "--embedded-jpeg-quality",
                $self->{config}->get('embedded_jpeg_quality'),
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
            "auto-multiple-choice",
            "association-auto",
            "--debug",
            debug_file(),
            pack_args(
                "--data",
                $self->{config}->get_absolute('data'),
                "--notes-id",
                $self->{config}->get('assoc_code'),
                "--liste",
                $self->{config}->get_absolute('listeetudiants'),
                "--liste-key",
                $self->{config}->get('liste_key'),
                "--csv-build-name",
                $self->csv_build_name(),
                "--encodage-liste",
                $self->bon_encodage('liste'),
                (
                    $self->{config}->get('assoc_code') eq '<preassoc>'
                    ? "--pre-association"
                    : "--no-pre-association"
                ),
            ),
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

    my @o_answer = ( '--no-split', '--no-answer-first' );
    if ( $self->{config}->get('options_impression/print_answersheet') eq
        'split' )
    {
        @o_answer = ( '--split', '--no-answer-first' );
    } elsif ( $self->{config}->get('options_impression/print_answersheet') eq
        'first' )
    {
        @o_answer = ( '--answer-first', '--no-split' );
    }

    my $extract_with = $self->project_extract_with();

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
                "--methode",
                $oo{printing_method},
                "--imprimante",
                $self->{config}->get('imprimante'),
                "--options",
                $oo{options_string},
                "--output",
                "$directory/$prefix-%e.pdf",
                @o_answer,
                "--print-command",
                $self->{config}->get('print_command_pdf'),
                "--sujet",
                $self->{config}->get_absolute('doc_question'),
                "--data",
                $self->{config}->get_absolute('data'),
                "--progression-id",
                'impression',
                "--progression",
                1,
                "--fich-numeros",
                $fh->filename,
                "--extract-with",
                $extract_with,
                "--password",
                (
                      $self->{config}->get('pdf_password_use')
                    ? $self->{config}->get('pdf_password')
                    : ""
                ),
                "--students-list",
                $self->{config}->get_absolute('listeetudiants'),
                "--list-key",
                $self->{config}->get('liste_key'),
                "--password-key",
                $self->{config}->get('pdf_password_key'),
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
                "--src",
                $self->{config}->get_absolute('doc_setting'),
                "--progression-id",
                'MEP',
                "--progression",
                1,
                "--data",
                $self->{config}->get_absolute('data'),
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
                "--out-corrige-indiv",
                $pdf_corrected,
                "--n-copies",
                $self->original_n_copies(),
                "--with",
                $self->moteur_latex(),
                "--filter",
                $self->{config}->get('filter'),
                "--filtered-source",
                $self->{config}->get_absolute('filtered_source'),
                "--progression-id",
                'bareme',
                "--progression",
                1,
                "--data",
                $self->{config}->get_absolute('data'),
                "--mode",
                $mode,
                $self->{config}->get_absolute('texsrc'),
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
                "--data",     $self->{config}->get_absolute('data'),
                "--seuil",    $self->{config}->get('seuil'),
                "--seuil-up", $self->{config}->get('seuil_up'),

                "--grain",
                $self->{config}->get('note_grain'),
                "--arrondi",
                $self->{config}->get('note_arrondi'),
                "--notemax",
                $self->{config}->get('note_max'),
                (
                    $self->{config}->get('note_max_plafond') ? "--plafond"
                    : "--no-plafond"
                ),
                "--notenull",
                $self->{config}->get('note_null'),
                "--notemin",
                $self->{config}->get('note_min'),
                "--postcorrect-student",
                $postcorrect_student,
                "--postcorrect-copy",
                $postcorrect_copy,
                (
                    $postcorrect_set_multiple ? "--postcorrect-set-multiple"
                    : "--no-postcorrect-set-multiple"
                ),

                "--progression-id",
                'notation',
                "--progression",
                1,
            ),
        ],
        signal       => 2,
        texte        => __ "Computing marks...",
        'progres.id' => 'notation',
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
        "--project",
        $self->{config}->{shortcuts}->absolu('%PROJET/'),
        "--project-name",
        $self->project_email_name(),
        "--students-list",
        $self->{config}->get_absolute('listeetudiants'),
        "--preassoc-key",
        $self->{config}->get('liste_key'),
        "--list-encoding",
        $self->bon_encodage('liste'),
        "--csv-build-name",
        $self->csv_build_name(),
        "--ids-file",
        $fh->filename,
        "--report",
        $oo{kind},
        "--email-column",
        $self->{config}->get('email_col'),
        "--sender",
        $self->{config}->get('email_sender'),
        "--subject",
        $self->{config}->get("project:$oo{kind_s}/email_subject"),
        "--text",
        $self->{config}->get("project:$oo{kind_s}/email_text"),
        "--text-content-type",
        (
            $self->{config}->get("project:$oo{kind_s}/email_use_html")
            ? 'text/html'
            : 'text/plain'
        ),
        "--transport",
        $self->{config}->get('email_transport'),
        "--sendmail-path",
        $self->{config}->get('email_sendmail_path'),
        "--smtp-host",
        $self->{config}->get('email_smtp_host'),
        "--smtp-port",
        $self->{config}->get('email_smtp_port'),
        "--smtp-ssl",
        $self->{config}->get('email_smtp_ssl'),
        "--smtp-user",
        $self->{config}->get('email_smtp_user'),
        "--smtp-passwd-file",
        $self->{config}->passwd_file("SMTP"),
        "--cc",
        $self->{config}->get('email_cc'),
        "--bcc",
        $self->{config}->get('email_bcc'),
        "--delay",
        $self->{config}->get('email_delay'),
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
                @mailing_args,
                "--progression-id",
                'mailing',
                "--progression",
                1,
                "--log",
                $self->{config}->{shortcuts}->absolu('mailing.log'),
            ),
        ],
        'progres.id' => 'mailing',
        texte        => __ "Sending emails...",
        o            => { fh => $fh, %oo },
        fin          => $oo{callback}
    );
}

1;

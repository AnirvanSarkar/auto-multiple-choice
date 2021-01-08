# -*- perl -*-
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

package AMC::Gui::Printing;

use parent 'AMC::Gui';

use AMC::Basic;

use Module::Load;
use Data::Dumper;

use constant { COPIE_N => 0, };

use_gettext();

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            layout         => '',
            callback_self  => '',
            print_callback => sub { debug "Warning: missing print_callback"; },
        },
        %oo
    );

    $self->store_register(

        print_answersheet => cb_model(
            '' => __
              # TRANSLATORS: One of the way to handle separate answer
              # sheet when printing: standard (same as in the question
              # pdf document). This is a menu entry.
              "Standard",

            split => __
              # TRANSLATORS: One of the way to handle separate answer
              # sheet when printing: print separately answer sheet and
              # question. This is a menu entry.
              "Separate answer sheet",

            first => __
              # TRANSLATORS: One of the way to handle separate answer sheet when
              # printing: print the answr sheet first. This is a menu entry.
              "Answer sheet first"
        ),

        sides => cb_model(
            'one-sided',
            __p(
                # TRANSLATORS: you can omit the [...] part, just here to
                # explain context
                "one sided [No two-sided printing]"
            ),

            'two-sided-long-edge',
            __(
                # TRANSLATORS: One of the two-side printing
                # types. This is a menu entry.
                "long edge"
            ),

            'two-sided-short-edge',
            __(
                # TRANSLATORS: One of the two-side printing
                # types. This is a menu entry.
                "short edge"
            )
        ),
    );
    $self->dialog();

    return $self;
}

# Prepares the window for printing options

sub dialog {
    my ($self) = @_;

    $self->set_env();

    debug "Printing method: $self->{method}";

    return () if ( $self->check_layout() || $self->check_cups() );

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade(
        $glade_xml, qw/choix_pages_impression
          arbre_choix_copies bloc_imprimante answersheet_box
          imprimante printing_options_table bloc_fichier
          impfp_cb_pdf_password_use impfp_x_pdf_password
          options_pdf_passwords/
    );

    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'impall',
        root   => "options_impression"
    );

    if ( $self->{method} =~ /^CUPS/ ) {
        $self->dialog_cups();
    } else {
        $self->get_ui('bloc_imprimante')->hide();
    }
    if ( $self->{method} eq 'file' ) {
        $self->dialog_file();
    } else {
        $self->get_ui('bloc_fichier')->hide();
    }

    $self->dialog_copies_list();

}

# get the printing method, that is forced to be 'to files' when pdfform
# is used

sub printing_method {
    my ($self) = @_;

    if ( $self->get('project:pdfform') ) {
        return ('file');
    } else {
        return ( $self->get("methode_impression") );
    }
}

# detect environment

sub set_env {
    my ($self) = @_;

    $self->{layout}->begin_read_transaction('PGCN');
    $self->{students_count} = $self->{layout}->students_count;
    $self->{pages_count}    = $self->{layout}->pages_count;
    $self->{preassoc}       = $self->{layout}->pre_association()
      && $self->get('listeetudiants');
    $self->{layout}->end_transaction('PGCN');

    $self->{options_string} = '';
    $self->{method} = $self->printing_method();
}

# Check that the layout is properly detected, so that the question is
# ready to be printed. Return TRUE on "error"

sub check_layout {
    my ($self) = @_;

    if ( !-f $self->get_absolute('doc_question') ) {
        my $dialog = Gtk3::MessageDialog->new( $self->{parent_window},
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup(
            __(
             # TRANSLATORS: Message when the user required printing the question
             # paper, but it is not present (probably the working documents have
             # not been properly generated).
              "You don't have any question to print:"
              . " please check your source file and update working documents first.")
        );
        $dialog->run;
        $dialog->destroy;

        return (1);
    }

    if ( $self->{pages_count} == 0 ) {
        my $dialog = Gtk3::MessageDialog->new( $self->{parent_window},
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup(
            __(
           # TRANSLATORS: Message when AMC does not know about the subject pages
           # that has been generated. Usualy this means that the layout
           # computation step has not been made.
                "Question's pages are not detected."
              )
              . " "
              . __ "Perhaps you forgot to compute layouts?"
        );
        $dialog->run;
        $dialog->destroy;

        return (1);
    }
    return (0);
}

# Check that CUPS is available, with at least one printer. Return TRUE if not.

sub check_cups {
    my ($self) = @_;

    return (0) if ( $self->{method} !~ /^CUPS/ );

    my $print_module = "AMC::Print::" . lc( $self->{method} );
    load($print_module);

    # checks for availibility

    my $error = $print_module->check_available();
    if ($error) {
        my $dialog = Gtk3::MessageDialog->new(
            $self->{parent_window},
            'destroy-with-parent',
            'error', 'ok',
            sprintf(
                __(
"You chose the printing method '%s' but it is not available (%s). Please install the missing dependencies or switch to another printing method."
                ),
                $self->{method},
                $error
            )
        );
        $dialog->run;
        $dialog->destroy;

        return (1);
    }

    $self->{print_object} = $print_module->new(
        useful_options => $self->get("printer_useful_options") );

    # check for a installed printer

    debug "Checking for at least one CUPS printer...";

    my $default_printer = $self->{print_object}->default_printer();

    if ( !$default_printer ) {
        my $dialog = Gtk3::MessageDialog->new(
            $self->{parent_window},
            'destroy-with-parent',
            'error', 'ok',
            __(
"You chose a printing method using CUPS but there are no configured printer in CUPS. Please configure some printer or switch to another printing method."
            )
        );
        $dialog->run;
        $dialog->destroy;

        return (1);
    }
}

# Prepare the specific options using CUPS

sub dialog_cups {
    my ($self) = @_;

    $self->get_ui('bloc_imprimante')->show();

    # Printers

    my @printers = $self->{print_object}->printers_list();
    debug "Printers : " . join( ' ', map { $_->{name} } @printers );
    my $p_model =
      cb_model( map { $_->{name} => $self->{print_object}->printer_text($_) }
          @printers );
    $self->get_ui('imprimante')->set_model($p_model);
    if ( !$self->get('imprimante') ) {
        my $defaut = $self->{print_object}->default_printer;
        if ($defaut) {
            $self->set( 'imprimante', $defaut );
        } else {
            $self->set( 'imprimante', $printers[0]->{name} );
        }
    }
    my $i =
      model_id_to_iter( $p_model, COMBO_ID, $self->get('imprimante') );
    if ($i) {
        $self->get_ui('imprimante')->set_active_iter($i);

        # (this will call autre_imprimante and transmet_pref with
        # the right options)
    } else {

        # updates the values in the GUI from the general options
        $self->{prefs}->transmet_pref(
            $self->{main},
            prefix => 'imp',
            root   => 'options_impression'
        );
    }
}

# Prepares the specific options when printing to files

sub dialog_file {
    my ($self) = @_;

    $self->get_ui('bloc_imprimante')->hide();
    $self->get_ui('bloc_fichier')->show();

    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'impf',
        root   => 'options_impression'
    );
    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'impfp',
        root   => "project:",
    );
    if ( $self->{preassoc} ) {
        $self->get_ui('options_pdf_passwords')->show();
    } else {
        $self->get_ui('options_pdf_passwords')->hide();
    }
}

sub pdf_password_key_update {
    my ($self) = @_;
    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'impfpu',
        keys   => ['pdf_password_key'],
    );
}

# prepare the list of available copies

sub dialog_copies_list {
    my ($self) = @_;

    $self->{store} = Gtk3::ListStore->new('Glib::String');
    $self->{layout}->begin_read_transaction('PRNT');
    my $row = 0;
    for my $c ( $self->{layout}->students() ) {
        $self->{store}->insert_with_values( $row++, COPIE_N, $c );
    }
    $self->{layout}->end_transaction('PRNT');

    $self->get_ui('arbre_choix_copies')->set_model( $self->{store} );

    my $renderer = Gtk3::CellRendererText->new;

    my $column =

      Gtk3::TreeViewColumn->new_with_attributes(
        __(
           # TRANSLATORS: This is the title of the column containing the paper's
           # numbers (1,2,3,...) in the table showing all available papers, from
           # which the user will choose those he wants to print.
            "papers"
        ),
        $renderer,
        text => COPIE_N
      );
    $self->get_ui('arbre_choix_copies')->append_column($column);
    $self->get_ui('arbre_choix_copies')->get_selection->set_mode("multiple");

    $self->get_ui('choix_pages_impression')->show();
}

sub printer_change {
    my ($self) = @_;

    my ( $ok, $imp_iter ) = $self->get_ui('imprimante')->get_active_iter;
    if ($ok) {
        my $i =
          $self->get_ui('imprimante')->get_model->get( $imp_iter, COMBO_ID );
        debug "Printer: $i";

        $self->set( "global:options_impression/printer", {} )
          if ( !$self->get("options_impression/printer") );
        my $printer_settings =
          $self->get("options_impression/printer");

        $printer_settings->{$i} = {}
          if ( !$printer_settings->{$i} );

        $self->{print_object}->printer_options_table(
            $self->get_ui('printing_options_table'),
            $self->{ui},
            $self->{prefs}, $i, $printer_settings->{$i}
        );

        $self->{prefs}->transmet_pref(
            $self->{main},
            prefix => 'imp',
            root   => 'options_impression'
        );
        $self->{prefs}->transmet_pref(
            $self->{main},
            prefix => 'printer',
            root   => "options_impression/printer/$i"
        );
    } else {
        debug "No printer choice!";
    }

}

sub random_password {
    my ($self) = @_;

    my $p     = '';
    my @chars = split( //,
        "0123456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ_-+." );
    for ( 0 .. 12 ) {
        $p .= $chars[ rand( 1 + $#chars ) ];
    }
    return ($p);
}

sub pdf_password_toggle {
    my ($self) = @_;

    $self->{prefs}->reprend_pref( prefix => 'impfp' );
    my $u = $self->get('pdf_password_use');
    if ($u) {
        if ( !$self->get('pdf_password') ) {
            $self->set( 'pdf_password', $self->random_password() );
            $self->{prefs}->transmet_pref(
                $self->{main},
                prefix => 'impfp',
                keys   => ['pdf_password'],
            );
        }
    }
    $self->get_ui('impfp_x_pdf_password')->set_sensitive($u);
}

# cancel callback

sub cancel {
    my ($self) = @_;

    if ( get_debug() ) {
        $self->{prefs}->reprend_pref( prefix => 'imp' );
        $Data::Dumper::Indent = 0;
        debug( Dumper( $self->get('options_impression') ) );
    }

    $self->get_ui('choix_pages_impression')->destroy;
}

# ok callback

sub ok {
    my ($self) = @_;

    # Get the list of selected copies

    my @e = ();

    my @selected =
      $self->get_ui('arbre_choix_copies')->get_selection()->get_selected_rows();
    for my $i ( @{ $selected[0] } ) {
        push @e, $self->{store}->get( $self->{store}->get_iter($i), COPIE_N )
          if ($i);
    }

    $self->{prefs}->reprend_pref( prefix => 'impall' );

    # get back CUPS printing options

    $self->get_options_cups();

    # get back file printing options

    $self->get_options_file();

    # Quit dialog

    $self->get_ui('choix_pages_impression')->destroy;

    debug "Printing: " . join( ",", @e );

    # Message if no exam was selected

    if ( !@e ) {

        # No page selected:
        my $dialog = Gtk3::MessageDialog->new( $self->{parent_window},
            'destroy-with-parent',
            'info', 'ok', __("You did not select any exam to print...") );
        $dialog->run;
        $dialog->destroy;
        return ();
    }

    # If a little exams were selected, ask if they are going to be
    # photocopied

    if ( @e <= 10 ) {
        if ( $self->{students_count} <= 10 && !$self->{preassoc} ) {
            $self->ask_for_photocopy_mode();
        }
    }

    # The option 'print asnwer sheet first' needs one of the
    # extracting commands [qpdf, pdftk, sedja-console]

    if ( $self->get('options_impression/print_answersheet') eq
        'first' )
    {
        return ()
          if (
            !$self->needs_extract_with(
                __("Answer sheet first"),
                qw/qpdf pdftk sedja-console/
            )
          );
    }

    # Ask for printing the exams!

    &{ $self->{print_callback} }(
        $self->{callback_self},
        {
            printing_method => $self->{method},
            options_string  => $self->{options_string},
            exams           => \@e
        }
    );

}

# Get back 'print via CUPS' options from dialog.

sub get_options_cups {
    my ($self) = @_;

    if ( $self->{method} =~ /^CUPS/ ) {
        my ( $ok, $imp_iter ) = $self->get_ui('imprimante')->get_active_iter;
        my $i;
        if ($ok) {
            $i = $self->get_ui('imprimante')
              ->get_model->get( $imp_iter, COMBO_ID );
        } else {
            $i = 'default';
        }
        $self->set( 'imprimante', $i );

        $self->{prefs}->reprend_pref( prefix => 'imp' );
        $self->{prefs}->reprend_pref( prefix => 'printer' );

        my $os =
          $self->options_string( $self->get("options_impression"),
            $self->get("options_impression/printer")->{$i} );

        $self->{options_string} = $os;

        debug("Printing options : $os");
    }
}

sub options_strings {
    my ( $self, $o ) = @_;
    return (
        map { $_ . "=" . $o->{$_} }
          grep {
                 !/^_/
              && !/^(repertoire|print_answersheet)$/
              && exists( $o->{$_} )
              && $o->{$_}
              && !ref( $o->{$_} )
          } ( keys %$o )
    );
}

sub options_string {
    my ( $self, @oos ) = @_;
    return ( join( ',', map { $self->options_strings($_) } (@oos) ) );
}

# Get back 'print to file'  options from dialog

sub get_options_file {
    my ($self) = @_;

    if ( $self->{method} eq 'file' ) {
        $self->{prefs}->reprend_pref( prefix => 'impf' );
        $self->{prefs}->reprend_pref( prefix => 'impfp' );
        if ( $self->{preassoc} ) {
            $self->{prefs}->reprend_pref( prefix => 'impfpu' );
        }
        if ( !$self->get('options_impression/repertoire') ) {
            debug "Print to file : no destination...";
            $self->set( 'options_impression/repertoire', '' );
        } else {
            my $path =
              $self->get_absolute('options_impression/repertoire');
            mkdir($path) if ( !-e $path );
        }
    }
}

# Propose to switch to photocopy mode if not already selected

sub ask_for_photocopy_mode {
    my ($self) = @_;

    if ( $self->get('auto_capture_mode') != 1 ) {
        my $dialog = Gtk3::MessageDialog->new( $self->{parent_window},
            'destroy-with-parent', 'question', 'yes-no', '' );
        $dialog->set_markup(
            __("You selected only a few sheets to print.") . "\n" . "<b>"
              . __(
"Are you going to photocopy some printed subjects before giving them to the students?"
              )
              . "</b>\n"
              . __(
                "If so, the corresponding option will be set for this project.")
              . " "
              . __(
"However, you will be able to change this when giving your first scans to AMC."
              )
        );
        my $reponse = $dialog->run;
        $dialog->destroy;
        my $mult = ( $reponse eq 'yes' ? 1 : 0 );
        $self->set( 'auto_capture_mode', $mult );
    }
}

# Restrict the extract command to be in a given set of allowed
# values. Return TRUE if this is possible.

sub needs_extract_with {
    my ( $self, $option_name, @allowed ) = @_;

    my $allowed_re = '(' . join( "|", @allowed ) . ")";

    my $found;

    if ( $self->get('print_extract_with') =~ /$allowed_re/ ) {
        $found = 1;
    } else {
        $found = 0;
      EXTRACT: for my $cmd (@allowed) {
            if ( commande_accessible($cmd) ) {
                my $dialog = Gtk3::MessageDialog->new( $self->{parent_window},
                    'destroy-with-parent', 'info', 'ok', '' );
                $dialog->set_markup(

                    sprintf(
                        __(
               # TRANSLATORS: %1$s and %3$s will be replaced by the
               # translations of "Answer sheet first" and "Extracting
               # method". %2$s (and %4$s) is a possible value of the "extracting
               # method" that needs to be used when "Answer sheet
               # first" is choosen
                            "You selected the '%1\$s' option, that uses '%2\$s',"
                              . " so the %3\$s has been set to '%4\$s' for you."
                        ),
                        $option_name,
                        $cmd,
                        __("Extracting method"),
                        $cmd
                    )
                );
                $dialog->run;
                $dialog->destroy;

                $self->set( "print_extract_with", $cmd );
                $found = 1;
                last EXTRACT;
            }
        }

        # No available command from the allowed set : cancel printing!

        if ( !$found ) {
            my $dialog = Gtk3::MessageDialog->new( $self->{parent_window},
                'destroy-with-parent', 'error', 'ok', '' );
            $dialog->set_markup(
                sprintf(
                    __(
"You selected the '%s' option, but this option needs %s"." to be installed on your system. Please install one of these and try again."
                    ),
                    $option_name,
                    $self->say_all( "'", @allowed )
                )
            );
            $dialog->run;
            $dialog->destroy;
        }
    }

    return ($found);
}

sub all_quoted {
    my ( $self, $quotechar, @items ) = @_;

    if ( @items == 1 ) {
        return ( $quotechar . $items[0] . $quotechar );
    } else {
        my $last = pop @items;
        return (
            join( ", ", map { "$quotechar$_$quotechar" } @items ) . " " . __(
                # TRANSLATORS: word between the last two options in an
                # enumeration. You can remove the [enumeration] part."
                "or [enumeration]"
              )
              . " $quotechar$last$quotechar"
        );
    }

}

1;

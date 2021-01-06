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

package AMC::Gui::Preferences;

use parent 'AMC::Gui';

use AMC::Basic;

use Module::Load;
use Module::Load::Conditional qw/check_install/;

my @widgets_disabled_when_preferences_opened = (qw/menu_popover/);

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            open_project_name        => '',
            widgets                  => '',
            capture                  => '',
            callback_self            => '',
            decode_callback          => '',
            detect_analysis_callback => '',
        },
        %oo
    );

    $self->stores();
    $self->dialog();

    return $self;
}

sub printing_methods {
    my ($self) = @_;

    my @printing_methods = ();
    for my $m (
        { name => "CUPS",   description => "CUPS" },
        { name => "CUPSlp", description => "CUPS (via lp)" },
      )
    {
        my $mod = "AMC::Print::" . lc( $m->{name} );
        load($mod);
        my $error = $mod->check_available();
        if ( !$error ) {
            push @printing_methods, $m->{name}, $m->{description};
            if ( !$self->get("methode_impression") ) {
                $self->set( "global:methode_impression", $m->{name} );
                debug "Switching to printing method <$m->{name}>.";
            }
        } else {
            if ( $self->get("methode_impression") eq $m->{name} ) {
                $self->set( "global:methode_impression", '' );
                debug "Printing method <$m->{name}> is not available: $error";
            }
        }
    }
    if ( !$self->get("methode_impression") ) {
        $self->set( "global:methode_impression", 'commande' );
        debug "Switching to printing method <commande>.";
    }

    push @printing_methods,
        'commande', __(
            # TRANSLATORS: One of the printing methods: use a command
            # (This is not the command name itself). This is a menu
            # entry.
            "command"),
        'file', __(
            # TRANSLATORS: One of the printing methods: print to
            # files. This is a menu entry.
            "to files");

    return (@printing_methods);
}

sub stores {
    my ($self) = @_;

    # Reads decoders list and build ComboBox model.

    my @decoders = perl_module_search('AMC::Decoder::register');
    for my $m (@decoders) {
        load("AMC::Decoder::register::$m");
    }
    @decoders = sort {
        "AMC::Decoder::register::$a"->weight <=>
          "AMC::Decoder::register::$b"->weight
    } @decoders;

    my $nftype_store = cb_model(
        '' => __ "Image",
        map { $_ => "AMC::Decoder::register::$_"->name() } (@decoders)
    );

    my $rounding_store = cb_model(
        'inf',
        __(
            # TRANSLATORS: One of the rounding method for marks. This
            # is a menu entry.
            "floor"
        ),
        'normal',
        __(
            # TRANSLATORS: One of the rounding method for marks. This
            # is a menu entry.
            "rounding"
        ),
        'sup',
        __(
            # TRANSLATORS: One of the rounding method for marks. This
            # is a menu entry.
            "ceiling"
        )
    );

    $self->store_register(
        encodage_latex => cb_model(
            map { $_->{iso} => $_->{txt} } (AMC::Encodings::encodings())
        ),

        delimiteur_decimal => cb_model(
            ',',
            __(
                # TRANSLATORS: One option for decimal point: use a
                # comma. This is a menu entry
                ", (comma)"
            ),

            '.',
            __(
                # TRANSLATORS: One option for decimal point: use a
                # point. This is a menu entry.
                ". (dot)"
            )
          ),
        methode_impression => cb_model( $self->printing_methods ),
        print_extract_with => cb_model(
            pdftk           => 'pdftk',
            gs              => 'gs (ghostscript)',
            qpdf            => 'qpdf',
            'sejda-console' => 'sejda-console',
        ),

        manuel_image_type => cb_model(
            ppm =>
            __p(
                # TRANSLATORS: you can omit the [...] part, just here to
                # explain context
                "(none) [No transitional image type (direct processing)]"),
            xpm => 'XPM',
            gif => 'GIF'
        ),
        defaut_name_field_type => $nftype_store,
        name_field_type        => $nftype_store,
        note_arrondi           => $rounding_store,
        defaut_note_arrondi    => $rounding_store,
        embedded_format        => cb_model(
            png  => 'PNG',
            jpeg => 'JPEG'
        ),
        email_transport => cb_model(
            sendmail => __(
                # TRANSLATORS: One of the ways to send mail: use sendmail
                # command. This is a menu entry.
                "sendmail"
            ),

            SMTP => __(
                # TRANSLATORS: One of the ways to send mail: use a
                # SMTP server. This is a menu entry.
                "SMTP"
            )
          ),

        email_smtp_ssl => cb_model(
            0        => __p(
                # TRANSLATORS: SMTP security mode: None (nor SSL nor
                # STARTTLS)
                "None [SMTP security]"),
            1        => 'SSL',
            starttls => 'STARTTLS'
        ),

        annote_position => cb_model(
            none =>
            __p(
                # TRANSLATORS: you can omit the [...] part, just here to
                # explain context
                "(none) [No annotation position (do not write anything)]"),

            marge => __(
                # TRANSLATORS: One of the possible location for
                # questions scores on annotated completed answer
                # sheet: in one margin. This is a menu entry.
                "in one margin"),

            marges => __(
                # TRANSLATORS: One of the possible location for
                # questions scores on annotated completed answer
                # sheet: in one of the two margins. This is a menu
                # entry.
                "in the margins"),

            case => __(
                # TRANSLATORS: One of the possible location for
                # questions scores on annotated completed answer
                # sheet: near the boxes. This is a menu entry.
                "near boxes"),

            zones => __(
                # TRANSLATORS: One of the possible location for
                # questions scores on annotated completed answer
                # sheet: in the zones defined in the source file
                "where defined in the source"),
        ),
    );

    my $symbole_type_cb = cb_model(
        none => __(
            # TRANSLATORS: One of the signs that can be drawn on
            # annotated answer sheets to tell if boxes are to be
            # ticked or not, and if they were detected as ticked or
            # not.
            "nothing"),

        circle => __(
            # TRANSLATORS: One of the signs that can be drawn on
            # annotated answer sheets to tell if boxes are to be
            # ticked or not, and if they were detected as ticked or
            # not.
            "circle"),

        mark => __(
            # TRANSLATORS: One of the signs that can be drawn on
            # annotated answer sheets to tell if boxes are to be
            # ticked or not, and if they were detected as ticked or
            # not. Here, a cross.
            "mark"),

        box => __(
            # TRANSLATORS: One of the signs that can be drawn on
            # annotated answer sheets to tell if boxes are to be
            # ticked or not, and if they were detected as ticked or
            # not. Here, the box outline.
            "box"),
    );

    for my $k (qw/0_0 0_1 1_0 1_1/) {
        $self->store_register( "symbole_" . $k . "_type" => $symbole_type_cb );
    }

}

sub dialog {
    my ($self) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->dependent_widgets_sensitivity(0);

    $self->read_glade(
        $glade_xml, qw/edit_preferences
          pref_projet_tous pref_projet_annonce
          pref_x_print_command_pdf pref_c_methode_impression
          email_group_sendmail email_group_SMTP/
    );

    # copy tooltip from note_* to defaut_note_*
    my $marking_prefs = {
        min         => 'x',
        max         => 'x',
        null        => 'x',
        grain       => 'x',
        max_plafond => 'v',
        arrondi     => 'c'
    };
    for my $k ( keys %$marking_prefs ) {
        $self->{main}
          ->get_object( "pref_" . $marking_prefs->{$k} . "_defaut_note_$k" )
          ->set_tooltip_text(
            $self->{main}->get_object(
                "pref_projet_" . $marking_prefs->{$k} . "_note_$k"
            )->get_tooltip_text
          );
    }

    # tableau type/couleurs pour correction

    $self->{prefs}->widget_store_clear( store => 'prefwindow' );

    $self->{prefs}->transmet_pref(
        $self->{main},
        store  => 'prefwindow',
        prefix => 'pref',
        root   => 'global:'
    );

    if ( $self->{open_project_name} ) {
        $self->{prefs}->transmet_pref(
            $self->{main},
            store  => 'prefwindow_project',
            prefix => 'pref_projet',
            root   => 'project:'
        );
        $self->get_ui('pref_projet_annonce')->set_label(
            '<i>'
              . sprintf(
                __ "Project \"%s\" preferences",
                $self->{open_project_name}
              )
              . '</i>.'
        );
    } else {
        $self->get_ui('pref_projet_tous')->set_sensitive(0);
        $self->get_ui('pref_projet_annonce')
          ->set_label( '<i>' . __("Project preferences") . '</i>' );
    }

    # unavailable options, managed by the filter:
    if ( $self->get('filter') ) {
        for
          my $k ( ( "AMC::Filter::register::" . $self->get('filter') )
            ->forced_options() )
        {
          TYPES: for my $t (qw/c cb ce col f s t v x/) {
                if ( my $w =
                    $self->{main}->get_object( "pref_projet_" . $t . "_" . $k )
                  )
                {
                    $w->set_sensitive(0);
                    last TYPES;
                }
            }
        }
    }

    $self->change_methode_impression();

    my $resp = $self->get_ui('edit_preferences')->run();

    if ($resp) {
        $self->accept();
    } else {
        $self->cancel();
    }

}

sub change_methode_impression {
    my ($self) = @_;

    if ( $self->get_ui('pref_x_print_command_pdf') ) {
        my $m = '';
        my ( $ok, $iter ) =
          $self->get_ui('pref_c_methode_impression')->get_active_iter;
        if ($ok) {
            $m =
              $self->get_ui('pref_c_methode_impression')
              ->get_model->get( $iter, COMBO_ID );
        }
        $self->get_ui('pref_x_print_command_pdf')
          ->set_sensitive( $m eq 'commande' );
    }
}

sub change_delivery {
    my ($self) = @_;

    $self->set_local_keys('email_transport');
    $self->{prefs}->reprend_pref(
        store     => 'prefwindow',
        prefix    => 'pref',
        container => 'local'
    );
    my $transport = $self->get('local:email_transport');
    if ($transport) {
        for my $k (qw/sendmail SMTP/) {
            $self->get_ui( 'email_group_' . $k )
              ->set_sensitive( $k eq $transport );
        }
    } else {
        debug "WARNING: could not retrieve email_transport!";
    }
}

sub dependent_widgets_sensitivity {
    my ( $self, $sensitive ) = @_;

    for my $k (@widgets_disabled_when_preferences_opened) {
        $self->{widgets}->{$k}->set_sensitive($sensitive);
    }
}

sub close_dialog {
    my ($self) = @_;

    $self->get_ui('edit_preferences')->destroy();
    $self->dependent_widgets_sensitivity(1);
}

sub cancel {
    my ($self) = @_;

    $self->close_dialog();
}

sub accept {
    my ($self) = @_;

    $self->{prefs}->reprend_pref( store => 'prefwindow', prefix => 'pref' );
    $self->{prefs}->reprend_pref(
        store  => 'prefwindow_project',
        prefix => 'pref_projet'
    ) if ( $self->{open_project_name} );

    my %pm;
    my %gm;
    my @dgm;
    my %labels;

    if ( $self->{open_project_name} ) {
        %pm = map { $_ => 1 } ( $self->{config}->changed_keys('project') );
        %gm = map { $_ => 1 } ( $self->{config}->changed_keys('global') );
        @dgm = grep { /^defaut_/ } ( keys %gm );

        for my $k (@dgm) {
            my $l = $self->{main}->get_object( 'label_' . $k );
            $labels{$k} = $l->get_text() if ($l);
            my $kp = $k;
            $kp =~ s/^defaut_//;
            $l = $self->{main}->get_object( 'label_' . $kp );
            $labels{$kp} = $l->get_text() if ($l);
        }
    }

    $self->close_dialog();

    if ( $self->{open_project_name} ) {

        # Check if annotations are still valid (same options)

        my $changed = 0;
        for (
            qw/annote_chsign symboles_trait
            embedded_format embedded_max_size embedded_jpeg_quality
            symboles_indicatives annote_font_name annote_ecart/
          )
        {
            $changed = 1 if ( $gm{$_} );
        }
        for my $tag (qw/0_0 0_1 1_0 1_1/) {
            $changed = 1
              if ( $gm{ "symbole_" . $tag . "_type" }
                || $gm{ "symbole_" . $tag . "_color" } );
        }
        for (qw/annote_position verdict verdict_q annote_rtl/) {
            $changed = 1 if ( $pm{$_} );
        }

        if ($changed) {
            annotate_source_change( $self->{capture}, 1 );
        }

        # Look at modified default values...

        debug "Labels: " . join( ',', keys %labels );

        for my $k (@dgm) {
            my $kp = $k;
            $kp =~ s/^defaut_//;

            debug "Test G:$k / P:$kp";
            if (   ( !$pm{$kp} )
                && ( $self->get($kp) ne $self->get($k) ) )
            {

                # project option has NOT been modified, and the new
                # value of general default option is different from
                # project option. Ask the user for modifying also the
                # project option value
                my $label_projet  = $labels{$kp};
                my $label_general = $labels{$k};

                debug "Ask user $label_general | $label_projet";

                if ( $label_projet && $label_general ) {
                    my $dialog =
                      Gtk3::MessageDialog->new( $self->{parent_window},
                        'destroy-with-parent', 'question', 'yes-no', '' );
                    $dialog->set_markup(
                        sprintf(
                            __(
"You modified \"<b>%s</b>\" value, which is the default value used when creating new projects. Do you want to change also \"<b>%s</b>\" for the opened <i>%s</i> project?"
                            ),
                            $label_general,
                            $label_projet,
                            $self->{open_project_name}
                        )
                    );
                    $dialog->get_widget_for_response('yes')
                      ->get_style_context()->add_class("suggested-action");
                    my $reponse = $dialog->run;
                    $dialog->destroy;

                    debug "Reponse: $reponse";

                    if ( $reponse eq 'yes' ) {

                        # change also project option value
                        $self->set( $kp, $self->get($k) );
                    }

                }
            }
        }

        # Run again decoding if the name field type has changed

        if ( $pm{name_field_type} ) {
            my $response;

            if ( $self->get('name_field_type') ) {
                my $dialog = Gtk3::MessageDialog->new( $self->{parent_window},
                    'destroy-with-parent', 'question', 'ok-cancel', '' );
                $dialog->set_markup(
                    __(
"You modified the name field type, so that the name fields has to be decoded again."
                    )
                );
                $dialog->get_widget_for_response('ok')->get_style_context()
                  ->add_class("suggested-action");
                $response = $dialog->run;
                $dialog->destroy;
            } else {
                $response = 'ok';
            }
            if ( $response eq 'ok' ) {
                &{ $self->{decode_callback} }( $self->{callback_self} );
            }
        }

        for my $k (qw/note_null note_min note_max note_grain/) {
            my $v = $self->get($k);
            $v =~ s/\s+//g;
            $self->set( $k, $v );
        }
    }

    if ( $self->{config}->key_changed("projects_home")
        && !$self->{open_project_name} )
    {
        $self->{config}
          ->set_projects_home( $self->get_absolute('projects_home') );
    }

    $self->{config}->test_commands();

    if (   $self->{config}->key_changed("seuil")
        || $self->{config}->key_changed("seuil_up") )
    {
        if ( $self->{capture}->n_pages_transaction() > 0 ) {
            &{ $self->{detect_analysis_callback} }( $self->{callback_self} );
        }
    }

    $self->{config}->save();
}

1;

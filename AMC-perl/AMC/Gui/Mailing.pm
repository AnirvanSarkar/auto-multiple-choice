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

package AMC::Gui::Mailing;

use parent 'AMC::Gui';

use AMC::Basic;
use AMC::DataModule::report ':const';

use Gtk3;
use Module::Load;
use Module::Load::Conditional qw/check_install/;

use constant {
    ATTACHMENTS_FILE       => 0,
    ATTACHMENTS_NAME       => 1,
    ATTACHMENTS_FOREGROUND => 2,

    EMAILS_SC     => 0,
    EMAILS_NAME   => 1,
    EMAILS_EMAIL  => 2,
    EMAILS_ID     => 3,
    EMAILS_STATUS => 4,
};

use_gettext;

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            kind          => '',
            kind_s        => '',
            project_name  => '',
            report        => '',
            capture       => '',
            association   => '',
            students_list => '',
        },
        %oo
    );

    return $self;
}

sub hex_color {
    my $s = shift;
    return ( Gtk3::Gdk::Color::parse($s)->to_string() );
}

sub dialog {
    my ($self) = @_;

    if ( $self->{kind} == REPORT_PRINTED_COPY ) {
    }
    
    if ( $self->{kind} == REPORT_ANNOTATED_PDF ) {
        return() if(!$self->check_for_annotated_pdf());
    }

    return() if(!$self->check_for_perl_modules());

    load Email::Address;

    return() if(!$self->check_for_sender_address());

    if ( $self->get('email_transport') eq 'sendmail' ) {
        return () if ( !$self->check_for_sendmail() );
    }
    
    my ($col_max, @cols) = $self->email_columns();

    $self->store_register( email_col => cb_model( map { $_ => $_ } (@cols) ) );

    if ( !$col_max ) {
        my $dialog = Gtk3::MessageDialog->new(
            $self->{parent_window},
            'destroy-with-parent',
            'error',
            'ok',
            __
"No email addresses has been found in the students list file. You need to write the students addresses in a column of this file."
        );
        $dialog->run;
        $dialog->destroy;

        return ();
    }

    $self->set( 'project:email_col', $col_max )
      if ( !$self->get('email_col') );

    # Launch dialog!
    
    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade(
        $glade_xml, qw/email_dialog
          emails_list email_dialog label_name
          attachments_list attachments_expander/
    );

    $self->get_ui('label_name')->set_text( $self->project_name() );

    my $renderer;
    my $column;
    my $attachments_list = $self->get_ui('attachments_list');
    my $attachments_store =
        Gtk3::ListStore->new( 'Glib::String', 'Glib::String', 'Glib::String', );
    $self->{attachments_store}=$attachments_store;

    $attachments_list->set_model($attachments_store);
    $renderer = Gtk3::CellRendererText->new;

    $column = Gtk3::TreeViewColumn->new_with_attributes(
        __
        # TRANSLATORS: This is the title of a column containing attachments
        # file paths in a table showing all attachments, when sending them to
        # the students by email.
        "file",
        $renderer,
        text       => ATTACHMENTS_NAME,
        foreground => ATTACHMENTS_FOREGROUND,
    );
    $attachments_list->append_column($column);

    $attachments_list->set_tooltip_column(ATTACHMENTS_FILE);
    $attachments_list->get_selection->set_mode('multiple');

    #

    my $emails_list = $self->get_ui('emails_list');
    my $emails_store = Gtk3::ListStore->new(
        'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String',
        'Glib::String',
        );
    $self->{emails_store}=$emails_store;
    $emails_list->set_model($emails_store);
    $renderer = Gtk3::CellRendererText->new;

    $column = Gtk3::TreeViewColumn->new_with_attributes(
        __(
          # TRANSLATORS: This is the title of a column containing copy numbers
          # in a table showing all annotated answer sheets, when sending them to
          # the students by email.
            "copy"
        ),
        $renderer,
        text => EMAILS_SC
    );
    $emails_list->append_column($column);
    $renderer = Gtk3::CellRendererText->new;

    $column = Gtk3::TreeViewColumn->new_with_attributes(
        __(
          # TRANSLATORS: This is the title of a column containing students names
          # in a table showing all annotated answer sheets, when sending them to
          # the students by email.
            "name"
        ),
        $renderer,
        text => EMAILS_NAME
    );
    $emails_list->append_column($column);
    $renderer = Gtk3::CellRendererText->new;

    $column = Gtk3::TreeViewColumn->new_with_attributes(
        __(
          # TRANSLATORS: This is the title of a column containing students email
          # addresses in a table showing all annotated answer sheets, when
          # sending them to the students by email.
            "email"
        ),
        $renderer,
        text => EMAILS_EMAIL
    );
    $emails_list->append_column($column);
    $renderer = Gtk3::CellRendererText->new;

    $column = Gtk3::TreeViewColumn->new_with_attributes(
        __(
          # TRANSLATORS: This is the title of a column containing mailing status
          # (not sent, already sent, failed) in a table showing all annotated
          # answer sheets, when sending them to the students by email.
            "status"
        ),
        $renderer,
        text => EMAILS_STATUS
    );
    $emails_list->append_column($column);

    $self->{report}->begin_read_transaction('emCC');
    if ( $self->{kind} == REPORT_ANNOTATED_PDF ) {
        $self->{email_key} = $self->{association}->variable('key_in_list');
        $self->{email_r} = $self->{report}->get_associated_type($self->{kind});
    } else {
        $self->{email_key} = $self->get('liste_key');
        $self->{email_r} = $self->{report}->get_preassociated_type($self->{kind});
    }

    for my $i (@{$self->{email_r}}) {
        my ($s) = $self->{students_list}
          ->data( $self->{email_key}, $i->{id}, test_numeric => 1 );
        my @sc = $self->{association}->real_back( $i->{id} );
        $emails_store->set(
            $emails_store->append,
            EMAILS_ID,
            $i->{id},
            EMAILS_EMAIL,
            '',
            EMAILS_NAME,
            $s->{_ID_},
            EMAILS_SC,
            ( defined( $sc[0] ) ? pageids_string(@sc) : "[" . $i->{id} . "]" ),
            EMAILS_STATUS,
            (
                $i->{mail_status} == REPORT_MAIL_OK ? __("done")
                : $i->{mail_status} == REPORT_MAIL_FAILED
                ? __("failed")
                : ""
            ),
        );
    }
    $self->{emails_failed} = [
        map    { $_->{id} }
          grep { $_->{mail_status} == REPORT_MAIL_FAILED }
          (@{$self->{email_r}})
    ];

    $self->{report}->end_transaction('emCC');

    $emails_list->get_selection->set_mode('multiple');
    $emails_list->get_selection->select_all;

    $self->attachment_addtolist( @{ $self->get("project:$self->{kind_s}/email_attachment") } );

    $self->get_ui('attachments_expander')
      ->set_expanded( @{ $self->get("project:$self->{kind_s}/email_attachment") } ? 1 : 0 );

    $self->{prefs}->transmet_pref( $self->{main}, prefix => 'email', root => 'project:' );
    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'emailcat',
        root   => "project:" . $self->{kind_s}
        );

    ##############################################
    my $resp = $self->get_ui('email_dialog')->run;
    ##############################################
    
    my @ids  = ();
    if ( $resp == 1 ) {
        $self->{prefs}->reprend_pref( prefix => 'email' );
        $self->{prefs}->reprend_pref(
            prefix => 'emailcat',
            root   => "project:" . $self->{kind_s}
        );

        # get selection
        my @selected = $emails_list->get_selection->get_selected_rows;
        @selected = @{ $selected[0] };
        for my $i (@selected) {
            my $iter = $emails_store->get_iter($i);
            push @ids, $emails_store->get( $iter, EMAILS_ID );
        }

        # get attachments filenames
        my @f    = ();
        my $iter = $attachments_store->get_iter_first;
        my $ok   = defined($iter);
        while ($ok) {
            push @f,
              $self->relatif(
                $attachments_store->get( $iter, ATTACHMENTS_FILE ) );
            $ok = $attachments_store->iter_next($iter);
        }
        if (@f) {
            $self->set( "project:$self->{kind_s}/email_attachment", [@f] );
        } else {
            $self->set( "project:$self->{kind_s}/email_attachment", [] );
        }
    }
    $self->get_ui('email_dialog')->destroy;

    # are all attachments present?
    if ( $resp == 1 ) {
        my @missing = grep { !-f $self->absolu($_) }
          ( @{ $self->get("project:$self->{kind_s}/email_attachment") } );
        if (@missing) {
            my $dialog = Gtk3::MessageDialog->new(
                $self->{parent_window},
                'destroy-with-parent',
                'error', 'ok',
                __(
"Some files you asked to be attached to the emails are missing:"
                  )
                  . "\n"
                  . join( "\n", @missing ) . "\n"
                  . __(
"Please create them or remove them from the list of attached files."
                  )
            );
            $dialog->run();
            $dialog->destroy();
            $resp = 0;
        }
    }
    
    return(@ids);
}

sub check_for_annotated_pdf {
    my ($self) = @_;

    $self->{report}->begin_read_transaction('emNU');
    my $n           = $self->{report}->type_count(REPORT_ANNOTATED_PDF);
    my $n_annotated = $self->{capture}->annotated_count();
    $self->{report}->end_transaction('emNU');

    if ( $n == 0 ) {
        my $dialog = Gtk3::MessageDialog->new(
            $self->{parent_window},
            'destroy-with-parent',
            'error', 'ok',
            __("There are no annotated corrected answer sheets to send.")
              . " "
              . (
                $n_annotated > 0
                ? __(
"Please group the annotated sheets to PDF files to be able to send them."
                  )
                : __(
"Please annotate answer sheets and group them to PDF files to be able to send them."
                )
              )
        );
        $dialog->run;
        $dialog->destroy;

        return (0);
    }

    return (1);
}

# check perl modules availibility

sub check_for_perl_modules {
    my ($self) = @_;

    my @needs_module = (
        qw/Email::Address Email::MIME
          Email::Sender Email::Sender::Simple/
    );
    if ( $self->get('email_transport') eq 'sendmail' ) {
        push @needs_module, 'Email::Sender::Transport::Sendmail';
    } elsif ( $self->get('email_transport') eq 'SMTP' ) {
        push @needs_module, 'Email::Sender::Transport::SMTP';
    }
    my @manque = ();
    for my $m (@needs_module) {
        if ( !check_install( module => $m ) ) {
            push @manque, $m;
        }
    }
    if (@manque) {
        debug 'Mailing: Needs perl modules ' . join( ', ', @manque );

        my $dialog = Gtk3::MessageDialog->new( $self->{parent_window},
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup(
            sprintf(
                __(
"Sending emails requires some perl modules that are not installed: %s. Please install these modules and try again."
                ),
                '<b>' . join( ', ', @manque ) . '</b>'
            )
        );
        $dialog->run;
        $dialog->destroy;

        return (0);
    }

    # STARTTLS is only available with Email::Sender >= 1.300027
    # Warn in case it is not available

    if ( $self->get('email_smtp_ssl') =~ /[^01]/ ) {
        load "Email::Sender";
        load "version";
        if ( version->parse($Email::Sender::VERSION) <
            version->parse("1.300027") )
        {
            my $dialog = Gtk3::MessageDialog->new( $self->{parent_window},
                'destroy-with-parent', 'error', 'ok', '' );
            $dialog->set_markup(
                __(
"SMTP security mode \"STARTTLS\" is only available with Email::Sender version 1.300027 and over. Please install a newer version of this perl module or change SMTP security mode, and try again."
                )
            );
            $dialog->run;
            $dialog->destroy;
            return (0);
        }
    }

    return (1);
}

# check that a correct sender address has been set

sub check_for_sender_address {
    my ($self) = @_;

    my @sa = Email::Address->parse( $self->get('email_sender') );

    if ( !@sa ) {
        my $message;
        if ( $self->get('email_sender') ) {
            $message .= sprintf(
                __("The email address you entered (%s) is not correct."),
                $self->get('email_sender')
              )
              . "\n"
              . __
              "Please edit your preferences to correct your email address.";
        } else {
            $message .= __("You did not enter your email address.") . "\n"
              . __ "Please edit the preferences to set your email address.";
        }
        my $dialog = Gtk3::MessageDialog->new( $self->{parent_window},
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup($message);
        $dialog->run;
        $dialog->destroy;

        return (0);
    }
    return (1);
}

# check that sendmail path is ok

sub check_for_sendmail {
    my ($self) = @_;

    if ( $self->get('email_sendmail_path')
        && !-f $self->get('email_sendmail_path') )
    {
        my $dialog = Gtk3::MessageDialog->new(
            $self->{parent_window},
            'destroy-with-parent',
            'error', 'ok', ''
        );
        $dialog->set_markup(
            sprintf(
                __(
                    # TRANSLATORS: Do not translate the 'sendmail' word.
                    "The <i>sendmail</i> program cannot be found at the location".
                    " you specified in the preferences (%s).".
                    " Please update your configuration."
                ),
                $self->get('email_sendmail_path')
            )
        );
        $dialog->run;
        $dialog->destroy;

        return (0);
    }
    return (1);
}

# find columns with emails in the students list file, and returns the
# column with the maximum number of emails, and the list off all
# columns

sub email_columns {
    my ($self) = @_;

    my %cols_email = $self->{students_list}
      ->heads_count( sub { my @a = Email::Address->parse(@_); return (@a) } );
    my @cols = grep { $cols_email{$_} > 0 } ( keys %cols_email );

    my $nmax    = 0;
    my $col_max = '';

    for (@cols) {
        if ( $cols_email{$_} > $nmax ) {
            $nmax    = $cols_email{$_};
            $col_max = $_;
        }
    }

    return($col_max, @cols);
}

sub attachment_addtolist {
    my ( $self, @files ) = @_;

    for my $f (@files) {
        if ( ref($f) eq 'ARRAY' ) {
            $self->attachment_addtolist(@$f);
        } else {
            my $name = $f;
            $name =~ s/.*\///;
            $self->{attachments_store}->set(
                $self->{attachments_store}->append,
                ATTACHMENTS_FILE,
                $self->absolu($f),
                ATTACHMENTS_NAME,
                $name,
                ATTACHMENTS_FOREGROUND,
                (
                    -f $self->absolu($f)
                    ? hex_color('black')
                    : hex_color('red')
                ),
            );
        }
    }
}

sub attachment_add {
    my ($self) = @_;

    my $d = Gtk3::FileChooserDialog->new(
        __("Attach file"),
        $self->{parent_window}, 'open',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok'
    );
    $d->set_select_multiple(1);
    my $r = $d->run;
    if ( $r eq 'ok' ) {
        $self->attachment_addtolist( clean_gtk_filenames( $d->get_filenames ) );
    }
    $d->destroy();
}

sub attachment_remove {
    my ($self) = @_;

    my @selected = $self->get_ui('attachments_list')->get_selection->get_selected_rows;
    for
      my $i ( map { $self->{attachments_store}->get_iter($_); } ( @{ $selected[0] } ) )
    {
        $self->{attachments_store}->remove($i) if ($i);
    }
}

sub select_failed {
    my ($self) = @_;

    my $select = $self->get_ui('emails_list')->get_selection;
    my $model  = $self->get_ui('emails_list')->get_model();
    $select->unselect_all();
    for my $id ( @{ $self->{emails_failed} } ) {
        $select->select_iter( model_id_to_iter( $model, EMAILS_ID, $id ) );
    }
}

sub project_name {
    my ($self) = @_;

    return ( $self->get('nom_examen')
          || $self->get('code_examen')
          || $self->{project_name} );
}

sub set_project_name {
    my ($self) = @_;

    my $dialog = Gtk3::Dialog->new(
        __("Set exam name"), $self->{parent_window},
        ['destroy-with-parent'],
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
    );
    $dialog->set_default_response('ok');

    my $t = Gtk3::Grid->new();
    my $widget;
    $t->attach( Gtk3::Label->new( __ "Examination name" ), 0, 0, 1, 1 );
    $widget = Gtk3::Entry->new();
    $self->{ui}->{set_name_x_nom_examen} = $widget;
    $t->attach( $widget, 1, 0, 1, 1 );
    $t->attach( Gtk3::Label->new( __ "Code (short name) for examination" ),
        0, 1, 1, 1 );
    $widget = Gtk3::Entry->new();
    $self->{ui}->{set_name_x_code_examen} = $widget;
    $t->attach( $widget, 1, 1, 1, 1 );

    $t->show_all;
    $dialog->get_content_area()->add($t);

    $self->{prefs}->transmet_pref( '', prefix => 'set_name', root => 'project:' );

    my $response = $dialog->run;

    if ( $response eq 'ok' ) {
        $self->{prefs}->reprend_pref( prefix => 'set_name' );
        $self->get_ui('label_name')->set_text( $self->project_name() );
    }

    $dialog->destroy;
}

sub change_col {
    my ($self) = @_;

    $self->set_local_keys('email_col');
    $self->{prefs}->reprend_pref( prefix => 'email', container => 'local' );

    my $i  = $self->{emails_store}->get_iter_first;
    my $ok = defined($i);
    while ($ok) {
        my ($s) = $self->{students_list}->data(
            $self->{email_key},
            $self->{emails_store}->get( $i, EMAILS_ID ),
            test_numeric => 1
        );
        $self->{emails_store}->set( $i, EMAILS_EMAIL,
            $s->{ $self->get('local:email_col') } );
        $ok = $self->{emails_store}->iter_next($i);
    }
}

1;

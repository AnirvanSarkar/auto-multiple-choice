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

package AMC::Gui::AutoCapture;

use parent 'AMC::Gui';

use AMC::Basic;

use Glib;

use_gettext();

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            capture       => '',
            callback_self => '',
            callback => sub { debug "Error: missing AutoCapture callback"; },
        },
        %oo
    );

    $self->store_register(
        auto_capture_mode => cb_model(
            -1 => __ "Please select...",
            0 => __(
                # TRANSLATORS: One of the ways exam was made: each
                # student has a different answer sheet with a
                # different copy number - no photocopy was made. This
                # is a menu entry.
                "Different answer sheets"),

            1 => __(
                # TRANSLATORS: One of the ways exam was made: some
                # students have the same exam subject, as some
                # photocopies were made before distributing the
                # subjects. This is a menu entry.
                "Some answer sheets were photocopied")
        ),
    );

    $self->set_env();

    return $self;
}

# Get some values to be used in other methods.
#
# - n: the number of exam sheets already been captured
# - mcopy: the first available copy number

sub set_env {
    my ($self) = @_;

    if($self->{capture}) {
        $self->{capture}->begin_read_transaction('ckev');
        $self->{n} = $self->{capture}->n_copies;
        $self->{mcopy} = $self->{capture}->max_copy_number() + 1;
        $self->{capture}->end_transaction('ckev');
    }
}

# If some data capture has already been made, check that the
# auto_capture_mode is set, and if not, set it to a sensible value.

sub check_auto_capture_mode {
    my ($self) = @_;

    if ( $self->{n} > 0 && $self->get('auto_capture_mode') < 0 ) {

        # the auto_capture_mode (sheets photocopied or not) is not set,
        # but some capture has already been done. This looks weird, but
        # it can be the case if captures were made with an old AMC
        # version, or if project parameters have not been saved...
        # So we try to detect the correct value from the capture data.
        $self->set( 'auto_capture_mode',
            ( $self->{capture}->n_photocopy() > 0 ? 1 : 0 ) );
    }

}

sub dialog {
    my ($self) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade(
        $glade_xml, qw/ saisie_auto
          copie_scans
          saisie_auto_chooser
          saisie_auto_c_auto_capture_mode
          saisie_auto_cb_allocate_ids
          button_capture_go/
    );

    $self->get_ui('copie_scans')->set_active(1);
    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'saisie_auto',
        root   => 'project:'
    );

    $self->get_ui('saisie_auto_cb_allocate_ids')->set_label(
        sprintf(
            __("Pre-allocate sheet ids from the page numbers, starting at %d"),
            $self->{mcopy}
        )
    );

    $self->get_ui('saisie_auto_c_auto_capture_mode')
      ->set_sensitive( $self->{n} == 0 );

    $self->get_ui('saisie_auto')->show();
}

sub close_dialog {
    my ($self) = @_;

    $self->get_ui('saisie_auto')->destroy();

}

sub cancel {
    my ($self) = @_;

    $self->close_dialog();
}

sub ok {
    my ($self) = @_;

    my @files = sort { $a cmp $b } (
        clean_gtk_filenames(
            $self->get_ui('saisie_auto_chooser')->get_filenames()
        )
    );
    my $copy_files = $self->get_ui('copie_scans')->get_active();

    $self->{prefs}->reprend_pref( prefix => 'saisie_auto' );

    $self->close_dialog();

    Glib::Idle->add(
        $self->{callback},
        {
            copy_files => $copy_files,
            files      => \@files,
            mcopy      => $self->{mcopy},
            self       => $self->{callback_self}, 
        },
        Glib::G_PRIORITY_LOW
    );

}

sub auto_mode_update {
    my ($self, @args) = @_;

    $self->set_local_keys('auto_capture_mode');

    # the mode value (auto_capture_mode) has been updated.
    $self->{prefs}->valide_options_for_domain( 'saisie_auto', 'local', @args );
    my $acm = $self->get('local:auto_capture_mode');
    $acm = -1 if ( !defined($acm) );
    $self->get_ui('button_capture_go')->set_sensitive( $acm >= 0 );
    my $w = $self->get_ui('saisie_auto_cb_allocate_ids');
    if ($w) {
        if ( $acm == 1 ) {
            $w->show();
        } else {
            $w->hide();
        }
    }
}

sub info {
    my ($self) = @_;

    my $dialog = Gtk3::MessageDialog->new( $self->get_ui('saisie_auto'),
        'destroy-with-parent', 'info', 'ok', '' );
    $dialog->set_markup(
        __("Automatic data capture can be done in two different modes:") . "\n"
          . "<b>"
          .

        __(
            # TRANSLATORS: This is a title for the AMC mode where the
            # distributed exam papers are all different (different
            # paper numbers at the top) -- photocopy is not used.
            "Different answer sheets")
          . ".</b> "
          . __(
"In the most robust one, you give a different exam (with a different exam number) to every student. You must not photocopy subjects before distributing them."
          )
          . "\n" . "<b>"
          .

        __(
            # TRANSLATORS: This is a title for the AMC mode where some
            # answer sheets have been photocopied before being
            # distributed to the students.
            "Some answer sheets were photocopied")
          . ".</b> "
          . __(
"In the second one (which can be used only if answer sheets to be scanned have one page per candidate) you can photocopy answer sheets and give the same subject to different students."
          )
          . "\n"
          . __(
"After the first automatic capture, you can't switch to the other mode."
          )
    );
    $dialog->run;
    $dialog->destroy;
}

########################################################################
# Small dialog to choose mode
########################################################################

sub choose_mode {
    my ($self) = @_;

    $self->check_auto_capture_mode();

    if ( $self->get('auto_capture_mode') >= 0 ) {
        return(1);
    }

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/ChooseMode.glade/i;

    $self->read_glade(
        $glade_xml, qw/choose-mode
          saisie_auto_c_auto_capture_mode
          button_capture_go/
    );

    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'saisie_auto',
        root   => 'project:'
    );
    my $ret = $self->get_ui('choose-mode')->run();
    if ( $ret == 1 ) {
        $self->{prefs}->reprend_pref( prefix => 'saisie_auto' );
        $self->get_ui('choose-mode')->destroy();
        return (1);
    } else {
        $self->get_ui('choose-mode')->destroy();
        return (0);
    }
}

1;

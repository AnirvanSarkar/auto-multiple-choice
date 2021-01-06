#! /usr/bin/perl -w
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

package AMC::Gui::Learning;

use parent 'AMC::Gui';

use AMC::Basic;

use Gtk3;

sub new {
    my ( $class, %oo ) = (@_);

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    return ($self);
}

sub lesson_full {
    my ( $self, $key, $type, $buttons, $force, @oo ) = @_;
    my $resp = '';
    $type    = 'info' if ( !$type );
    $buttons = 'ok'   if ( !$buttons );
    if ( $force || !$self->get("apprentissage/$key") ) {
        my $garde;
        my $dialog =
          Gtk3::MessageDialog->new( $self->{parent_window}, 'destroy-with-parent',
            $type, $buttons, '' );
        $dialog->set_markup(@oo);

        if ( !$force ) {
            $garde =
              Gtk3::CheckButton->new( __ "Show this message again next time" );
            $garde->set_active(0);
            $garde->set_can_focus(0);

            $dialog->get_content_area()->add($garde);
        }

        $dialog->show_all();

        $resp = $dialog->run;

        if ( !( $force || $garde->get_active() ) ) {
            debug "Learning : $key";
            $self->set( "apprentissage/$key", 1 );
        }

        $dialog->destroy;
    }
    return ($resp);
}

sub lesson {
    my ( $self, $key, $data ) = @_;

    if ( $key eq 'MAJ_DOCS_OK' ) {
        $self->lesson_full(
            $key, '', '', 0,
            __("Working documents successfully generated.") . " "
              . __(
                # TRANSLATORS: Here, "them" refers to the working documents.
                "You can take a look at them double-clicking on the list."
              )
              . " "
              . __(
                # TRANSLATORS: Here, "they" refers to the working documents.
                "If they are correct, proceed to layouts detection..."
              )
        );
    } elsif ( $key eq 'MAJ_MEP_OK' ) {
        $self->lesson_full(
            $key, '', '', 0,
            __("Layouts are detected.") . " "
              . sprintf(
                __
"You can check all is correct clicking on button <i>%s</i> and looking at question pages to see if red boxes are well positioned.",
                __ "Check layouts"
              )
              . " "
              . __ "Then you can proceed to printing and to examination."
        );
    } elsif ( $key eq 'ASSOC_AUTO_OK' ) {
        $self->lesson_full(
            $key, '', '', 0,
            __(
"Automatic association is now finished. You can ask for manual association to check that all is fine and, if necessary, read manually students names which have not been automatically identified."
            )
        );
    } elsif ( $key eq 'SAISIE_AUTO' ) {
        $self->lesson_full(
            $key, '', '', 0,
            __("Automatic data capture now completed.") . " "
              . (
                $data->{incomplete} > 0
                ? sprintf(
                    __("It is not complete (missing pages from %d papers).")
                      . " ",
                    $data->{incomplete}
                  )
                : ''
              )
              . __(
"You can analyse data capture quality with some indicators values in analysis list:"
              )
              . "\n"
              . sprintf(
                __
"- <b>%s</b> represents positioning gap for the four corner marks. Great value means abnormal page distortion.",
                __ "MSE"
              )
              . "\n"
              . sprintf(
                __
"- great values of <b>%s</b> are seen when darkness ratio is very close to the threshold for some boxes.",
                __ "sensitivity"
              )
              . "\n"
              . sprintf(
                __
"You can also look at the scan adjustment (<i>%s</i>) and ticked and unticked boxes (<i>%s</i>) using right-click on lines from table <i>%s</i>.",
                __ "page adjustment",
                __ "boxes zooms",
                __ "Diagnosis"
              )
        );
    } else {
        debug "WARNING! Unknown lesson: $key";
    }

}

sub forget {
    my ($self) = @_;

    my $dialog =
      Gtk3::MessageDialog->new( $self->{parent_window}, 'destroy-with-parent',
        'question', 'yes-no', '' );
    $dialog->set_markup(

# Explains that some dialogs are shown only to learn AMC, only once by default (first part).
        __("Several dialogs try to help you be at ease handling AMC.") . " " .

# Explains that some dialogs are shown only to learn AMC, only once by default (second part). %s will be replaced with the text "Show this message again next time" that is written along the checkbox allowing the user to keep these learning message next time.
          sprintf(
            __ "Unless you tick the \"%s\" box, they are shown only once.",

# Explains that some dialogs are shown only to learn AMC, only once by default. This is the message shown along the checkbox allowing the user to keep these learning message next time.
            __ "Show this message again next time"
          )
          . " "
          .

# Explains that some dialogs are shown only to learn AMC, only once by default (third part). If you answer YES here, all these dialogs will be shown again.
          __
"Do you want to forgot which dialogs you have already seen and ask to show all of them next time they should appear ?"
    );
    my $response = $dialog->run;
    $dialog->destroy;
    if ( $response eq 'yes' ) {
        debug "Clearing learning states...";
        $self->set( "state:apprentissage", {} );
        $self->{config}->save();
    }
}

1;

__END__

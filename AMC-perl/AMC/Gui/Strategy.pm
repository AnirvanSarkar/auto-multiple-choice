# Copyright (C) 2022 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::Gui::Strategy;

use AMC::Basic;
use AMC::Gui::WindowSize;
use AMC::DataModule::scoring qw/:question/;
use AMC::Scoring;

use Glib qw/TRUE FALSE/;

my %explain_why = (
    V => __("No answer: v"),
    F => __("Forced"),
    P => __("Ceiling"),
    E => __("Invalid: e"),
);

sub new {
    my %o    = (@_);
    my $self = { project => '', size_monitor => '' };
    for ( keys %o ) {
        $self->{$_} = $o{$_} if ( defined( $self->{$_} ) );
    }

    bless $self;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{gui} = Gtk3::Builder->new();
    $self->{gui}->set_translation_domain('auto-multiple-choice');
    $self->{gui}->add_from_file($glade_xml);

    for my $k (
        qw/test_strategy multiple none_of none_row none_ticked
           answers n_answers score_label
           default_scoring question_scoring
           import_row import_cb /
      )
    {
        $self->{$k} = $self->{gui}->get_object($k);
    }

    my $alist =
      Gtk3::ListStore->new( 'Glib::Boolean', 'Glib::String', 'Glib::Boolean' );
    $self->{answers}->set_model($alist);

    my $renderer;

    $renderer=Gtk3::CellRendererToggle->new;
    $renderer->set_property(activatable=>TRUE);
    $renderer->signal_connect("toggled", \&bool_edited, [ $self, 0 ] );
    $self->{answers}->append_column(
        Gtk3::TreeViewColumn->new_with_attributes(
            __(
                # TRANSLATORS: column title for the list of
                # answers in the scoring strategy test window
                "Correct"
            ),
            $renderer,
            active => 0,
        )
    );

    $renderer = Gtk3::CellRendererToggle->new;
    $renderer->set_property( activatable => TRUE );
    $renderer->signal_connect( "toggled", \&bool_edited, [ $self, 2 ] );
    $self->{answers}->append_column(
        Gtk3::TreeViewColumn->new_with_attributes(
            __(
                # TRANSLATORS: column title for the list of
                # answers in the scoring strategy test window
                "Ticked"
            ),
            $renderer,
            active => 2,
        )
    );

    $renderer = Gtk3::CellRendererText->new;
    $renderer->set_property( editable => TRUE );
    $renderer->signal_connect( "edited", \&scoring_edited, [ $self, 1 ] );
    $self->{answers}->append_column(
        Gtk3::TreeViewColumn->new_with_attributes(
            __(
                # TRANSLATORS: column title for the list of
                # answers in the scoring strategy test window
                "Scoring"
            ),
            $renderer,
            text => 1,
        )
    );

    $self->{n} = 3;
    for my $i ( 1 .. $self->{n} ) {
        $alist->set(
            $alist->append,
            0 => $i==1,
            1 => '',
            2 => 0
        );
    }

    $self->{alist} = $alist;

    $self->{answers}->get_selection->set_mode('single');

    AMC::Gui::WindowSize::size_monitor( $self->window, $self->{size_monitor} )
      if ( $self->{size_monitor} );

    $self->{gui}->connect_signals( undef, $self );

    $self->{as_question} = '';
    $self->add_questions;

    $self->window->show;

    $self->change_multiple;
    $self->change_none_of;

    return($self);
}

sub add_questions {
    my ($self) = @_;
    my $any = 0;
    if ( $self->{project} && $self->{project}->name ) {
        $self->{project}->scoring->begin_read_transaction('QnAn');
        my $codepattern = $self->{project}->layout->code_digit_pattern;
        my @q =
          sort { $a->{title} cmp $b->{title} }
          grep { $_->{nanswers} <= 10 && $_->{title} !~ /$codepattern$/ }
          ( $self->{project}->scoring->questions_n_answers );
        $self->{project}->scoring->end_transaction('QnAn');

        $self->{questions} =
          cb_model( "-1", "*", map { $_->{question}, $_->{title} } @q );
        $self->{import_cb}->set_model( $self->{questions} );

        $any=1 if(@q);
    }
    $self->{import_row}->set_visible($any);
}

sub do_import {
    my ($self) = @_;
    my $q = get_active_id( $self->{import_cb} );
    if ( $q >= 0 ) {
        debug "Import from question $q";
        $self->{project}->scoring->begin_read_transaction('ScIm');

        my $student = $self->{project}->scoring->question_first_student($q);
        debug "Student $student";
        my ( $type, $indicative, $strategy ) =
            $self->{project}->scoring->question_info( $student, $q );
        my $answers = $self->{project}->scoring->answers_info( $student, $q );
        my $none_of = ($answers->[0]->{answer} == 0);
        my $n = $answers->[$#{$answers}]->{answer};
        my $default = $self->{project}->scoring->default_strategy($type);

        $self->{project}->scoring->end_transaction('ScIm');

        $self->{multiple}->set_active($type == QUESTION_MULT);
        $self->{default_scoring}->set_text($default);
        $self->{question_scoring}->set_text($strategy);
        $self->{none_of}->set_active($none_of);
        $self->{n_answers}->set_value($n);
        for my $a (@$answers) {
            if ( $a->{answer} > 0 ) {
                my $iter =
                  $self->{alist}->get_iter_from_string( $a->{answer} - 1 );
                $self->{alist}->set( $iter, 0, $a->{correct} );
                $self->{alist}->set( $iter, 1, $a->{strategy} );
                $self->{alist}->set( $iter, 2, 0 );
            }
        }

        $self->{as_question} = $q;
    }
}

sub question_changed {
    my ($self) = @_;
    if($self->{as_question} ne '') {
        $self->{import_cb}->set_active(0);
        $self->{as_question} = '';
    }
}

sub bool_edited {
    my ( $renderer, $path, $args ) = @_;
    my ( $self, $col ) = @$args;
    my $iter = $self->{alist}->get_iter_from_string($path);
    $self->{alist}->set( $iter, $col => !$self->{alist}->get( $iter, $col ) );
    $self->question_changed if($col != 2);
    $self->update;
}

sub scoring_edited {
    my ($renderer, $path, $text, $args) = @_;
    my ($self, $col) = @$args;
    my $iter = $self->{alist}->get_iter_from_string($path);
    $self->{alist}->set( $iter, $col => $text );
    $self->question_changed;
    $self->update;
}

sub window {
    my ($self) = @_;
    return ( $self->{test_strategy} );
}

sub close {
    my ($self) = @_;
    $self->window->destroy;
}

sub change_multiple {
    my ($self) = @_;
    $self->{none_of}->set_sensitive( $self->{multiple}->get_active );
    $self->question_changed;
    $self->update;
}

sub change_none_of {
    my ($self) = @_;
    $self->{none_row}->set_visible( $self->{none_of}->get_active );
    $self->question_changed;
    $self->update;
}

sub update_scoring {
    my ($self) = @_;
    $self->question_changed;
    $self->update;
}

sub update_answers {
    my ($self) = @_;
    my $n = $self->{n_answers}->get_value();
    if ( $n > $self->{n} ) {
        for ( 1 .. ( $n - $self->{n} ) ) {
            $self->{alist}->set(
                $self->{alist}->append,
                0 => 0,
                1 => '',
                2 => 0
            );
        }
    } elsif ( $n < $self->{n} ) {
        for my $i ( 1 .. ( $self->{n} - $n ) ) {
            my $path = $self->{n} - $i;
            my $iter =
              $self->{alist}->get_iter_from_string( $path );
            $self->{alist}->remove($iter) if ($iter);
        }
    }
    $self->{n} = $n;
    $self->question_changed;
    $self->update;
}

sub answer_data {
    my ( $self, $i ) = @_;
    my $iter = $self->{alist}->get_iter_from_string( $i - 1 );
    return {
        strategy => $self->{alist}->get( $iter, 1 ),
        correct  => $self->{alist}->get( $iter, 0 ),
        answer   => $i,
        question => 1,
        ticked   => $self->{alist}->get( $iter, 2 ),
    };
}

sub update {
    my ($self) = @_;

    my $scoring = AMC::Scoring->new();

    my @a = ();

    my $any = 0;
    for my $i ( 1 .. $self->{n} ) {
        my $aa = $self->answer_data($i);
        $any++ if ( $aa->{correct} );
        push @a, $aa;
    }

    if ( $any != 1 && !$self->{multiple}->get_active ) {
        $self->show_score("Error: a simple question must have 1 correct answer");
        return ();
    }

    if ( $self->{multiple}->get_active && $self->{none_of}->get_active ) {
        push @a,
          {
            strategy => '',
            correct  => !$any,
            answer   => 0,
            question => 1,
            ticked   => $self->{none_ticked}->get_active
          };
    }

    my $q = {
        question         => 1,
        indicative       => 0,
        title            => 'test',
        default_strategy => $self->{default_scoring}->get_text(),
        strategy         => $self->{question_scoring}->get_text(),
        type             => (
            $self->{multiple}->get_active ? QUESTION_MULT : QUESTION_SIMPLE
        ),
        answers => \@a
    };

    $scoring->set_default_strategy;
    $scoring->prepare_question($q);
    $scoring->set_type(0);
    my ( $xx, $why ) = $scoring->score_question( 1, $q, 0 );
    $scoring->set_type(1);
    my ($max_score) = $scoring->score_max_question( 1, $q );

    my $text = "$xx  / $max_score";
    $why = $explain_why{$why} || $why;
    $text .= " [$why]" if ($why);

    $self->show_score($text);
}

sub show_score {
    my ( $self, $text ) = @_;
    $self->{score_label}->set_text($text);
}

1;

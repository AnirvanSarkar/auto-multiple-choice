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

package AMC::Gui::Postcorrect;

use parent 'AMC::Gui';

use AMC::Basic;
use AMC::DataModule::capture ':zone';

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            capture     => '',
            ok_callback => '',
        },
        %oo
    );

    return $self;
}

sub choose_reference {
    my ( $self, $ok_callback ) = @_;

    debug "PostCorrect option ON";

    $self->{ok_callback} = $ok_callback if ($ok_callback);

    # gets available sheet ids

    $self->{ids} = {};

    $self->{capture}->begin_read_transaction('PCex');
    my $sth = $self->{capture}->statement('studentCopies');
    $sth->execute;
    while ( my $sc = $sth->fetchrow_hashref ) {
        $self->{student_min} = $sc->{student}
          if ( !defined( $self->{student_min} ) );
        $self->{ids}->{ $sc->{student} }->{ $sc->{copy} } = 1;
        $self->{student_max} = $sc->{student};
    }
    $self->{capture}->end_transaction('PCex');

    debug "Student range: $self->{student_min}," . "$self->{student_max}\n";

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade(
        $glade_xml, qw/choix_postcorrect
          postcorrect_student postcorrect_copy
          postcorrect_set_multiple
          postcorrect_photo postcorrect_apply/
    );

    AMC::Gui::PageArea::add_feuille( $self->get_ui('postcorrect_photo') );

    $self->get_ui('postcorrect_student')
      ->set_range( $self->{student_min}, $self->{student_max} );

    if ( $self->get('postcorrect_student') ) {
        for (qw/student copy/) {
            $self->get_ui( 'postcorrect_' . $_ )
              ->set_value( $self->get( 'postcorrect_' . $_ ) );
        }
    } else {
        $self->get_ui('postcorrect_student')->set_value( $self->{student_min} );
        my @c = sort { $a <=> $b }
          ( keys %{ $self->{ids}->{ $self->{student_min} } } );
        $self->get_ui('postcorrect_copy')->set_value( $c[0] );
    }

    $self->get_ui('postcorrect_set_multiple')
        ->set_active( $self->get("postcorrect_set_multiple") );

    $self->change();

    $self->get_ui('choix_postcorrect')->show();
}

sub close_window {
    my ($self) = @_;

    $self->get_ui('choix_postcorrect')->destroy();
}

sub cancel {
    my ($self) = @_;

    $self->close_window();
}

sub ok {
    my ($self) = @_;

    my $student = $self->get_ui('postcorrect_student')->get_value();
    my $copy    = $self->get_ui('postcorrect_copy')->get_value();
    my $mult    = $self->get_ui('postcorrect_set_multiple')->get_active();
    $self->get_ui('choix_postcorrect')->destroy();

    $self->set( 'postcorrect_student',      $student );
    $self->set( 'postcorrect_copy',         $copy );
    $self->set( 'postcorrect_set_multiple', $mult );

    &{ $self->{ok_callback} }( $student, $copy, $mult );
}

sub student_exists {
    my ( $self, $student ) = @_;
    my @c = ();
    @c = ( keys %{ $self->{ids}->{$student} } )
      if ( $self->{ids}->{$student} );
    return ( $#c >= 0 ? 1 : 0 );
}

sub previous {
    my ($self)  = @_;
    my $student = $self->get_ui('postcorrect_student')->get_value();
    my $copy    = $self->get_ui('postcorrect_copy')->get_value();

    $copy--;
    if ( $copy < $self->{copy_0} ) {
        do { $student-- } while ( $student >= $self->{student_min}
            && !$self->student_exists($student) );
        if ( $student >= $self->{student_min} ) {
            $self->get_ui('postcorrect_student')->set_value($student);
            $self->get_ui('postcorrect_copy')->set_value(10000);
        }
    } else {
        $self->get_ui('postcorrect_copy')->set_value($copy);
    }
}

sub next {
    my ($self)  = @_;
    my $student = $self->get_ui('postcorrect_student')->get_value();
    my $copy    = $self->get_ui('postcorrect_copy')->get_value();

    $copy++;
    if ( $copy > $self->{copy_1} ) {
        do { $student++ } while ( $student <= $self->{student_max}
            && !$self->student_exists($student) );
        if ( $student <= $self->{student_max} ) {
            $self->get_ui('postcorrect_student')->set_value($student);
            $self->get_ui('postcorrect_copy')->set_value(0);
        }
    } else {
        $self->get_ui('postcorrect_copy')->set_value($copy);
    }
}

sub change_copy {
    my ($self)  = @_;
    my $student = $self->get_ui('postcorrect_student')->get_value();
    my $copy    = $self->get_ui('postcorrect_copy')->get_value();

    $self->get_ui('postcorrect_apply')
      ->set_sensitive( $self->{ids}->{$student}->{$copy} );

    $self->{capture}->begin_read_transaction('PCCN');
    my ($f) = $self->{capture}->zone_images( $student, $copy, ZONE_NAME );
    $self->{capture}->end_transaction('PCCN');
    if ( !defined($f) ) {
        $f = '';
    } else {
        $f = $self->get_absolute('cr') . "/$f";
    }
    debug "Postcorrect name field image: $f";
    if ( -f $f ) {
        $self->get_ui('postcorrect_photo')->set_content( image => $f );
    } else {
        $self->get_ui('postcorrect_photo')->set_content();
    }
}

sub change {
    my ($self) = @_;
    my $student = $self->get_ui('postcorrect_student')->get_value();

    my @c = sort { $a <=> $b } ( keys %{ $self->{ids}->{$student} } );
    $self->{copy_0} = $c[0];
    $self->{copy_1} = $c[$#c];

    debug "Postcorrect copy range for student $student: $c[0],$c[$#c]\n";
    $self->get_ui('postcorrect_copy')->set_range( $c[0], $c[$#c] );

    $self->change_copy();
}

1;

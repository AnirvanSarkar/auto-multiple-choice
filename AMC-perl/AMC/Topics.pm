#
# Copyright (C) 2023 Alexis Bienvenüe <paamc@passoire.fr>
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

use utf8;

package AMC::Topics;

use AMC::Basic;
use Hash::Merge;
use File::Spec;
use Cwd;
use Module::Load;
use Module::Load::Conditional qw/check_install/;

my $merger = Hash::Merge->new('LEFT_PRECEDENT');

sub new {
    my ( $class, %o ) = @_;
    my $self = {
        project_dir => '',
        data        => '',
        layout      => '',
        scoring     => '',
        config      => '',
        errors      => []
    };

    for my $k ( keys %o ) {
        $self->{$k} = $o{$k} if ( defined( $self->{$k} ) );
    }

    bless( $self, $class );

    if ( !$self->{data} ) {
        $self->{data} = AMC::Data->new( $self->{project_dir} . "/data" );
    }
    for my $m (qw/layout scoring/) {
        $self->{$m} = $self->{data}->module($m) if ( !$self->{$m} );
    }
    $self->load_topics();

    return $self;
}

sub error {
    my ($self, $text) = @_;
    push @{$self->{errors}}, $text;
    debug "ERROR $text";
}

sub errors {
    my ($self) = @_;
    return ( @{ $self->{errors} } );
}

sub load_yaml {
    my ($self, $file) = @_;

    debug "Loading YAML: $file";

    my ( $volume, $directories, undef ) = File::Spec->splitpath($file);
    my $base = File::Spec->catpath( $volume, $directories );

    my $content = {};
    eval { $content = YAML::Syck::LoadFile($file); };
    $self->error("Unable to parse YAML file $file: $@") if($@);

    if ( ref($content) eq 'HASH' && $content->{include} ) {
        if ( !ref( $content->{include} ) ) {
            $content->{include} = [ $content->{include} ];
        }
        $content->{include} =
          [ map { Cwd::realpath( File::Spec->rel2abs( $_, $base ) ); }
              @{ $content->{include} } ];
        for my $f ( @{ $content->{include} } ) {
            if ( -f $f ) {
                my $c = load_yaml($f);
                $content = $merger->merge( $content, $c );
            } else {
                $self->error("File not found: $f (included from $file)");
            }
        }
    }

    return ($content);
}

sub all_topics {
    my ($self) = @_;
    return(@{$self->{config}->{topics}});
}

sub last_modified {
    my ($self) = @_;
    my $m = 0;
    for my $file ( @{ $self->{config}->{include} } ) {
        my @stats = stat($file);
        $m = $stats[9] if ( $stats[9] > $m );
    }
    return ($m);
}

sub add_conf {
    my ($self, $topics) = @_;
    for my $t ( values(%{$topics->{conf}}), @{$topics->{topics}} ) {
        if ( $t->{conf} ) {
            if ( !ref( $t->{conf} ) ) {
                $t->{conf} = [ $t->{conf} ];
            }
            for my $c ( @{ $t->{conf} } ) {
                if ( $topics->{conf}->{$c} ) {
                    %$t = %{ $merger->merge( $t, $topics->{conf}->{$c} ) };
                } else {
                    $self->error("Unknown configuration: $c");
                }
            }
        }
    }
    return ($topics);
}

sub defaults {
    my ($self) = @_;
    for my $t ( $self->all_topics ) {
        $t->{value} = 'ratio' if ( !$t->{value} );

        my $valuekey = '%{' . $t->{value} . '}';
        $valuekey    = '%{ratio:pc}'     if ( $t->{value} eq 'ratio' );
        $valuekey    = '%{score}/%{max}' if ( $t->{value} eq 'score' );
        $t->{format} = "⬤ %{name}: %{message} ($valuekey)"
          if ( !defined( $t->{format} ) );

        $t->{levels} = [] if ( !$t->{levels} );
        my $i = 1;
        for my $l ( @{ $t->{levels} } ) {
            $l->{i}       = $i++;
            $l->{message} = "" if ( !$l->{message} );
        }
    }
}

sub load_topics {
    my ($self, $force) = @_;

    return() if($self->{config} && !$force);

    my $topics_file = $self->{project_dir} . "/topics.yml";
    if ( -f $topics_file ) {
        if ( check_install( module => 'YAML::Syck' ) ) {
            load('YAML::Syck');
            $YAML::Syck::ImplicitTyping = 1;
            $YAML::Syck::ImplicitUnicode = 1;

            $self->{config} = $self->add_conf( $self->load_yaml($topics_file) );
            push @{$self->{config}->{include}}, $topics_file;
            $self->defaults();
            $self->build_questions_lists();
        } else {
            $self->{config} = { topics => [], include=>[] };
            $self->error('Unable to load perl module YAML::Syck');
        }
    } else {
        $self->{config} = { topics => [], include=>[] };
    }
}

sub n_topics {
    my ($self) = @_;
    return ( 1 + $#{ $self->{config}->{topics} } );
}

sub match_re {
    my ( $self, $target ) = @_;
    if ( ref($target) eq 'ARRAY' ) {
        return "(" . join( '|', map { $self->match_re($_) } (@$target) ) . ")";
    } else {
        if ( $target =~ /^\^/ ) {
            return $target;
        } elsif ( $target =~ /[\*\?]/ ) {
            return join( '',
                map { ( $_ eq '*' ? '.*' : $_ eq '?' ? '.' : "\Q$_\E" ) }
                  split( /(\*|\?)/, $target ) );
        } else {
            return "\Q$target\E";
        }
    }
}

sub build_questions_lists {
    my ($self) = @_;
    my @questions = $self->{layout}->questions_list();
    $self->{qid_to_topics}={};
    for my $t ( @{ $self->{config}->{topics} } ) {
        my $re = $self->match_re( $t->{questions} );
        debug "RE for TOPIC $t->{id} is $re";
        $t->{questions_list} = [grep { $_->{name} =~ /$re/ } @questions];
        for my $q (@{$t->{questions_list}}) {
            push @{$self->{qid_to_topics}->{$q->{question}}}, $t->{id};
        }
    }
}

sub get_topics {
    my ($self, $question_id) = @_;
    my $l = $self->{qid_to_topics}->{$question_id};
    if($l) {
        return(@$l);
    } else {
        return();
    }
}

sub n_levels {
    my ($self, $topic) = @_;
    if($topic->{levels}) {
        return(0+@{$topic->{levels}});
    } else {
        return(0);
    }
}

sub level_color {
    my ( $self, $topic, $i_level ) = @_;
    return $topic->{levels}->[ $i_level - 1 ]->{color};
}

sub and_odf {
    my ( $self, @c ) = @_;
    if (@c) {
        if ( 1 + $#c > 1 ) {
            return ( "AND(" . join( ";", @c ) . ")" );
        } else {
            return ( $c[0] );
        }
    } else {
        return "TRUE";
    }
}

sub level_test_single_odf {
    my ($self, $topic, $i_level, $value) = @_;
    my @cond = ();
    my $l=$topic->{levels}->[$i_level-1];
    if(defined($l->{max})) {
        push @cond, "$value<$l->{max}";
    }
    if(defined($l->{min})) {
        push @cond, "$value>=$l->{min}";
    }
    return($self->and_odf(@cond));
}

sub level_test_odf {
    my ($self, $topic, $i_level, $value) = @_;
    my @cond = ("NOT(ISBLANK($value))");
    if($i_level>1) {
        for my $i (1..($i_level -1)) {
            push @cond, "NOT(".$self->level_test_single_odf($topic, $i, $value).")";
        }
    }
    push @cond, $self->level_test_single_odf($topic, $i_level, $value);
    return $self->and_odf(@cond);
}

sub value_in_level {
    my ($self,$level,$value)=@_;
    return (0) if ( defined($level->{min}) && $value <  $level->{min} );
    return (0) if ( defined($level->{max}) && $value >= $level->{max} );
    return(1);
}

sub value_level {
    my ( $self, $topic, $value ) = @_;
    if ( @{ $topic->{levels} } ) {
        my $n_levels = 1 + $#{ $topic->{levels} };
        my $i_level  = 0;
        while ( $i_level < $n_levels
            && !$self->value_in_level( $topic->{levels}->[$i_level], $value ) )
        {
            $i_level++;
        }
        return ( $topic->{levels}->[$i_level] );
    } else {
        return (undef);
    }
}

sub student_topic_calc {
    my ( $self, $student, $copy, $topic ) = @_;
    my @x   = ();
    for my $q ( @{ $topic->{questions_list} } ) {
        my $r =
          $self->{scoring}->question_result( $student, $copy, $q->{question} );
        if ( defined( $r->{score} ) ) {
            debug "Student ($student,$copy) topic $topic->{id} score ($r->{score},$r->{max})";
            push @x, [ $r->{score}, $r->{max} ];
        }
    }

    my $s    = 0;
    my $smax = 0;
    for my $xm (@x) {
        $s    += $xm->[0];
        $smax += $xm->[1];
    }
    if ( $smax > 0 ) {
        return { score => $s, max => $smax, ratio => $s / $smax };
    } else {
        return undef;
    }
}

sub student_topic_message {
    my ( $self, $student, $copy, $topic ) = @_;
    my $x = $self->student_topic_calc( $student, $copy, $topic );
    if ($x) {
        $x->{'ratio:pc'} = sprintf( "%.0f %%", $x->{ratio} * 100 );
        my $s = $topic->{format};
        for my $k (qw/score max ratio ratio:pc/) {
            $s =~ s/\%\{$k\}/$x->{$k}/g;
        }
        for my $k (qw/id name/) {
            $s =~ s/\%\{$k\}/$topic->{$k}/g;
        }
        my $l =
          $self->value_level( $topic, $x->{ $topic->{value} } )
          || { message => "", color=>"" };
        for my $k (qw/message/) {
            $s =~ s/\%\{$k\}/$l->{$k}/g;
        }
        return { message=>$s, color=>$l->{color} };
    } else {
        return { message => '', color => '' };
    }
}

1;



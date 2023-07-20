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

package AMC::Topics;

use AMC::Basic;
use YAML::Syck;
use Hash::Merge;
use File::Spec;
use Cwd;

my $merger = Hash::Merge->new('LEFT_PRECEDENT');

$YAML::Syck::ImplicitTyping = 1;

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

sub load_yaml {
    my ($self, $file) = @_;

    debug "Loading YAML: $file";

    my ( $volume, $directories, undef ) = File::Spec->splitpath($file);
    my $base = File::Spec->catpath( $volume, $directories );

    my $content = {};
    eval { $content = LoadFile($file); };
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
                $self->error("File not found: $f");
            }
        }
    }

    return ($content);
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

sub load_topics {
    my ($self, $force) = @_;

    return() if($self->{config} && !$force);

    my $topics_file = $self->{project_dir} . "/topics.yml";
    if ( -f $topics_file ) {
        $self->{config} = $self->add_conf( $self->load_yaml($topics_file) );
        $self->build_questions_lists();
    } else {
        $self->{config} = { topics => [] };
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
        debug "RE for TOPIC $t is $re";
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

1;



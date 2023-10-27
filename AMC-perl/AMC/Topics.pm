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
    debug "ERROR(Topic) $text";
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
                my $c = $self->load_yaml($f);
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

sub exam_topics {
    my ($self) = @_;
    my @exam_questions = $self->{scoring}->questions();
    my @topics = ();
    for my $t ($self->all_topics()) {
        my $included = 0;
        my $re = $self->match_re( $t->{questions} );
    QUEST: for my $q (@exam_questions) {
            if($q->{title} =~ /$re/) {
                debug "Exam topics: topic $t->{id} included by question $q->{title}";
                $included = 1;
                last QUEST;
            }
        }
        push @topics, $t if($included);
    }
    return(@topics);
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
    my ( $self, $topics ) = @_;
    my @domains = ();
    if ( $topics->{conf} ) {
        if(ref($topics->{conf}) eq 'HASH') {
            push @domains, values( %{ $topics->{conf} } );
        } else {
            $self->error("'conf' section should include keys");
        }
    }
    if ( $topics->{topics} ) {
        if ( ref( $topics->{topics} ) eq 'ARRAY' ) {
            push @domains, @{ $topics->{topics} };
        } else {
            $self->error("'topics' section should be a list");
        }
    }
    for my $t (@domains) {
        if ( $t->{conf} ) {
            if ( !ref( $t->{conf} ) ) {
                $t->{conf} = [ $t->{conf} ];
            }
            if ( ref( $t->{conf} ) eq 'ARRAY' ) {
                for my $c ( @{ $t->{conf} } ) {
                    debug "Applying conf $c...";
                    if ( $topics->{conf}->{$c} ) {
                        %$t = %{ $merger->merge( $t, $topics->{conf}->{$c} ) };
                    } else {
                        $self->error("Unknown configuration: $c");
                    }
                }
            } else {
                $self->error("'conf' section should be a text or list");
            }
        }
    }
    return ($topics);
}

sub defaults {
    my ($self) = @_;
    for my $t ( $self->all_topics ) {
        $self->error( __
"Topic id <$t->{id}> must only contain alphanumeric characters, without spaces and accentuated characters"
        ) if ( $t->{id} =~ /[^a-zA-Z0-9]/ );

        $t->{value} = 'ratio:pc' if ( !$t->{value} );

        $t->{format} = "⬤ %{name}: %{message} (%{value})"
            if ( !defined( $t->{format} ) );

        $t->{decimals}      = 0 if ( !defined( $t->{decimals} ) );
        $t->{decimalsratio} = 2 if ( !defined( $t->{decimalsratio} ) );
        $t->{decimalspc}    = 0 if ( !defined( $t->{decimalspc} ) );

        $t->{levels} = [] if ( !$t->{levels} );
        my $i = 1;
        for my $l ( @{ $t->{levels} } ) {
            $l->{i}       = $i++;
            $l->{message} = "" if ( !$l->{message} );
        }
    }

    $self->{config}->{preferences} = $merger->merge(
        $self->{config}->{preferences} || {},
        {
            intervalsep => '-',
            odscolumns  => 'value',
        }
    );
}

sub get_option {
    my ( $self, $k ) = @_;
    return ( $self->{config}->{preferences}->{$k} );
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

            if ( ref( $self->{config} ) ) {
                $self->{config}->{include} = []
                  if ( !$self->{config}->{include} );
                push @{ $self->{config}->{include} }, $topics_file;
                $self->defaults();
                if ( ref( $self->{config}->{topics} ) ) {
                    $self->build_questions_lists();
                }
            }
        } else {
            $self->{config} = { topics => [], include=>[] };
            $self->error('Unable to load perl module YAML::Syck');
        }
    } else {
        debug "Topics: file not found - $topics_file";
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
            return '^'
              . join( '',
                map { ( $_ eq '*' ? '.*' : $_ eq '?' ? '.' : "\Q$_\E" ) }
                  split( /(\*|\?)/, $target ) )
              . '$';
        } else {
            return ( '^' . "\Q$target\E" . '$' );
        }
    }
}

sub build_questions_lists {
    my ($self)             = @_;
    $self->{data}->begin_read_transaction("topP");
    my $code_digit_pattern = $self->{layout}->code_digit_pattern();
    my @codes              = $self->{scoring}->codes();
    my $codes_re =
      "(" . join( "|", map { "\Q$_\E" } @codes ) . ")" . $code_digit_pattern;
    my @questions =
      grep { $_->{title} !~ /$codes_re/ } ( $self->{scoring}->questions() );
    $self->{data}->end_transaction("topP");
    debug "All questions: "
      . join( ", ", map { "$_->{question}=$_->{title}" } (@questions) );

    $self->{qid_to_topics} = {};
    for my $t ( @{ $self->{config}->{topics} } ) {
        my $re = $self->match_re( $t->{questions} );
        debug "RE for TOPIC $t->{id} is $re";
        $t->{questions_list} = [ grep { $_->{title} =~ /$re/ } @questions ];
        debug "matching: "
          . join( ", ",
            map { "$_->{question}=$_->{title}" } ( @{ $t->{questions_list} } ) );
        for my $q ( @{ $t->{questions_list} } ) {
            push @{ $self->{qid_to_topics}->{ $q->{question} } }, $t->{id};
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
        return 1;
    }
}

sub level_threshold_odf {
    my ( $self, $topic, $l, $k ) = @_;
    my $v = $l->{$k};
    $v /= 100.0 if ( $topic->{value} =~ /:pc$/ );
    return ($v);
}

sub level_test_single_odf_l {
    my ( $self, $topic, $level, $value ) = @_;
    my @cond = ();
    if ( defined( $level->{max} ) ) {
        push @cond, "$value<" . $self->level_threshold_odf( $topic, $level, 'max' );
    }
    if ( defined( $level->{min} ) ) {
        push @cond,
          "$value>=" . $self->level_threshold_odf( $topic, $level, 'min' );
    }
    return ( $self->and_odf(@cond) );
}

sub level_test_single_odf {
    my ( $self, $topic, $i_level, $value ) = @_;
    my $l    = $topic->{levels}->[ $i_level - 1 ];
    return($self->level_test_single_odf_l($topic, $l, $value));
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

sub level_short_odf {
    my ( $self, $level ) = @_;
    my $v = $level->{code} || $level->{i};
    $v = '"' . $v . '"' if ( $v !~ /^[0-9]+$/ );
    return ($v);
}

sub level_value_odf {
    my ( $self, $topic, $value ) = @_;
    my @cond = ( 'ISBLANK(' . $value . ')', '""' );
    for my $l ( @{ $topic->{levels} } ) {
        my $v = $self->level_short_odf($l);
        push @cond, $self->level_test_single_odf_l( $topic, $l, $value ), $v;
    }
    push @cond, 1, '"?"';
    return ( "IFS(" . join( ";", @cond ) . ")" );
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

sub range {
    my ( $self, $start, $end ) = @_;
    if ( $start eq $end ) {
        return ($start);
    } elsif ( $end == $start + 1 ) {
        return ( $start . ", " . $end );
    } else {
        return ( $start . $self->get_option('intervalsep') . $end );
    }
}

sub last_int {
    my ($self, $s) = @_;
    if($s =~ /([0-9]+)\s*$/) {
        return($1);
    } else {
        return(-99);
    }
}

sub combined_cmp {
    my ( $self, $a, $b ) = @_;

    if ( $a =~ /^[0-9]+$/ && $b =~ /^[0-9]+$/ ) {
        return ( $a <=> $b );
    }

    if ( $a =~ /^([0-9]+)[^0-9]+([0-9]+)$/ ) {
        my $ax = $1;
        my $ay = $2;
        if ( $b =~ /^([0-9]+)[^0-9]+([0-9]+)$/ ) {
            my $bx = $1;
            my $by = $2;
            return ( $ax <=> $bx || $ay <=> $by );
        }
    }

    return ( $a cmp $b );
}


sub nums_string {
    my ($self, @x) = @_;
    my %x = map { $_ => 1 } (@x);
    @x = sort { $self->combined_cmp( $a, $b ) } ( keys %x );
    my $simple = join( ", ", @x );
    my $start  = '';
    my $end    = '';
    my @sets   = ();
    for my $i (@x) {
        if ($start) {
            if ( $self->last_int($i) == $self->last_int($end) + 1 ) {
                $end = $i;
            } else {
                push @sets, $self->range( $start, $end );
                $start = $i;
                $end   = $i;
            }
        } else {
            $start = $i;
            $end   = $i;
        }
    }
    push @sets, $self->range( $start, $end ) if ( $start ne '' );
    my $merged = join( ", ", @sets );
    return ( $simple, $merged );
}

sub student_topic_calc {
    my ( $self, $student, $copy, $topic ) = @_;
    my @x    = ();
    my @nums = ();
    for my $q ( @{ $topic->{questions_list} } ) {
        my $r =
          $self->{scoring}->question_result( $student, $copy, $q->{question} );
        if ( defined( $r->{score} ) ) {
            debug "Student ($student,$copy) topic $topic->{id} score ($r->{score},$r->{max})";
            push @x, [ $r->{score}, $r->{max} ];
            push @nums,
              $self->{layout}->question_number( $student, $q->{question} );
        }
    }

    my ( $nums_simple, $nums_condensed ) = $self->nums_string(@nums);

    my $s    = 0;
    my $smax = 0;
    for my $xm (@x) {
        $s    += $xm->[0];
        $smax += $xm->[1];
    }

    if ( $smax > 0 ) {
        my $x = {
            score      => $s,
            max        => $smax,
            ratio      => $s / $smax,
            'ratio:pc' => 100 * $s / $smax,
            'nums:s'   => $nums_simple,
            'nums:c'   => $nums_condensed,
        };

        # Applies ceil and floor to topic value
        my $k = $topic->{value};
        if ( defined( $topic->{ceil} ) ) {
            $x->{$k} = $topic->{ceil}
              if ( $x->{$k} > $topic->{ceil} );
        }
        if ( defined( $topic->{floor} ) ) {
            $x->{$k} = $topic->{floor}
              if ( $x->{$k} < $topic->{floor} );
        }

        # Updates ratio:pc if ratio has been updated, and ratio if
        # ratio:pc has been updated
        my $k_alter = $k;
        if ( $k_alter =~ s/:pc$// ) {
            $x->{$k_alter} = $x->{$k} / 100;
        } else {
            $k_alter .= ':pc';
            $x->{$k_alter} = $x->{$k} * 100;
        }

        return ($x);
    } else {
        return undef;
    }
}

sub student_topic_message {
    my ( $self, $student, $copy, $topic ) = @_;
    my $x = $self->student_topic_calc( $student, $copy, $topic );
    if ($x) {
        my $s = $topic->{format};
        my $l =
          $self->value_level( $topic, $x->{ $topic->{value} } )
          || { message => "", color=>"" };

        for my $k (qw/message/) {
            $s =~ s/\%\{$k\}/$l->{$k}/g if ( defined( $l->{$k} ) );
        }

        my $value = '%{'.$topic->{value}.'}';
        if($topic eq 'score') {
            $value = '%{score}/%{max}';
        }
        $s =~ s/\%\{value\}/$value/g;

        for my $k (qw/score max ratio ratio:pc/) {
            my $v;
            if ( $k =~ /:pc$/ ) {
                my $kk = $k;
                $kk =~ s/:pc$//;
                $x->{$k} = $x->{$kk} * 100;
                my $d = $topic->{decimalspc};
                $v = sprintf( "%.${d}f %%", $x->{$k} );
            } else {
                my $d =
                  (   $k eq 'ratio'
                    ? $topic->{decimalsratio}
                    : $topic->{decimals} );
                $v = sprintf( "%.${d}f", $x->{$k} );
            }
            $s =~ s/\%\{$k\}/$v/g;
        }
        for my $k (qw/id name/) {
            $s =~ s/\%\{$k\}/$topic->{$k}/g;
        }
        for my $k (qw/nums:s nums:c/) {
            $s =~ s/\%\{$k\}/$x->{$k}/g;
        }
        for my $k (qw/code i/) {
            $s =~ s/\%\{$k\}/$l->{$k}/g if ( defined( $l->{$k} ) );
        }
        return { message => $s, color => $l->{color}, calc => $x };
    } else {
        return { message => '', color => '', calc => $x };
    }
}

1;



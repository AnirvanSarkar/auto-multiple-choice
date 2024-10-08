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
use Module::Load;
use Module::Load::Conditional qw/check_install/;
use Data::Dumper;

my $merger = Hash::Merge->new('LEFT_PRECEDENT');

sub min {
    my $x = shift;
    for my $y (@_) {
        $x = $y if ( $y < $x );
    }
    return ($x);
}

sub max {
    my $x = shift;
    for my $y (@_) {
        $x = $y if ( $y > $x );
    }
    return ($x);
}

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

    debug( "Loading YAML: " . show_utf8($file) );

    my ( $volume, $directories, undef ) = File::Spec->splitpath($file);
    my $base = File::Spec->catpath( $volume, $directories );
    debug( "Base path: " . show_utf8($base) );

    my $content = {};

    if ( -s $file ) {
        eval { $content = YAML::Syck::LoadFile($file); };
        $self->error("Unable to parse YAML file $file: $@") if ($@);
    } else {
        debug("File not found, or empty: $file");
    }

    if ( ref($content) eq 'HASH' && $content->{include} ) {
        if ( !ref( $content->{include} ) ) {
            $content->{include} = [ $content->{include} ];
        }
        $content->{include} =
          [ map { File::Spec->rel2abs( $_, $base ); }
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
    my ($self)         = @_;
    my @exam_questions = $self->{scoring}->questions();
    my @topics         = ();
    for my $t ( $self->all_topics() ) {
        push @topics, $t
          if ( $self->topic_filter_questions( $t, @exam_questions ) );
    }
    return (@topics);
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
    my $i = 0;
    for my $t ( $self->all_topics ) {
        $i++;
        $t->{id} = "_topic" . $i if ( !$t->{id} );
        $t->{i} = $i;

        $self->error(
            sprintf(
                (
                    __
"Topic id <%s> must only contain alphanumeric characters, without spaces and accentuated characters"
                ),
                $t->{id}
            )
        ) if ( $t->{id} =~ /[^_a-zA-Z0-9]/ );

        $t->{value} = 'ratio:pc' if ( !$t->{value} );
        $t->{aggregate} = 'sumscores' if ( !$t->{aggregate} );

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
            intervalsep       => '-',
            odscolumns        => 'value',
            skip_indicatives  => 1,
            decimal_separator => '.',
            pc_suffix         => ' %',
            answered_only     => 0,
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
    if ( !$target ) {
        return '';
    } elsif ( ref($target) eq 'ARRAY' ) {
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

sub topic_filter_questions {
    my ( $self, $topic, @q ) = @_;
    my $re = $self->match_re( $topic->{questions} );
    debug "RE for TOPIC $topic->{id} is $re";
    return() if(!$re);
    @q = grep { $_->{title} =~ /$re/ } @q;
    my $xre = $self->match_re( $topic->{exclude_questions} );
    debug "XRE for TOPIC $topic->{id} is $xre";
    @q = grep { $_->{title} !~ /$xre/ } @q if ($xre);
    return (@q);
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
    $self->{question_color} = {};
    for my $t ( @{ $self->{config}->{topics} } ) {
        $t->{questions_list} =
          [ $self->topic_filter_questions( $t, @questions ) ];
        debug "matching: "
          . join( ", ",
            map { "$_->{question}=$_->{title}" }
              ( @{ $t->{questions_list} } ) );
        for my $q ( @{ $t->{questions_list} } ) {
            push @{ $self->{qid_to_topics}->{ $q->{question} } }, $t->{id};
            $self->{question_color}->{ $q->{question} } = $t->{annotate_color}
              if ( $t->{annotate_color} );
        }
    }
}

sub get_question_color {
    my ( $self, $question_id ) = @_;
    return ( $self->{question_color}->{$question_id} );
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

sub value_calc_odf {
    my ( $self, $topic, $scores, $maxs, $n_cells ) = @_;
    my $formula;
    my $matrix = 0;

    my $key      = $topic->{value};
    my $agg      = $topic->{aggregate};
    my $modifier = '';
    if ( $key =~ /^([^:]+):(.*)$/ ) {
        $key      = $1;
        $modifier = $2;
    }

    my $subformula = '';
    if ( $agg =~ /count\(([\d.]+)(?:,([\d.]+))?\)/ ) {
        my $min = $1;
        my $max = $2;
        $agg = 'count';
        my @parts = ();
        for my $range (split(/;/,$scores)) {
            if(defined($max)) {
                push @parts, "SUM(IFS(($range)<$min;0;($range)>$max;0;1;1))";
            } else {
                push @parts, "SUM(($range)=$min)";
            }
        }
        $subformula = join('+', @parts);
    }

    if ( $key eq 'score' ) {
        if ( $agg eq 'sumscores' ) {
            $formula = "SUM($scores)";
        } elsif ( $agg eq 'sumratios' ) {
            $formula = "SUM(($scores)/($maxs))";
            $matrix  = 1;
        } elsif ( $agg =~ /(max|min)score/ ) {
            $formula = uc($1) . "($scores)";
        } elsif ( $agg =~ /(max|min)ratio/ ) {
            $formula = uc($1) . "(($scores)/($maxs))";
            $matrix  = 1;
        } elsif ( $agg eq 'count') {
            $formula = "$subformula";
            $matrix = 1;
        } else {
            die "Topic agregate '$agg' can't be handled";
        }
    } elsif ( $key eq 'ratio' ) {
        if ( $agg eq 'sumscores' ) {
            $formula = "SUM($scores)/SUM($maxs)";
        } elsif ( $agg eq 'sumratios' ) {
            $formula = "SUM(($scores)/($maxs))/$n_cells";
            $matrix  = 1;
        } elsif ( $agg =~ /(max|min)score/ ) {
            $formula = uc($1) . "($scores)/" . uc($1) . "($maxs)";
        } elsif ( $agg =~ /(max|min)ratio/ ) {
            $formula = uc($1) . "(($scores)/($maxs))";
            $matrix  = 1;
        } elsif ( $agg eq 'count') {
            $formula = "($subformula)/$n_cells";
            $matrix = 1;
        } else {
            die "Topic agregate '$agg' can't be handled";
        }
    } else {
        die "Topic value '$key' can't be handled";
    }

    if ( $modifier =~ /^[0-9]+(\.[0-9]+)?$/ ) {
        $formula = "$modifier*($formula)";
    } elsif ( $modifier =~ /^([0-9]+(?:\.[0-9]+)?):([0-9]+(?:\.[0-9]+)?)$/ ) {
        my $mult = $1;
        my $prec = $2;
        $formula = "$prec*ROUND($mult*($formula)/$prec)";
    } elsif ( $modifier =~ /^([0-9]+(?:\.[0-9]+)?)-([0-9]+(?:\.[0-9]+)?)$/ ) {
        my $low  = $1;
        my $high = $2;
        $formula="$low+($high-$low)*($formula)";
    } elsif ( $modifier =~
        /^([0-9]+(?:\.[0-9]+)?)-([0-9]+(?:\.[0-9]+)?):([0-9]+(?:\.[0-9]+)?)$/ )
    {
        my $low  = $1;
        my $high = $2;
        my $prec = $3;
        $formula="$prec*ROUND(($low+($high-$low)*($formula))/$prec)";
    }

    if(defined($topic->{ceil})) {
        $formula="MIN($topic->{ceil};$formula)";
    }
    if(defined($topic->{floor})) {
        $formula="MAX($topic->{floor};$formula)";
    }

    return($formula, $matrix);
}

sub value_in_level {
    my ($self,$level,$value)=@_;
    return (0) if ( defined($level->{min}) && $value <  $level->{min} );
    return (0) if ( defined($level->{max}) && $value >= $level->{max} );
    return(1);
}

sub value_level {
    my ( $self, $topic, $scores ) = @_;
    if ( @{ $topic->{levels} } ) {
        my $value = $scores->{value};

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
    my %x = ();
    for (@x) { $x{$_} = 1 if(defined($_)); }
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
    my $agg  = $topic->{aggregate};
    my $all_empty = 1;
    for my $q ( @{ $topic->{questions_list} } ) {
        my $r =
            $self->{scoring}->question_result( $student, $copy, $q->{question} );
        my $indic = 0;
        $indic = $self->{scoring}->indicative( $student, $q->{question} )
            if($self->get_option('skip_indicatives'));
        if ( defined( $r->{score} ) && ! $indic ) {
            debug "Student ($student,$copy) topic $topic->{id} score ($r->{score},$r->{max}) for question $q->{title}";
            push @x, [ $r->{score}, $r->{max} ];
            push @nums,
                $self->{layout}->question_number( $student, $q->{question} );
            $all_empty = 0 if($r->{why} ne 'V');
        }
    }

    my ( $nums_simple, $nums_condensed ) = $self->nums_string(@nums);

    my $s    = 0;
    my $smax = 0;
    if ( $agg =~ /^min/ ) {
        $s    = "Inf";
        $smax = "Inf";
    }
    if ( $agg =~ /^(min|max)ratio$/ ) {
        $smax = 1;
    }
    for my $xm (@x) {
        my $s1 = $xm->[0];
        my $m1 = $xm->[1];
        if ( $agg eq 'sumscores' ) {
            $s    += $s1;
            $smax += $m1;
        } elsif ( $agg eq 'sumratios' ) {
            if ( $m1 > 0 ) {
                $s    += $s1 / $m1;
                $smax += 1;
            }
        } elsif ( $agg =~ /(max|min)score/ ) {
            my $f = $1;
            {
                no strict 'refs';
                $s    = &{$f}( $s,    $s1 );
                $smax = &{$f}( $smax, $m1 );
            }
        } elsif ( $agg =~ /(max|min)ratio/ ) {
            my $f = $1;
            if ( $m1 > 0 ) {
                no strict 'refs';
                $s = &{$f}( $s, $s1 / $m1 );
            }
        } elsif ( $agg =~ /count\(([\d.]+)(?:,([\d.]+))?\)/ ) {
            my $min = $1;
            my $max = $2;
            $max = $min if ( !defined($max) );
            $s += 1 if ( $s1 >= $min && $s1 <= $max );
            $smax += 1;
        } else {
            die "Unknown aggregate function : $topic->{aggregate}";
        }
    }

    if ( $smax > 0 ) {
        my $x = {
            score     => $s,
            max       => $smax,
            ratio     => $s / $smax,
            'nums:s'  => $nums_simple,
            'nums:c'  => $nums_condensed,
            all_empty => $all_empty,
        };

        $x->{'ratio:pc'} =
          $self->adjusted_value( $topic, 'ratio', $x->{ratio}, 'pc' );

        my $key      = $topic->{value};
        my $modifier = '';
        if ( $key =~ /^([^:]+):(.*)$/ ) {
            $key      = $1;
            $modifier = $2;
        }
        my $v = $x->{$key};

        ( $x->{value}, $x->{value_decimals} ) =
          $self->adjusted_value( $topic, $key, $v, $modifier );

        return ($x);
    } else {
        return undef;
    }
}

sub with_decimals {
    my ( $self, $decimals, $x, $pc ) = @_;
    my $force = 0;
    $force = 1 if ( $decimals =~ s/\!$// );
    my $s = sprintf( "%.${decimals}f", $x );
    if ( $s =~ /\./ && !$force ) {
        $s =~ s/\.?0+$//;
    }
    $s .= " %" if($pc);
    return ($s);
}

sub round_to_multiple {
    my ( $self, $x, $prec ) = @_;
    my $decimals = 0;
    if ( $prec =~ /\./ ) {
        my @xx = split( /\./, $prec );
        $decimals = length( $xx[1] );
    }
    $x = sprintf( "%.0f", $x / $prec ) * $prec;
    my $s = $self->with_decimals( $decimals, $x );
    return(wantarray ? ($s, $decimals) : $s);
}

sub intervaled {
    my ( $self, $topic, $v ) = @_;

    # Applies ceil and floor to topic value
    if ( defined( $topic->{ceil} ) ) {
        $v = $topic->{ceil}
          if ( $v > $topic->{ceil} );
    }
    if ( defined( $topic->{floor} ) ) {
        $v = $topic->{floor}
          if ( $v < $topic->{floor} );
    }
    return ($v);
}

sub adjusted_value {
    my ( $self, $topic, $key, $x, $modifier ) = @_;
    my $s   = '?';
    my $dec;
    if ( $modifier eq '_self' ) {
        if ( $key =~ /^([^:]+):(.*)$/ ) {
            $key      = $1;
            $modifier = $2;
        } else {
            $modifier = '';
        }
    }
    my $d = ( $key eq 'ratio' ? 'decimalsratio' : 'decimals' );
    $dec = $topic->{$d};
    if ( $modifier eq '' ) {
        $s   = $self->with_decimals( $dec, $self->intervaled( $topic, $x ) );
    } elsif ( $modifier eq 'pc' ) {
        $dec = $topic->{decimalspc};
        $s =
          $self->with_decimals( $dec, $self->intervaled( $topic, $x * 100 ) );
    } elsif ( $modifier =~ /^[0-9]+(\.[0-9]+)?$/ ) {
        $s   = $self->with_decimals( $dec,
            $self->intervaled( $topic, $x * $modifier ) );
    } elsif ( $modifier =~ /^([0-9]+(?:\.[0-9]+)?):([0-9]+(?:\.[0-9]+)?)$/ ) {
        my $mult = $1;
        my $prec = $2;
        ( $s, $dec ) =
          $self->round_to_multiple( $self->intervaled( $topic, $x * $mult ),
            $prec );
    } elsif ( $modifier =~ /^([0-9]+(?:\.[0-9]+)?)-([0-9]+(?:\.[0-9]+)?)$/ ) {
        my $low  = $1;
        my $high = $2;
        $s   = $self->with_decimals( $dec,
            $self->intervaled( $topic, $x * ( $high - $low ) + $low ) );
    } elsif ( $modifier =~
        /^([0-9]+(?:\.[0-9]+)?)-([0-9]+(?:\.[0-9]+)?):([0-9]+(?:\.[0-9]+)?)$/ )
    {
        my $low  = $1;
        my $high = $2;
        my $prec = $3;
        ( $s, $dec ) =
          $self->round_to_multiple(
            $self->intervaled( $topic, $x * ( $high - $low ) + $low ), $prec );
    }
    return ( wantarray ? ($s, $dec) : $s );
}

sub student_topic_message {
    my ( $self, $student, $copy, $topic ) = @_;
    if ( $topic->{text} ) {
        return (
            { message => $topic->{text}, color => $topic->{color}, calc => {} }
        );
    }
    my $x = $self->student_topic_calc( $student, $copy, $topic );
    if ($x) {
        if($x->{all_empty} && $self->get_option('answered_only')) {
            debug("Topic($student,$copy,$topic->{id}): all empty");
            return { message => '', color => '', calc => $x };
        }

        my $s = $topic->{format};
        my $l =
          $self->value_level( $topic, $x )
          || { message => "", color=>"" };

        for my $k (qw/message/) {
            $s =~ s/\%\{$k\}/$l->{$k}/g if ( defined( $l->{$k} ) );
        }

        if ( $topic->{value} eq 'score' ) {
            my $value = '%{score}/%{max}';
            $s =~ s/\%\{value\}/$value/g;
        }

        for my $k (qw/score max ratio value/) {
            my $v;
            if ( $k eq 'value' ) {
                $v = $x->{$k};
            } else {
                $v = $self->adjusted_value( $topic, $k, $x->{$k}, '_self' );
            }
            my $dp = $self->get_option('decimal_separator');
            $v =~ s/\./$dp/;
            if($k eq 'value' && $topic->{value} =~ /:pc/) {
                $v .= $self->get_option('pc_suffix');
            }

            $s =~ s/\%\{$k\}/$v/g;
        }

        for my $k (qw/id name/) {
            $s =~ s/\%\{$k\}/$topic->{$k}/g if ( defined( $topic->{$k} ) );
        }
        for my $k (qw/nums:s nums:c/) {
            $s =~ s/\%\{$k\}/$x->{$k}/g if ( defined( $x->{$k} ) );
        }
        for my $k (qw/code i/) {
            $s =~ s/\%\{$k\}/$l->{$k}/g if ( defined( $l->{$k} ) );
        }

        my $c = { message => $s, color => $l->{color}, calc => $x };
        debug( "Topic($student,$copy,$topic->{id}):\n" . Dumper($c) );
        return($c);
    } else {
        debug("Topic($student,$copy,$topic->{id}): empty calc");
        return { message => '', color => '', calc => $x };
    }
}

1;



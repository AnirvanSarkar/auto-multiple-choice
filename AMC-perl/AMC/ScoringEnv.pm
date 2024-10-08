# -*- perl -*-
#
# Copyright (C) 2012-2022 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::ScoringEnv;

# AMC::ScoringEnv object handles directives used in scoring
# strategies. Directives can be parsed from scoring strategy strings,
# and their value can be computed with different sets of variables'
# values (AMC-note uses one set of values for variables for the
# student answer sheet, and one set of values for a perfect answer).

use AMC::Basic;
use Text::ParseWords;

# The functions min and max will sometimes be used to evaluate the
# formulas: don't cut them off

sub min {
    my (@values) = @_;
    my $r = $values[0];
    for (@values) { $r = $_ if ( $_ < $r ); }
    return ($r);
}

sub max {
    my (@values) = @_;
    my $r = $values[0];
    for (@values) { $r = $_ if ( $_ > $r ); }
    return ($r);
}

sub amcround {
    my ( $x, $ndd ) = @_;
    return ( sprintf( "%.0f", $x * 10**$ndd ) );
}

sub amcroundnear {
    my ( $x, $ndd ) = @_;
    return
      abs( sprintf( "%.0f", $x * 10**$ndd + 0.01 ) -
          sprintf( "%.0f", $x * 10**$ndd - 0.01 ) );
}

sub amcrounddiff {
    my ( $target, $x, $ndd ) = @_;
    my $diff = abs( amcround( $target, $ndd ) - amcround( $x, $ndd ) );
    my $tol  = max( amcroundnear( $target, $ndd ), amcroundnear( $x, $ndd ) );
    return max( 0, $diff - $tol );
}

sub amcvdifference {
    my ( $target, $x, $ndd, $nexpo ) = @_;
    if ( $nexpo > 0 ) {
        my ( $t0, $e ) = split( /e/, sprintf( "%.12e", $target ) );
        if ( amcround( abs($t0), $ndd ) >= 10**( $ndd + 1 ) ) {
            $e += 1;
            $t0 /= 10;
        }
        return amcrounddiff( $t0, $x * 10**( -$e ), $ndd );
    } else {
        return amcrounddiff( $target, $x, $ndd );
    }
}


sub new {
    my ( $class, @objects ) = (@_);

    my $self = {
        error_hook => '',
        variables  => {},
        directives => {},
        type       => 0,
    };

    my $scalar_only = 0;

    for my $obj (@objects) {
        if ( $obj->{scalar_only} ) {
            $scalar_only = 1;
            delete( $obj->{scalar_only} );
        }
        for my $k ( keys %$obj ) {
            if ( defined( $self->{$k} ) ) {
                if ( ref( $self->{$k} ) eq 'HASH' ) {
                    $self->{$k} = { %{ $obj->{$k} } }
                      if ( !$scalar_only );
                } else {
                    $self->{$k} = $obj->{$k};
                }
            }
        }
    }

    $self->{errors}          = [];
    $self->{globalvariables} = $self->{variables};

    bless( $self, $class );

    return ($self);
}

sub new_from_directives_string {
    my ( $class, $string ) = @_;
    my $self = $class->new();
    $self->process_directives($string);
    return ($self);
}

sub error {
    my ( $self, $text ) = @_;
    debug $text;
    push @{ $self->{errors} }, $text;
}

sub errors {
    my ($self) = @_;
    return ( @{ $self->{errors} } );
}

sub n_errors {
    my ($self) = @_;
    return ( 1 + $#{ $self->{errors} } );
}

sub clear_errors {
    my ($self) = @_;
    $self->{errors} = [];
}

sub clone {
    my ( $self, $from_global ) = @_;
    my $c = AMC::ScoringEnv->new($self);
    if ($from_global) {
        $c->{globalvariables} = $self->{variables};
    } else {
        $c->{globalvariables} = $self->{globalvariables};
    }
    return ($c);
}

sub clone_directives {
    my ($self) = @_;
    return (
        AMC::ScoringEnv->new(
            { directives  => $self->{directives} },
            { scalar_only => 1 }, $self
        )
    );
}

# set the type (a small integer) to be used for computations. Changing
# the type will move to different values for all variables handled by
# the object. All directives are kept unchanged, but their values will
# be computed again next time get_directive will be called, with the
# new values that will be set for all variables.

sub set_type {
    my ( $self, $type ) = @_;
    $self->unevaluate_directives() if ( $self->{type} != $type );
    $self->{type} = $type;
}

# set variable value.

sub set_variable {
    my ( $self, $vv, $value, $rw, $unlock, $global ) = @_;
    my $vars = ( $global ? 'globalvariables' : 'variables' );
    $self->{$vars}->{$vv} = [] if ( !$self->{$vars}->{$vv} );
    if (   ( !$unlock )
        && $self->{$vars}->{$vv}->[ $self->{type} ]
        && !$self->{$vars}->{$vv}->[ $self->{type} ]->{rw} )
    {
        $self->error("Trying to set read-only variable $vv");
    } else {
        $self->{$vars}->{$vv}->[ $self->{type} ] =
          { value => $value, rw => $rw };
    }
}

sub set_variables_from_hashref {
    my ( $self, $hashref, $rw ) = @_;
    for my $k ( keys %$hashref ) {
        $self->set_variable( $k, $hashref->{$k}, $rw );
    }
}

# is this variable defined?

sub defined_variable {
    my ( $self, $vv ) = @_;
    return (0) if ( !$self->{variables}->{$vv} );
    return (0) if ( !$self->{variables}->{$vv}->[ $self->{type} ] );
    return ( defined( $self->{variables}->{$vv}->[ $self->{type} ] ) );
}

# get variable value.

sub get_variable {
    my ( $self, $vv ) = @_;
    if ( $self->defined_variable($vv) ) {
        return ( $self->{variables}->{$vv}->[ $self->{type} ]->{value} );
    } else {
        return (undef);
    }
}

# parse directives strings

sub parse_defs {
    my ( $self, $string, $plain_only ) = @_;
    my @r = ();
    for my $def ( quotewords( ',+', 1, $string ) ) {
        if ( length($def) ) {
            $def =~ s/^\s*(['"])(.*)\g{1}\s*$/$2/;
            if ( $def =~ /^\s*([.a-zA-Z0-9_-]+)\s*=\s*(.*)/ ) {
                # "variable=value" case
                my $variable = $1;
                my $value    = $2;
                $value =~ s/\s+$//;
                $value =~ s/^(['"])(.*)\g{1}$/$2/;
                push @r, { key => $variable, value => $value }
                  if ( !$plain_only );
            } else {

                # "value" case
                $def =~ s/^\s+//;
                $def =~ s/\s+$//;
                if ( $def ne '' ) {
                    if ($plain_only) {
                        push @r, $def;
                    } else {
                        push @r, { key => "_PLAIN_", value => $def };
                    }
                }
            }
        }
    }
    return ( \@r );
}

sub action_variable {
    my ( $self, $action, $key, $value ) = @_;
    if ( $action eq 'default' ) {
        if ( !$self->defined_variable($key) ) {
            debug "Default value for variable $key [$self->{type}] = $value";
            $self->set_variable( $key, $self->evaluate($value), 1 );
        } else {
            debug "Variable $key [$self->{type}] already set";
        }
    } elsif ( $action eq 'set' ) {
        debug "Setting variable $key [$self->{type}] = $value";
        $self->set_variable( $key, $self->evaluate($value), 0 );
    } elsif ( $action eq 'setx' ) {
        debug "Overwriting variable $key [$self->{type}] = $value";
        $self->set_variable( $key, $self->evaluate($value), 0, 1 );
    } elsif ( $action eq 'setglobal' ) {
        debug "Setting global variable $key [$self->{type}] = $value";
        $self->set_variable( $key, $self->evaluate($value), 0, 1, 1 );
    } elsif ( $action eq 'requires' ) {
        $self->error("Variable $key [$self->{type}] required")
          if ( !$self->defined_variable($key) );
    }
}

sub action_variables_from_directives {
    my ( $self, $action, $keys ) = @_;
    $keys = [ $self->sorted_directives_keys ] if ( !$keys );
    for my $key (@$keys) {
        if ( $key =~ /^$action\.(.*)/ ) {
            $self->action_variable( $action, $1,
                $self->{directives}->{$key}->{def} );
        }
    }
}

sub variables_from_directives {
    my ( $self, %oo ) = @_;
    debug "Variables from internal directives";
    my @keys = $self->sorted_directives_keys;
    for my $a (qw/default set setx setglobal requires/) {
        $self->action_variables_from_directives( $a, \@keys )
          if ( $oo{$a} );
    }
}

sub action_variables_from_parse {
    my ( $self, $parsed, $action ) = @_;
    my @other = ();
    for my $d (@$parsed) {
        if ( $d->{key} =~ /^$action\.(.*)/ ) {
            $self->action_variable( $action, $1, $d->{value} );
        } else {
            push @other, $d;
        }
    }
    @$parsed = @other;
}

sub variables_from_parsed_directives {
    my ( $self, $parsed, %oo ) = @_;
    for my $a (qw/default set setx setglobal requires/) {
        $self->action_variables_from_parse( $parsed, $a )
          if ( $oo{$a} );
    }
}

sub variables_from_directives_string {
    my ( $self, $string, %oo ) = @_;
    debug "Variables from directives $string";
    $self->variables_from_parsed_directives( $self->parse_defs($string), %oo );
}

sub process_variables {
    my ( $self, $string ) = @_;
    $self->variables_from_parse( $self->parse_defs($string) );
}

sub unevaluate_directives {
    my ($self) = @_;
    for my $key ( keys %{ $self->{directives} } ) {
        $self->{directives}->{$key}->{evaluated} = 0;
    }
}

sub max_rank {
    my ($self) = @_;
    my $r = 0;
    for ( keys %{ $self->{directives} } ) {
        $r = $self->{directives}->{$_}->{rank}
          if ( $self->{directives}->{$_}->{rank} > $r );
    }
    return ($r);
}

sub sorted_directives_keys {
    my ($self) = @_;
    return (
        sort {
            $self->{directives}->{$a}->{rank}
              <=> $self->{directives}->{$b}->{rank}
        } ( keys %{ $self->{directives} } )
    );
}

sub set_directive {
    my ( $self, $key, $value, $rank ) = @_;
    $rank = $self->max_rank() + 1 if ( !defined($rank) );
    debug "Setting directive {$rank} $key = $value";
    $self->{directives}->{$key} = { def => $value, rank => $rank };
}

sub directives_from_parse {
    my ( $self, $parsed ) = @_;
    my $rank = $self->max_rank() + 1;
    for my $d (@$parsed) {
        $self->set_directive( $d->{key}, $d->{value}, $rank++ );
    }
}

sub process_directives {
    my ( $self, $string ) = @_;
    $self->directives_from_parse( $self->parse_defs($string) );
}

sub evaluate {
    my ( $self, $string ) = @_;

    if ( !defined($string) ) {
        debug "Value is undef";
        return (undef);
    }
    if ( $string eq '' ) {
        debug "Value is empty";
        return ('');
    }

    my $string_orig = $string;
    for my $vv ( keys %{ $self->{variables} } ) {
        my $value = $self->get_variable($vv);
        if ( defined($value) ) {
            if ( $value eq "" ) {
                $string =~ s/\b$vv\b/''/g;
            } else {
                $string =~ s/\b$vv\b/$value/g;
            }
        } else {
            $string =~ s/\b$vv\b/undef/g;
        }
    }
    my $calc = eval($string);
    $self->error("Syntax error (evaluation of $string): $@")
      if ($@);
    debug "Evaluation ["
      . printable( $self->{type} ) . "] : "
      . printable($string_orig) . " => "
      . printable($string) . " => "
      . printable($calc)
      if ( !defined($calc) || $string_orig ne $calc );

    return ($calc);
}

sub defined_directive {
    my ( $self, $key ) = @_;
    return ( $self->{directives}->{$key} );
}

sub get_directive_raw {
    my ( $self, $key ) = @_;
    if ( $self->{directives}->{$key} ) {
        return ( $self->{directives}->{$key}->{def} );
    } else {
        return (undef);
    }
}

sub get_directive {
    my ( $self, $key ) = @_;

    if ( $self->{directives}->{$key} ) {
        if ( !$self->{directives}->{$key}->{evaluated} ) {
            debug "Evaluate directive $key";
            $self->{directives}->{$key}->{value} =
              $self->evaluate( $self->{directives}->{$key}->{def} );
            $self->{directives}->{$key}->{evaluated} = 1;
        }
        return ( $self->{directives}->{$key}->{value} );
    } else {
        return (undef);
    }
}

1;


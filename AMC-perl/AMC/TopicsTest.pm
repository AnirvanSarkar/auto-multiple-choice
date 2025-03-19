#
# Copyright (C) 2025 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::TopicsTest;

use Scalar::Util qw(looks_like_number);
use Hash::Merge;

use Module::Load;
use Module::Load::Conditional qw/check_install/;

use AMC::Basic;
use AMC::TopicsTestResult;

BEGIN {
    use Exporter ();
    our ( $VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS );

    @ISA = qw(Exporter);
    @EXPORT =
        qw( &check_topics_main_file );
    %EXPORT_TAGS = ();    # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK = qw();
}

my $merger = Hash::Merge->new('LEFT_PRECEDENT');

sub check_yaml_module {
    if ( check_install( module => 'YAML::Syck' ) ) {
	load('YAML::Syck');
	$YAML::Syck::ImplicitTyping = 1;
	$YAML::Syck::ImplicitUnicode = 1;
	return "";
    } else {
	return "Unable to load perl module YAML::Syck";
    }
}

sub check_yaml_load {
    my ($file, $errors) = @_;

    debug ":loading YAML $file";

    my $content;
    eval { $content = YAML::Syck::LoadFile($file); };
    my $err_msg = $@;
    chomp($err_msg);

    if($err_msg) {
	if($err_msg =~ /Syck parser \((.*)\): (.*) at \//) {
	    my $position = $1;
	    my $error = $2;
	    $err_msg = "$error ($position)";
	}
        $errors->add_error("", $file,
                  sprintf(__("Error loading YAML file: %s"), $err_msg));
        return {};
    } else {
        if(ref($content) eq 'HASH' &&
           $content->{topics} && ref($content->{topics}) eq 'ARRAY') {
            for my $t (@{$content->{topics}}) {
                if(ref($t) eq 'HASH' && $t->{conf}) {
                    $t->{conf} = [$t->{conf}] if(!ref($t->{conf}));
                    if(ref($t->{conf}) eq 'ARRAY') {
                        $content->{__local__} = {} if(!$content->{__local__});
                        $content->{__local__}->{conf} = []
                            if(!$content->{__local__}->{conf});
                        for my $c (@{$t->{conf}}) {
                            push @{$content->{__local__}->{conf}},
                                { file=>$file,
                                  topic_id=>$t->{id},
                                  conf=>$c
                                };
                        }
                    }
                }
            }
        }
        
	return $content;
    }
}

sub check_value {
    my ($x, $conditions, $prefix, $file, $errors) = @_;

    debug "[$file] $prefix?\n";
    
    if($conditions->{strlist}) {
	my @values = map { s/^\s+//; s/\s+$//; $_; } split(/,/, $x);
	for my $v (@values) {
	    if(!(grep { $v eq $_ } (@{$conditions->{strlist}}))) {
		$errors->add_error($prefix, $file, sprintf(__('Unexpected value: "%s"'), $v));
	    }
	}
    }
    if($conditions->{options}) {
	if(!(grep { $x eq $_ } (@{$conditions->{options}}))) {
	    $errors->add_error($prefix, $file, sprintf(__('Unexpected value: "%s"'), $x));
	}
    }
    if($conditions->{hash}) {
	check_hash($x, $conditions->{hash}, $prefix, $file, $errors);
    }
    if($conditions->{array}) {
	check_array($x, $conditions->{array}, $prefix, $file, $errors);
    }
    if($conditions->{scalarorarray}) {
        if(ref($x) eq 'ARRAY') {
            check_array($x, $conditions->{scalarorarray}, $prefix, $file, $errors);
        } elsif(ref($x) eq '') {
            check_value($x, $conditions->{scalarorarray}, $prefix, $file, $errors);
        } else {
            $errors->add_error($prefix, $file, __"Should be a list");
        }
    }
    if($conditions->{str}) {
        if(ref($x) ne '') {
            $errors->add_error($prefix, $file, __"String expected");
        }
    }
    for my $c (qw/boolean numeric integer regex/) {
        if ( $conditions->{$c} ) {
            $errors->add_error( $prefix, $file,
                __"Single value expected, but got a list" )
              if ( ref($x) eq 'ARRAY' );
            $errors->add_error( $prefix, $file,
                __"Single value expected, but got parameters" )
              if ( ref($x) eq 'HASH' );
            $errors->add_error( $prefix, $file, __"Single value expected" )
              if ( ref($x) );
        }
    }
    if($conditions->{boolean}) {
        unless($x eq '0' || $x eq '1') {
            $errors->add_error($prefix, $file, __"Boolean expected (0 or 1)");
        }
    }
    if($conditions->{numeric}) {
        unless(looks_like_number($x)) {
            $errors->add_error($prefix, $file, __"Numerical value expected");
        }
    }
    if($conditions->{integer}) {
        unless($x =~ /^\s*-?[0-9]+\s*$/) {
            $errors->add_error($prefix, $file, __"Integer value expected");
        }
    }
    if($conditions->{regex}) {
        unless($x =~ /$conditions->{regex}/) {
            $errors->add_error($prefix, $file, __"Unexpected value");
        }
    }
}

sub check_array {
    my ($x, $keys, $prefix, $file, $errors) = @_;
    if(ref($x) ne 'ARRAY') {
	$errors->add_error($prefix, $file, __"Should be a list");
    }
    my $i = 1;
    for my $v (@$x) {
        $prefix =~ s/ \/ $//;
	check_value($v, $keys, $prefix . "[$i] / ", $file, $errors);
	$i++;
    }
}

sub check_hash {
    my ($x, $keys, $prefix, $file, $errors) = @_;
    if(ref($x) ne 'HASH') {
	$errors->add_error($prefix, $file, __"Should contain parameters");
    }
    my $x_keys = {};
    for my $k (keys(%$x)) {
	$x_keys->{$k} = 1;
    }
    for my $k (keys(%$keys)) {
	if($keys->{$k}->{force} &&
	   ! exists($x->{$k})) {
	    $errors->add_error($prefix, $file, sprintf(__('Should contain parameter "%s"'), $k));
	}
	if(exists($x->{$k})) {
	    check_value($x->{$k}, $keys->{$k}, $prefix . "$k / ", $file, $errors);
	}
	delete($x_keys->{$k});
    }
    if($keys->{_ALL}) {
        for my $k (keys %$x) {
            check_value($x->{$k}, $keys->{_ALL}, $prefix . "$k / ", $file, $errors);
        }
    }
    my @unknown = (keys %$x_keys);
    if(@unknown && ! $keys->{_ALL}) {
	$errors->add_error($prefix, $file, sprintf(__('Unexpected parameters: %s'), join(', ', @unknown)));
    }
}

my $level_conditions = {
    min     => { numeric => 1 },
    max     => { numeric => 1 },
    code    => { str     => 1 },
    color   => { str     => 1 },
    message => { str     => 1 },
};

my $topic_conditions = {
    id        => { str           => 1 },
    name      => { str           => 1 },
    questions => { scalarorarray => { str  => 1 } },
    conf      => { scalarorarray => { str  => 1 } },
    levels    => { array         => { hash => $level_conditions } },
    aggregate => {
            regex => '^('
          . 'count\(([\d.]+)(?:,([\d.]+))?\)'
          . '|sumscores'
          . '|sumratios'
          . '|(min|max)(score|ratio)' . ')$'
    },
    value          => { regex   => '^(score|ratio)(:.*)?$' },
    format         => { str     => 1 },
    decimals       => { integer => 1 },
    decimalsratio  => { integer => 1 },
    decimalspc     => { integer => 1 },
    text           => { str     => 1 },
    color          => { str     => 1 },
    floor          => { numeric => 1 },
    ceil           => { numeric => 1 },
    annotate_color => { str     => 1 },
};

my $content_conditions = {
    preferences => {
        hash => {
            answered_only     => { boolean => 1 },
            decimal_separator => { str     => 1 },
            intervapsep       => { str     => 1 },
            odscolumns        => { strlist => [ 'level', 'value' ] },
            pc_suffix         => { str     => 1 },
            skip_indicatives  => { boolean => 1 },
        }
    },
    conf      => { hash          => { _ALL => { hash => $topic_conditions } } },
    include   => { scalarorarray => { str  => 1 } },
    topics    => { array         => { hash => $topic_conditions } },
    __local__ => {},
};

sub check_topics_file {
    my ($topics_file, $errors) = @_;

    my $content = check_yaml_load($topics_file, $errors);

    check_hash( $content, $content_conditions, "", $topics_file, $errors );

    if ( $content->{include} ) {
        if ( !ref( $content->{include} ) ) {
            $content->{include} = [ $content->{include} ];
        }
        my ( $volume, $directories, undef ) =
          File::Spec->splitpath($topics_file);
        my $base = File::Spec->catpath( $volume, $directories );
        $content->{include} =
          [ map { File::Spec->rel2abs( $_, $base ); }
              @{ $content->{include} } ];
        for my $f ( @{ $content->{include} } ) {
            if ( -f $f ) {
                my $y = check_topics_file($f, $errors);
                $content = $merger->merge( $content, $y );
            }
            else {
                $errors->add_error("", $topics_file,
                                   sprintf(__("Included file not found: %s"),
                                           $f)
                                  );
            }
        }
    }

    return $content;
}

sub check_topics_main_file {
    my ($topics_file) = @_;

    my $errors = AMC::TopicsTestResult->new();

    if(!-f $topics_file) {
        return $errors;
    }

    my $e = check_yaml_module();
    if($e) {
        $errors->add_global_error($e);
        return $errors;
    }

    # check syntax of YAML files
    my $x;
    eval {
        $x = check_topics_file( $topics_file, $errors );
    };
    if ($@) {
        $errors->add_global_error( sprintf( __("Internal error: %s"), $@ ) );
        return $errors;
    }

    # check that there exists at least one topic
    unless ( ref($x) eq 'HASH'
        && ref( $x->{topics} ) eq 'ARRAY'
        && @{ $x->{topics} } )
    {
        $errors->add_global_error( __"No topic found in topics.yml file" );
    }

    # check that all conf: exist
    if($x->{__local__} && $x->{__local__}->{conf}) {
        for my $c (@{$x->{__local__}->{conf}}) {
            unless ( $x->{conf} && $x->{conf}->{$c->{conf}} ) {
                $errors->add_error( "topic / $c->{topic_id}", $c->{file},
                                    sprintf( __('Missing configuration "%s"'), $c->{conf} ) );
            }
        }
    }

    return $errors;
}

1;

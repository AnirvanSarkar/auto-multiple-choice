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

package AMC::TopicsTestResult;

sub new {
    my ( $class, $errors ) = @_;

    $errors = {} if(!$errors);

    my $self = { errors=>$errors };

    bless( $self, $class );

    return $self;
}

sub add_error {
    my ( $self, $prefix, $file, $message ) = @_;
    my $index = scalar(%{$self->{errors}});
    $index           = 1000                     if ( $file eq '__global__' );
    $errors->{$file} = { e => [], i => $index } if ( !$errors->{$file} );
    $prefix =~ s/[\s\/]+$//;

    push @{ $self->{errors}->{$file}->{e} },
        { prefix => $prefix, message => $message };
}


sub add_global_error {
    my ($self, $message) = @_;
    $self->add_error("", "__global__", $message);
}

sub failed {
    my ($self) = @_;
    return(scalar(%{$self->{errors}}));
}

sub topics_single_error_to_string {
    my ($e) = @_;
    if($e->{prefix}) {
        return "[$e->{prefix}] $e->{message}";
    } else {
        return $e->{message};
    }
}

my $tef = {
           text=>{before_file=>"* ", after_file=>"\n",
                  begin_errs=>'', end_errs=>'',
                  before_err=>'', after_err=>"\n",
                 },
           html=>{before_file=>"<b>", after_file=>"</b>\n",
                  begin_errs=>"<ul>\n", end_errs=>"</ul>\n",
                  before_err=>"<li>", after_err=>"</li>\n",
                 },
           pango=>{before_file=>"<b>", after_file=>"</b>\n",
                   begin_errs=>"", end_errs=>"",
                   before_err=>"", after_err=>"\n",
                  },
           };

sub to_string {
    my ( $self, $format ) = @_;
    my $s = $tef->{$format} || $tef->{text};
    if ( $self->failed() ) {
        my $text = '';
        for my $file (
            sort { $self->{errors}->{$a}->{i} <=> $self->{errors}->{$b}->{i} }
            ( keys %{ $self->{errors} } ) )
        {
            $text .= $s->{before_file};
            if ( $file eq '__global__' ) {
                $text .= "Global:";
            } else {
                $text .= sprintf( "In file %s:", $file );
            }
            $text .= $s->{after_file};
            $text .= $s->{begin_errs};
            $text .= join(
                "",
                map {
                        $s->{before_err}
                      . topics_single_error_to_string($_)
                      . $s->{after_err}
                } ( @{ $self->{errors}->{$file}->{e} } )
            );
            $text .= $s->{end_errs};
        }
        return $text;
    } else {
        return "Valid";
    }
}

1;



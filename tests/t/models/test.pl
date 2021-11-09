#! /usr/bin/env perl
#
# Copyright (C) 2021 Alexis Bienvenüe <paamc@passoire.fr>
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

require "./AMC/Test.pm";

use File::Spec;
use Cwd qw(getcwd abs_path);
use File::Temp qw(tempdir);
use AMC::Config;

my $t = AMC::Test->new( setup => 0, exitonerror => 0 );

my @select_models=@ARGV;

my $cwd = getcwd();
my ( $script_volume, $script_directory, undef ) =
  File::Spec->splitpath(__FILE__);
chdir( File::Spec->catpath( $script_volume, $script_directory ) );
my $models_base = abs_path("../../../doc/modeles");
chdir($cwd);

my $errors = 0;
my @failed = ();

sub one_tgz {
    my ($model_tgz) = @_;

    my $short_model = $model_tgz;
    $short_model =~ s:.*/([^/]+/[^/]+)$:$1:;
    $t->trace("[I] Model: $short_model");

    my $temp_dir = tempdir( CLEANUP => ( !$t->{debug} ) );
    my ( $temp_vol, $temp_d, $temp_n ) = File::Spec->splitpath($temp_dir);

    chdir($temp_dir);
    system( "tar", "xf", $model_tgz );

    my $conf = AMC::Config::new();
    $conf->set_global_options_to_default();
    $conf->set_project_options_to_default();
    $conf->set( rep_projets => File::Spec->catpath( $temp_vol, $temp_d ) );

    my $options_file = $conf->project_options_file($temp_n);
    if ( -f $options_file ) {
        $conf->open_project($temp_n);
    }

    $t->clean();
    $t->set(
        error      => 0,
        dir        => $temp_dir,
        tex_engine => $conf->get('moteur_latex_b'),
        filter     => $conf->get('filter'),
    );
    $t->setup();

    $t->default_process();

    if($t->{error}) {
        push @failed, $short_model;
    }
    $errors += $t->{error};
}

if(@select_models) {

    for my $m (@select_models) {
        if(!-d $m) {
            $m="$models_base/$m";
        }
        one_tgz($m);
    }

} else {

    opendir( my $dh, $models_base ) || die "Can't opendir $models_base: $!";
    my @groups = grep { !/^\./ && -d "$models_base/$_" } readdir($dh);
    closedir $dh;

    for my $g (@groups) {

        my $group_dir = "$models_base/$g";

        opendir( my $dh, $group_dir ) || die "Can't opendir $group_dir: $!";
        my @models =
            grep { !/^\./ && /\.tgz$/i && -f "$group_dir/$_" } readdir($dh);
        closedir $dh;

        for my $m (@models) {
            one_tgz("$group_dir/$m");
        }
    }

}

for my $f (@failed) {
    $t->trace("[F] Failed: $f");
}

exit($errors);

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

package AMC::Gui::CreateProject;

use parent 'AMC::Gui';

use AMC::Basic;
use AMC::Encodings;

use File::Copy;
use Archive::Tar;
use XML::Simple;
use Gtk3;
use Glib;

use constant {
    MODEL_NOM  => 0,
    MODEL_PATH => 1,
    MODEL_DESC => 2,
};

use_gettext();

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            filter_modules => []
        },
        %oo
    );

    return $self;
}

###########################################################################
# OPTION
###########################################################################

# let the user choose a creation option

sub create_option {
    my ($self) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/Option.glade/i;

    $self->read_glade(
        $glade_xml,
        qw/source_latex_dialog
          sl_type_new sl_type_choix sl_type_vide sl_type_zip/
    );

    my $dialog = $self->get_ui('source_latex_dialog');

    my $response = $dialog->run();
    my $option   = '';

    if ( $response == 10 ) {
        for (qw/new choix vide zip/) {
            if ( $self->get_ui( 'sl_type_' . $_ )->get_active() ) {
                debug "Button $_";
                $option = $_;
            }
        }
    }

    $dialog->destroy();

    debug "RESPONSE=$response";
    debug "OPTION=$option";
    return ($option);
}

###########################################################################
# MODELS MANAGEMENT
###########################################################################

# Let the user choose a model

sub select_model {
    my ($self) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/Model.glade/i;

    $self->read_glade(
        $glade_xml,
        qw/source_latex_modele
          modeles_liste modeles_description
          model_choice_button mlist_separation/
    );

    $self->get_ui('source_latex_modele')->show();

    $self->{models_store} =
      Gtk3::TreeStore->new( 'Glib::String', 'Glib::String', 'Glib::String' );

    $self->load_models( undef, $self->get('rep_modeles') )
      if ( $self->get('rep_modeles') );

    $self->load_models( undef, amc_specdir('models') );

    $self->get_ui('modeles_liste')->set_model( $self->{models_store} );

    my $renderer = Gtk3::CellRendererText->new;

    my $column = Gtk3::TreeViewColumn->new_with_attributes(
        __(
            # TRANSLATORS: This is a column name for the list of available
            # templates, when creating a new project based on a template.
            "template"
        ),
        $renderer,
        text => MODEL_NOM
    );
    $self->get_ui('modeles_liste')->append_column($column);

    $self->get_ui('mlist_separation')
      ->set_position(
        .5 * $self->get_ui('mlist_separation')->get_property('max-position') );

    my $response = $self->get_ui('source_latex_modele')->run();

    debug "Dialog modele : $response";

    my $mod;

    if ($response) {
        my $iter =
          $self->get_ui('modeles_liste')->get_selection()->get_selected();
        $mod = $self->{models_store}->get( $iter, MODEL_PATH ) if ($iter);
    }

    $self->get_ui('source_latex_modele')->destroy();

    if ( $response == 10 ) {
        return ($mod);
    } else {
        return ('');
    }
}

sub model_description {
    my ($self) = @_;
    my $iter = $self->get_ui('modeles_liste')->get_selection()->get_selected();
    my $desc = '';
    my $is_model = '';

    if ($iter) {
        $desc     = $self->{models_store}->get( $iter, MODEL_DESC );
        $is_model = ( $self->{models_store}->get( $iter, MODEL_PATH ) ? 1 : 0 );
    }
    $self->get_ui('modeles_description')->get_buffer->set_text($desc);
    $self->get_ui('model_choice_button')->set_sensitive($is_model);
}

sub load_models {
    my ( $self, $parent, $rep ) = @_;

    return if ( !-d $rep );

    my @all;
    my @ms;
    my @subdirs;

    if ( opendir( DIR, $rep ) ) {
        @all     = readdir(DIR);
        @ms      = grep { /\.tgz$/ && -f $rep . "/$_" } @all;
        @subdirs = grep { -d $rep . "/$_" && !/^\./ } @all;
        closedir DIR;
    } else {
        debug("MODELS : Can't open directory $rep : $!");
    }

    for my $sd ( sort { $a cmp $b } @subdirs ) {
        my $nom       = $sd;
        my $desc_text = '';

        my $child = $self->{models_store}->append($parent);
        if ( -f $rep . "/$sd/directory.xml" ) {
            my $d = XMLin( $rep . "/$sd/directory.xml" );
            $nom       = $d->{title} if ( $d->{title} );
            $desc_text = $d->{text}  if ( $d->{text} );
        }
        $self->{models_store}->set( $child, MODEL_NOM, $nom, MODEL_PATH, '',
            MODEL_DESC, $desc_text );
        $self->load_models( $child, $rep . "/$sd" );
    }

    for my $m ( sort { $a cmp $b } @ms ) {
        my $nom = $m;
        $nom =~ s/\.tgz$//i;
        my $desc_text = __ "(no description)";
        my $tar       = Archive::Tar->new();
        if ( $tar->read( $rep . "/$m" ) ) {
            my @desc = grep { /description.xml$/ } ( $tar->list_files() );
            if ( $desc[0] ) {
                my $d =
                  XMLin( $tar->get_content( $desc[0] ), SuppressEmpty => '' );
                $nom       = $d->{title} if ( $d->{title} );
                $desc_text = $d->{text}  if ( $d->{text} );
            }
            debug "Adding model $m";
            debug "NAME=$nom DESC=$desc_text";
            $self->{models_store}->set(
                $self->{models_store}->append($parent),
                MODEL_NOM, $nom, MODEL_PATH, $rep . "/$m",
                MODEL_DESC, $desc_text
            );
        } else {
            debug_and_stderr
              "WARNING: Could not read archive file \"$rep/$m\" ...";
        }
    }
}

###########################################################################
# CREATE FROM FILE
###########################################################################

sub choose_file {
    my ($self) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/File.glade/i;

    $self->read_glade( $glade_xml,
        qw/source_latex_choix source_latex_chooser/ );

    $self->get_ui('source_latex_chooser')
      ->set_current_folder( Glib::get_home_dir() );

    # default filter: all possible source files

    my $filtre_all = Gtk3::FileFilter->new();
    $filtre_all->set_name( __ "All source files" );
    for my $m (@{$self->{filter_modules}}) {
        for my $p ( "AMC::Filter::register::$m"->file_patterns ) {
            $filtre_all->add_pattern($p);
        }
    }
    $self->get_ui('source_latex_chooser')->add_filter($filtre_all);

    # filters for each filter module

    for my $m (@{$self->{filter_modules}}) {
        my $f = Gtk3::FileFilter->new();

        my @pat = ();
        for my $p ( "AMC::Filter::register::$m"->file_patterns ) {
            push @pat, $p;
            $f->add_pattern($p);
        }
        $f->set_name(

            sprintf(
                __(
          # TRANSLATORS: This is the label of a choice in a menu to select only
          # files that corresponds to a particular format (which can be LaTeX or
          # Plain for example). %s will be replaced by the name of the format.
                    "%s files"
                ),
                "AMC::Filter::register::$m"->name()
              )
              . ' ('
              . join( ', ', @pat ) . ')'
        );
        $self->get_ui('source_latex_chooser')->add_filter($f);
    }

    my $response = $self->get_ui('source_latex_choix')->run();
    my $f        = '';

    if ( $response == 10 ) {
        $f = clean_gtk_filenames(
            $self->get_ui('source_latex_chooser')->get_filename() );
    }

    $self->get_ui('source_latex_choix')->destroy();

    return ($f);
}

###########################################################################
# CREATE FROM ARCHIVE
###########################################################################

sub choose_zip {
    my ($self) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/Zip.glade/i;

    $self->read_glade( $glade_xml,
        qw/source_latex_choix_zip source_latex_chooser_zip/ );

    $self->get_ui('source_latex_chooser_zip')
      ->set_current_folder( Glib::get_home_dir() );

    my $filtre_zip = Gtk3::FileFilter->new();
    $filtre_zip->set_name( __ "Archive (zip, tgz)" );
    $filtre_zip->add_pattern("*.zip");
    $filtre_zip->add_pattern("*.tar.gz");
    $filtre_zip->add_pattern("*.tgz");
    $filtre_zip->add_pattern("*.TGZ");
    $filtre_zip->add_pattern("*.ZIP");
    $self->get_ui('source_latex_chooser_zip')->add_filter($filtre_zip);

    my $response = $self->get_ui('source_latex_choix_zip')->run();

    my $f = '';
    if ( $response == 10 ) {
        $f = clean_gtk_filenames(
            $self->get_ui('source_latex_chooser_zip')->get_filename() );
    }

    $self->get_ui('source_latex_choix_zip')->destroy();

    return ($f);
}

###########################################################################
# CHOOSE AND INSTALL SOURCE FILE
###########################################################################

sub install_source {
    my ($self, %oo) = @_;

    my $texsrc = '';

    if ( !$oo{nom} ) {
        debug "ERR: Empty name for source_latex_choisir";
        return ( 0, '' );
    }

    if ( -e $self->get('rep_projets') . "/" . $oo{nom} ) {
        debug
          "ERR: existing project directory $oo{nom} for install_source";
        return ( 0, '' );
    }

    my $option = '';

    if ( $oo{type} ) {
        $option = $oo{type};
    } else {
        $option = $self->create_option();
    }

    return ( 0, '' ) if ( !$option );

    # actions apres avoir choisi le type de source latex a utiliser

    if ( $option eq 'new' ) {

        my $mod = $self->select_model();

        return ( 0, '' ) if ( !$mod );

        if ($mod) {
            debug "Installing model $mod";
            return (
                $self->install_source(
                    type   => 'zip',
                    fich   => $mod,
                    decode => 1,
                    nom    => $oo{nom}
                )
            );
        } else {
            debug "No model";
            return ( 0, '' );
        }

    } elsif ( $option eq 'choix' ) {

        my $f = $self->choose_file();

        return ( 0, '' ) if ( !$f );

        $texsrc = $self->relatif( $f, $oo{nom} );
        debug "Source LaTeX $f";

    } elsif ( $option eq 'zip' ) {

        my $fich;

        if ( $oo{fich} ) {
            $fich = $oo{fich};
        } else {

            $fich = $self->choose_zip();

            return ( 0, '' ) if ( !$fich );
        }

        # unzip in temporary directory

        my ( $temp_dir, $rv ) = unzip_to_temp($fich);

        my ( $n, $suivant ) = n_fich($temp_dir);

        if ( $rv || $n == 0 ) {
            my $dialog =
              Gtk3::MessageDialog->new( $self->{parent_window}, 'destroy-with-parent',
                'error', 'ok', '' );
            $dialog->set_markup(
                sprintf(
                    __ "Nothing extracted from archive %s. Check it.",
                    $fich
                )
            );
            $dialog->run;
            $dialog->destroy;
            return ( 0, '' );
        } else {

            # unzip OK
            # remove intermediary directories

            while ( $n == 1 && -d $suivant ) {
                debug "Changing root directory : $suivant";
                $temp_dir = $suivant;
                ( $n, $suivant ) = n_fich($temp_dir);
            }

            # move all files

            my $hd = $self->get('rep_projets') . "/" . $oo{nom};

            mkdir($hd) if ( !-e $hd );

            my @archive_files;

            if ( opendir( MVR, $temp_dir ) ) {
                @archive_files = grep { !/^\./ } readdir(MVR);
                closedir(MVR);
            } else {
                debug("ARCHIVE : Can't open $temp_dir : $!");
            }

            my $latex;

            for my $ff (@archive_files) {
                debug "Moving to project: $ff";
                if ( $ff =~ /\.tex$/i ) {
                    $latex = $ff;
                    if ( $oo{decode} ) {
                        debug "Decoding $ff...";
                        move( "$temp_dir/$ff", "$temp_dir/$ff.0enc" );
                        $self->copy_latex( "$temp_dir/$ff.0enc", "$temp_dir/$ff" );
                    }
                }
                if ( system( "mv", "$temp_dir/$ff", "$hd/$ff" ) != 0 ) {
                    debug "ERR: Move failed: $temp_dir/$ff --> $hd/$ff -- $!";
                    debug "(already exists)" if ( -e "$hd/$ff" );
                }
            }

            if ($latex) {
                $texsrc = "%PROJET/$latex";
                debug "LaTeX found : $latex";
            }

            return ( 2, $texsrc );
        }

    } elsif ( $option eq 'vide' ) {

        my $hd = $self->get('rep_projets') . "/" . $oo{nom};

        mkdir($hd) if ( !-e $hd );

        $texsrc = 'source.tex';
        my $sl = "$hd/$texsrc";

    } else {
        return ( 0, '' );
    }

    return ( 1, $texsrc );

}

# copy a latex source file, with new encoding

sub copy_latex {
    my ($self, $src, $dest, $new_encoding) = @_;

    if(!$new_encoding) {
        $new_encoding = $self->get('encodage_latex');
    }

    # 1) find current encoding
    
    my $i = '';
    open( SRC, $src );
  LIG: while (<SRC>) {
        s/%.*//;
        if (/\\usepackage\[([^\]]*)\]\{inputenc\}/) {
            $i = $1;
            last LIG;
        }
    }
    close(SRC);

    # 2) copy and change encoding

    my $ie = get_enc($i);
    my $id = get_enc( $new_encoding );
    
    if ( $ie && $id && $ie->{iso} ne $id->{iso} ) {
        debug "Reencoding $ie->{iso} => $id->{iso}";
        open( SRC,  "<:encoding($ie->{iso})", $src ) or return ('');
        open( DEST, ">:encoding($id->{iso})", $dest )
          or close(SRC), return ('');
        while (<SRC>) {
            chomp;
s/\\usepackage\[([^\]]*)\]\{inputenc\}/\\usepackage[$id->{inputenc}]{inputenc}/;
            print DEST "$_\n";
        }
        close(DEST);
        close(SRC);
        return (1);
    } else {
        return ( copy( $src, $dest ) );
    }
}

1;

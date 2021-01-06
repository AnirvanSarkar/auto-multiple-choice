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

package AMC::Gui::ProjectManager;

use parent 'AMC::Gui';

use File::Spec::Functions qw/splitpath/;
use File::Path qw/remove_tree/;
use File::Copy;
use File::Find;
use AMC::Basic;

use Gtk3;

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            action             => '',
            current_project    => '',
            local_projects_dir => '',
            callback_self      => '',
            open_callback      => '',
            new_callback       => '',
            progress_widget    => '',
            command_widget     => '',
        },
        %oo
    );

    if ( $self->{action} ) {
        $self->projects_list_window();
    }

    return $self;
}

# Open new window with existing projects list

sub projects_list_window {
    my ($self) = @_;

    $self->{local_projects_dir} = $self->get_absolute('rep_projets');
    $self->{local_projects_dir} = $self->get_absolute('projects_home')
      if ( !( $self->{local_projects_dir} && -d $self->{local_projects_dir} ) );

    if ( !-d $self->{local_projects_dir} ) {
        debug "Create projects directory: $self->{local_projects_dir}";
        mkdir( $self->{local_projects_dir} );
    }

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade(
        $glade_xml, qw/choix_projet label_etat label_action
          choix_projets_liste
          projet_select_directory
          projet_bouton_ouverture projet_bouton_creation
          projet_bouton_supprime projet_bouton_annule
          projet_bouton_annule_label projet_bouton_renomme
          projet_bouton_clone
          projet_bouton_mv_yes projet_bouton_mv_no
          projet_nom projet_nouveau_syntaxe projet_nouveau/
    );

    if ( $self->{action} eq 'new' ) {
        $self->get_ui('projet_nouveau')->show();
        $self->get_ui('projet_bouton_creation')->show();
        $self->get_ui('projet_bouton_ouverture')->hide();

        $self->get_ui('label_etat')->set_text( __ "Existing projects:" );

        $self->get_ui('choix_projet')->set_focus( $self->get_ui('projet_nom') );

        $self->get_ui('choix_projet')->set_title(
            __
              # TRANSLATORS: Window title when creating a new project.
              "New AMC project"
        );
    }

    if ( $self->{action} eq 'manage' ) {
        $self->get_ui('label_etat')->set_text( __ "Projects management:" );
        $self->get_ui('label_action')->set_markup( __ "Change project name:" );
        $self->get_ui('projet_bouton_ouverture')->hide();
        for (qw/supprime clone renomme/) {
            $self->get_ui( 'projet_bouton_' . $_ )->show();
        }
        $self->get_ui('projet_bouton_annule_label')->set_text( __ "Back" );

        $self->get_ui('choix_projet')->set_title(
            __
              # TRANSLATORS: Window title when managing projects.
              "AMC projects management"
        );
    }

    # keep same size as last time used

    if ( $self->get('conserve_taille') ) {
        AMC::Gui::WindowSize::size_monitor(
            $self->get_ui('choix_projet'),
            {
                config => $self->{config},
                key    => 'global:projects_list_window_size'
            }
        );
    }

    $self->get_ui('projet_select_directory')
      ->set_current_folder( $self->{local_projects_dir} );
    $self->get_ui('choix_projet')->show;
}

# update UI with changed directory (signal from filechooser)

sub set_directory {
    my ( $self, $filechooser ) = @_;
    my $directory = clean_gtk_filenames( $filechooser->get_filename()
          || $filechooser->get_current_folder() );
    debug "Changed directory: " . show_utf8($directory);
    $self->{local_projects_dir} = $directory;
    $self->set_relatif_os( 'rep_projets', $directory );
    $self->projects_update_list();
}

# get directories list (either AMC poject directories and other
# directories) in current directory

sub projects_list {
    my ($self) = @_;
    debug "Projects list: " . show_utf8( $self->{local_projects_dir} );
    if ( -d $self->{local_projects_dir} ) {
        my @f = dir_contents_u( $self->{local_projects_dir} );
        debug "F:"
          . join( ',',
            map { $_ . ":" . ( -d $self->{local_projects_dir} . "/" . $_ ) }
              @f );

        my @projs =
          grep { !/^\./ && -d $self->{local_projects_dir} . "/" . $_ } @f;
        debug "[" . $self->{local_projects_dir} . "] P:" . join( ',', @projs );
        return (@projs);
    }
}

# create a project widget (label and icon)

sub create_project_widget {
    my ( $self, $item ) = @_;
    my $label = Gtk3::Label->new( $item->{label} );
    my $icon  = Gtk3::Image->new_from_icon_name( $item->{icon}, 'menu' );
    my $box   = Gtk3::Box->new( 'horizontal', 2 );
    $box->add($icon);
    $box->add($label);
    $box->{_amc_project_data} = {%$item};
    return $box;
}

# get the options file path for directory $name. If his file exists,
# the directory is a AMC project, and if not, this is a standard
# directory

sub options_file {
    my ( $self, $name ) = @_;

    my $of = $self->{local_projects_dir};
    $of .= "/$name/options.xml";

    debug "Options file: " . show_utf8($of);

    return ($of);
}

# Updates the UI with the list of sub-directories in the current directory

sub projects_update_list {
    my ( $self, $p ) = @_;
    $p = [ $self->projects_list() ] if ( !$p );

    # first remove all entries...
    $self->get_ui('choix_projets_liste')
      ->foreach( sub { my ($child) = @_; $child->destroy() } );

    #
    my $up = $self->{local_projects_dir};
    if ( $up ne '/' ) {
        $up =~ s:/[^/]*/?$::;

        $self->get_ui('choix_projets_liste')->add(
            $self->create_project_widget(
                {
                    label => "..",
                    name  => "..",
                    path  => $up,
                    icon  => "inode-directory",
                }
            )
        );
    }

    # $prefix is the <LTR> UTF8 character in RTL environments.
    my $prefix = (
        $self->{parent_window}->get_direction() eq 'rtl'
        ? decode( "utf-8", "\xe2\x80\x8e" )
        : ''
    );
    for my $proj_name ( sort { $a cmp $b } @$p ) {
        my $is_amc     = ( -f $self->options_file($proj_name) );
        my $name_plain = $proj_name;
        my $label      = $proj_name = Glib::filename_display_name($proj_name);
        $label = $prefix . $label if ( $proj_name =~ /^[0-9]*$/ );
        debug "Directory: " . show_utf8($label) . ( $is_amc ? " (AMC)" : "" );

        $self->get_ui('choix_projets_liste')->add(
            $self->create_project_widget(
                {
                    label => $label,
                    name  => $proj_name,
                    path  => $self->{local_projects_dir} . "/" . $proj_name,
                    icon  => (
                        $is_amc
                        ? "auto-multiple-choice"
                        : "inode-directory"
                    )
                }
            )
        );
    }

    $self->get_ui('choix_projets_liste')->show_all;
}

# Get the name of the selected directory in the list

sub get_selected_project {
    my ($self) = @_;
    my $sel_items =
      $self->get_ui('choix_projets_liste')->get_selected_children();
    return if ( !@$sel_items );
    my $proj = $sel_items->[0]->get_child()->{_amc_project_data}->{name};
    return ($proj);
}

# callback from the Cancel button: closes the window

sub cancel {
    my ($self) = @_;
    $self->get_ui('choix_projet')->destroy();
}

# callback from the Open button: opens the project

sub open_ok {
    my ($self) = @_;

    my $project = $self->get_selected_project();
    return if ( !$project );

    $self->{project} = $project;

    $self->get_ui('choix_projet')->destroy();

    Glib::Idle->add( \&open_callback_when_idle, $self, Glib::G_PRIORITY_LOW );
}

sub open_callback_when_idle {
    my ($self) = @_;
    &{ $self->{open_callback} }
        ( $self->{callback_self}, $self->{local_projects_dir}, $self->{project} );

    return(0);
}

# callback called when a directory is selected (double-click in the list)

sub select_item {
    my ( $self, $flowbox, $boxchild ) = @_;
    my $selected_path = $boxchild->get_child->{_amc_project_data}->{name};
    debug "Selected: " . show_utf8($selected_path);
    if ( -f $self->options_file( $selected_path ) ) {

        # an AMC project directory has been selected
        if ( $self->get_ui('projet_bouton_ouverture')->is_visible() ) {
            $self->open_ok();
        }
    } else {

        # move to other directory
        $self->{local_projects_dir} = $self->{local_projects_dir} . "/" . $selected_path;

        debug "Move to directory: " . show_utf8( $self->{local_projects_dir} );

        $self->get_ui('projet_select_directory')
          ->set_filename( $self->{local_projects_dir} );
        $self->get_ui('projet_select_directory')
          ->set_current_folder( $self->{local_projects_dir} );
    }
}

sub check_project_name {
    my ($self) = @_;
    $self->restricted_check(
        $self->get_ui('projet_nom'),
        $self->get_ui('projet_nouveau_syntaxe'),
        "a-zA-Z0-9._+:-"
    );
}

# Callback from the New button

sub new_project {
    my ($self)=@_;

    # get the choosen name for the project and close the window
    my $proj = $self->get_ui('projet_nom')->get_text();
    $self->get_ui('choix_projet')->destroy();

    if ( -e $self->{local_projects_dir} . "/$proj" ) {

        # the name choosen for the new project corresponds to an
        # already existing directory: cancel

        my $dialog =
          Gtk3::MessageDialog->new( $self->{parent_window}, 'destroy-with-parent',
            'error', 'ok', '' );
        $dialog->set_markup(
            sprintf(
                __(
"The name <b>%s</b> is already used in the projects directory."
                  )
                  . " "
                  . __ "You must choose another name to create a project.",
                $proj
            )
        );
        $dialog->run;
        $dialog->destroy;

    } else {

        &{ $self->{new_callback} }
          ( $self->{callback_self}, $self->{local_projects_dir}, $proj );

    }
}

# Check that the selected project is not already opened

sub check {
    my ( $self, $open_ok ) = @_;

    my $project = $self->get_selected_project();

    return ('') if ( !$project );

    return ($project) if ($open_ok);

    # Impossible with current open project

    if ( $self->{current_project} && $project eq $self->{current_project} ) {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('choix_projet'),
            'destroy-with-parent',
            'error', 'ok', __ "You can't change project %s since it's open.",
            $project );
        $dialog->run;
        $dialog->destroy;
        $self->get_ui('choix_projet')->set_keep_above(1);
        $project = '';
    }

    return ($project);
}

# Open a new text field to give a new name to the selected project

sub rename_project {
    my ($self)=@_;
    my ($project) = $self->check();
    return if ( !$project );

    $self->get_ui('projet_nouveau')->show();
    $self->get_ui('projet_nom')->set_text( glib_filename($project) );

    $self->{original_name} = $project;

    # buttons...
    for (qw/annule renomme clone supprime/) {
        $self->get_ui( 'projet_bouton_' . $_ )->hide();
    }
    for (qw/mv_no mv_yes/) {
        $self->get_ui( 'projet_bouton_' . $_ )->show();
    }
}

# clse the text field for renaming

sub close_rename {
    my ($self) = @_;

    # fermeture zone :
    $self->get_ui('projet_nouveau')->hide();

    # boutons...
    for (qw/annule renomme clone supprime/) {
        $self->get_ui( 'projet_bouton_' . $_ )->show();
    }
    for (qw/mv_no mv_yes/) {
        $self->get_ui( 'projet_bouton_' . $_ )->hide();
    }
}

# rename the project

sub rename_ok {
    my ($self) = @_;

    my $new_name = $self->get_ui('projet_nom')->get_text();
    $self->close_rename();

    return if ( $new_name eq $self->{original_name} || !$new_name );

    if ( $self->{local_projects_dir} ) {
        my $dir_original =  $self->{local_projects_dir}. "/" . $self->{original_name};
        if ( -d $dir_original ) {
            my $dir_nouveau = $self->{local_projects_dir} . "/" . $new_name;
            if ( -d $dir_nouveau ) {
                $self->get_ui('choix_projet')->set_keep_above(0);
                my $dialog = Gtk3::MessageDialog->new( $self->{parent_window},
                    'destroy-with-parent', 'error', 'ok', '' );
                $dialog->set_markup(

                    sprintf(
                        __(
# TRANSLATORS: Message when you want to create an AMC project with
# name xxx, but there already exists a directory in the projects
# directory with this name!
"Directory <i>%s</i> already exists, so you can't choose this name."
                        ),
                        glib_filename($dir_nouveau)
                    )
                );
                $dialog->run;
                $dialog->destroy;
                $self->get_ui('choix_projet')->set_keep_above(1);

                return;
            } else {

                # OK

                if ( !move( $dir_original, $dir_nouveau ) ) {
                    debug_and_stderr("ERROR (move project): $!");
                }

                $self->projects_update_list();
            }
        } else {
            debug_and_stderr "No original directory";
        }
    } else {
        debug "No projects directory";
    }
}

# cancel renaming

sub rename_cancel {
    my ($self) = @_;

    $self->close_rename();
}

# Clone the selected project

sub clone_project {
    my ($self)=@_;
    my ($project) = $self->check(1);
    return if ( !$project );

    my $proj_clone =
      new_filename( $self->{local_projects_dir} . '/' . $project );
    my ( undef, undef, $proj_c ) = splitpath($proj_clone);

    my $dialog =
      Gtk3::MessageDialog->new( $self->get_ui('choix_projet'), 'destroy-with-parent',
        'warning', 'ok-cancel', '' );
    $dialog->set_markup(
        sprintf(
            __("This will clone project <b>%s</b> to a new project <i>%s</i>."),
            glib_filename($project), glib_filename($proj_c)
        )
    );
    my $r = $dialog->run;
    $dialog->destroy;

    if ( $r eq 'ok' ) {
        if (
            !$self->clone_project_ok(
                $self->{local_projects_dir} . '/' . $project, $proj_clone,
                $self->get_ui('choix_projet')
            )
          )
        {
            debug_and_stderr("ERROR (clone project): $!");
        }
        $self->projects_update_list();
    }
}

# actually clone an existing project to another new directory

sub add_to_results {
    my ($self) = @_;
    my $f = $File::Find::name;
    utf8::decode($f);
    push @{$self->{find_results}}, $f;
}

sub clone_project_ok {
    my ( $self, $src, $dest, $parent_window ) = @_;
    $parent_window = $self->{parent_window} if ( !$parent_window );
    my $err = '';
    if ( !$err && -e $dest ) {
        $err = __("Destination project directory already exists");
    }
    if ( !$err ) {
        $self->{find_results} = [];
        my $src_chars = $src;
        utf8::encode($src_chars);
        find( { wanted => sub { $self->add_to_results() }, no_chdir => 1 }, $src_chars );
        my $total = 1 + $#{$self->{find_results}};
        if ( $total > 0 ) {
            my $done          = 0;
            my $i             = 0;
            my $last_fraction = 0;
            my $old_text      = $self->{progress_widget}->get_text();
            $self->{progress_widget}->set_text( __ "Copying project..." );
            $self->{progress_widget}->set_fraction(0);
            $self->{command_widget}->show();
            for my $s (@{$self->{find_results}}) {
                my $d = $s;
                $d =~ s:^\Q$src\E:$dest:;
                debug "Clone: $s -> $d";
                if ( -d $s ) {
                    if ( mkdir($d) ) {
                        $done++;
                    } else {
                        debug "* Failed!";
                    }
                } else {
                    if ( copy( $s, $d ) ) {
                        $done++;
                    } else {
                        debug "* Failed!";
                    }
                }
                $i++;
                if ( $i / $total - $last_fraction > 1 / 40 ) {
                    $last_fraction = $i / $total;
                    $self->{progress_widget}->set_fraction($last_fraction);
                    Gtk3::main_iteration while (Gtk3::events_pending);
                }
            }
            $self->{progress_widget}->set_text($old_text);
            $self->{command_widget}->hide();

            if ( $done == $total ) {
                my $dialog = Gtk3::MessageDialog->new(
                    $parent_window,
                    'destroy-with-parent',
                    'info', 'ok',
                    __("Your project has been copied")
                      . "."
                );
                $dialog->run;
                $dialog->destroy;
            } else {
                my $dialog = Gtk3::MessageDialog->new(
                    $parent_window,
                    'destroy-with-parent',
                    'error', 'ok',
                    __("Your project was not properly copied")
                      . (
                        $done != $total
                        ? " "
                          . sprintf( __("(%d files out of %d)"), $done, $total )
                        : ""
                      )
                    . ".\n"
                    . __("AMC encountered unknown problems copying your project: please make a copy yourself by other means.")
                );
                $dialog->run;
                $dialog->destroy;
            }
                
        } else {
            $err = __("Source project directory not found");
        }
    }
    if ($err) {
        my $dialog =
          Gtk3::MessageDialog->new( $parent_window, 'destroy-with-parent',
            'error', 'ok', __("An error occuried during project copy: %s."),
            $err );
        $dialog->run;
        $dialog->destroy;
        return (0);
    }
    return (1);
}

# Delete a project

sub delete_project {
    my ($self)=@_;
    my ($project) = $self->check();
    return if ( !$project );

    # Please confirm...
    $self->get_ui('choix_projet')->set_keep_above(0);
    my $dialog =
      Gtk3::MessageDialog->new( $self->{parent_window}, 'destroy-with-parent',
        'warning', 'ok-cancel', '' );
    $dialog->set_markup(
        sprintf(
            __("You asked to remove project <b>%s</b>.") . " "
              . __(
"This will permanently erase all the files of this project, including the source file as well as all the files you put in the directory of this project, as the scans for example."
              )
              . " "
              . __("Is this really what you want?"),
            glib_filename($project)
        )
    );
    $dialog->get_widget_for_response('ok')->get_style_context()
      ->add_class("destructive-action");
    my $reponse = $dialog->run;
    $dialog->destroy;
    $self->get_ui('choix_projet')->set_keep_above(1);

    if ( $reponse ne 'ok' ) {
        return;
    }

    debug "Removing project $project!";

    # Unlink all files...

    if ( $self->{local_projects_dir} ) {
        my $dir = $self->{local_projects_dir} . "/" . $project;
        if ( -d $dir ) {
            remove_tree( $dir, { verbose => 0, safe => 1, keep_root => 0 } );
        } else {
            debug "No directory $dir";
        }
    } else {
        debug "No projects directory";
    }

    $self->projects_update_list();
}

1;

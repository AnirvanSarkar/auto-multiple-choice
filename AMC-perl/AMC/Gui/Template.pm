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

package AMC::Gui::Template;

use parent 'AMC::Gui';

use AMC::Basic;

use Gtk3 -init;
use XML::Writer;
use Archive::Tar;

use constant {
    TEMPLATE_FILES_PATH => 0,
    TEMPLATE_FILES_FILE => 1,
};

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            project_name=>'',
        },
        %oo
    );

    $self->dialog();

    return $self;
}

sub options_file {
    my ($self) = @_;

    return ( $self->get('rep_projets')
          . "/$self->{project_name}/options.xml" );
}

sub dialog {
    my ($self) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade(
        $glade_xml,
        qw/make_template
          template_files_tree template_name template_file_name
          template_description template_file_name_warning mt_ok
          template_description_scroll template_files_scroll
          /,
    );

    $self->{store} =
        Gtk3::TreeStore->new( 'Glib::String', 'Glib::String' );

    $self->get_ui('template_files_tree')->set_model($self->{store});
    my $renderer = Gtk3::CellRendererText->new;

    my $column = Gtk3::TreeViewColumn->new_with_attributes(
        __(
            # TRANSLATORS: This is a column title for the list of files to be
            # included in a template being created.
            "file"
        ),
        $renderer,
        text => TEMPLATE_FILES_FILE
    );
    $self->get_ui('template_files_tree')->append_column($column);
    $self->get_ui('template_files_tree')->get_selection->set_mode("multiple");

    # Detects files to include

    $self->add_file( $self->get_absolute('texsrc') );
    $self->add_file( $self->options_file() );

    for (qw/description files/) {
        $self->get_ui( 'template_' . $_ . '_scroll' )
          ->set_policy( 'automatic', 'automatic' );
    }

    # Waits for action

    my $resp = $self->get_ui('make_template')->run();

    if ( $resp eq "1" ) {
        $self->build();
    }

    $self->get_ui('make_template')->destroy;

}

sub add_file {
    my ($self, $f ) = @_;

    # removes local part

    my $p_dir = $self->absolu('%PROJET/');
    if ( $f =~ s:^\Q$p_dir\E:: ) {
        my $i = $self->path_from_tree( $f );
        return ($i);
    } else {
        debug "Trying to add non local file: $f (local dir is $p_dir)";
        return (undef);
    }
}

sub path_from_tree {
    my ( $self, $f ) = @_;
    my $i = undef;

    return (undef) if ( !$f );

    my $d = '';

    for my $pp ( split( m:/:, $f ) ) {
        my $ipar = $i;
        $d .= '/' if ($d);
        $d .= $pp;
        $i = model_id_to_iter( $self->{store}, TEMPLATE_FILES_PATH, $d );
        if ( !$i ) {
            $i = $self->{store}->append($ipar);
            $self->{store}->set( $i, TEMPLATE_FILES_PATH, $d,
                TEMPLATE_FILES_FILE, $pp );
        }
    }

    $self->get_ui('template_files_tree')
      ->expand_to_path( $self->{store}->get_path($i) );
    return ($i);
}

sub add_to_archive {
    my ( $store, $path, $iter, $data ) = @_;
    my ($tar, $self) = @$data;

    my $f  = $store->get( $iter, TEMPLATE_FILES_PATH );
    my $af = $self->absolu("%PROJET/$f");

    return (0) if ( $f eq 'description.xml' );

    if ( -f $af ) {
        debug "Adding to template archive: $f\n";
        my $tf = Archive::Tar::File->new( file => $af );
        $tf->rename($f);
        $tar->add_files($tf);
    }

    return (0);
}

sub build {
    my ($self) = @_;

    # Creates template

    my $tfile = $self->get('rep_modeles') . '/'
      . $self->get_ui('template_file_name')->get_text() . ".tgz";
    my $tar = Archive::Tar->new();
    $self->{store}->foreach( \&add_to_archive, [$tar, $self] );

    # Description

    my $buf = $self->get_ui('template_description')->get_buffer;

    my $desc   = '';
    my $writer = new XML::Writer( OUTPUT => \$desc, ENCODING => 'utf-8' );
    $writer->xmlDecl("UTF-8");
    $writer->startTag('description');
    $writer->dataElement( 'title',$self->get_ui('template_name')->get_text()  );
    $writer->dataElement( 'text',
        $buf->get_text( $buf->get_start_iter, $buf->get_end_iter, 1 ) );
    $writer->endTag('description');
    $writer->end();

    $tar->add_data( 'description.xml', $desc );

    $tar->write( $tfile, COMPRESS_GZIP );
}

sub filename_check {
    my ($self) = @_;

    $self->restricted_check(
        $self->get_ui('template_file_name'),
        $self->get_ui('template_file_name_warning'),
        "a-zA-Z0-9_+-"
    );
    my $t     = $self->get_ui('template_file_name')->get_text();
    my $tfile = $self->get('rep_modeles') . '/' . $t . ".tgz";
    $self->get_ui('mt_ok')->set_sensitive( $t && !-e $tfile );
}

sub add {
    my ($self) = @_;

    my $fs = Gtk3::FileChooserDialog->new(
        __("Add files to template"),
        $self->get_ui('make_template'),
        'open', __("Cancel"), 'cancel', __("Add"), 'accept'
    );
    $fs->set_current_folder( $self->absolu('%PROJET/') );
    $fs->set_select_multiple(1);

    my $err  = 0;
    my $resp = $fs->run();
    if ( $resp eq 'accept' ) {
        for my $f ( @{$fs->get_filenames()} ) {
            $err++
              if ( !defined( $self->add_file( clean_gtk_filenames($f) ) ) );
        }
    }
    $fs->destroy();

    if ($err) {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('make_template'),
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup(
            __(
"When making a template, you can only add files that are within the project directory."
            )
        );
        $dialog->run();
        $dialog->destroy();
    }
}

sub del {
    my ($self) = @_;

    my @i = ();
    my @selected =
      $self->get_ui('template_files_tree')->get_selection->get_selected_rows;
    for my $path ( @{ $selected[0] } ) {
        push @i, $self->{store}->get_iter($path) if ($path);
    }
    for (@i) {
        $self->{store}->remove($_);
    }
}

1;

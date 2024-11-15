# Copyright (C) 2008-2022 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::Gui::Association;

use AMC::Basic;
use AMC::Gui::PageArea;
use AMC::Data;
use AMC::DataModule::capture ':zone';
use AMC::NamesFile;
use AMC::Gui::WindowSize;

use Getopt::Long;

use POSIX;
use Gtk3 -init;
use Glib qw/TRUE FALSE/;

use constant {
    COPIES_N       => 0,
    COPIES_STUDENT => 1,
    COPIES_COPY    => 2,
    COPIES_AUTO    => 3,
    COPIES_MANUEL  => 4,
    COPIES_BG      => 5,
    COPIES_IIMAGE  => 6,

    NAMES_NAME => 0,
    NAMES_I    => 1,
};

use_gettext;

my $col_pris       = Gtk3::Gdk::RGBA::parse("#FFD0A9");
my $col_actif      = Gtk3::Gdk::RGBA::parse("#14933A");
my $col_actif_fond = Gtk3::Gdk::RGBA::parse("#5FD581");

sub new {
    my %o    = (@_);
    my $self = {
        'assoc-ncols'      => 3,
        cr                 => '',
        namefield_dir      => '',
        liste              => '',
        liste_key          => '',
        data_dir           => '',
        data               => '',
        assoc              => '',
        capture            => '',
        layout             => '',
        global             => 0,
        show_all           => 1,
        complete_beginning => 1,
        encodage_liste     => 'UTF-8',
        separateur         => "",
        identifiant        => '',
        fin                => '',
        size_prefs         => '',
        rtl                => '',
    };

    for ( keys %o ) {
        $self->{$_} = $o{$_} if ( defined( $self->{$_} ) );
    }

    bless $self;

    $self->{namefield_dir} = $self->{cr} if ( !$self->{namefield_dir} );

    # Open databases for association and capture

    $self->{data} = AMC::Data->new( $self->{data_dir} )
      if ( !$self->{data} );

    $self->{assoc} = $self->{data}->module('association')
      if ( !$self->{assoc} );
    $self->{capture} = $self->{data}->module('capture')
      if ( !$self->{capture} );
    $self->{layout} = $self->{data}->module('layout')
      if ( !$self->{layout} );

    $self->{assoc}->begin_transaction('ALSK');
    $self->{assoc}->check_keys( $self->{liste_key}, '---' );
    $self->{assoc}->end_transaction('ALSK');

    # Read the names from the students list

    $self->{liste} = AMC::NamesFile::new(
        $self->{liste},
        encodage    => $self->{encodage_liste},
        separateur  => $self->{separateur},
        identifiant => $self->{identifiant},
    );

    debug "" . $self->{liste}->taille() . " names in list\n";

    return ($self) if ( !$self->{liste}->taille() );

    # Find all name field images

    my @images = ();

    $self->{capture}->begin_read_transaction('AIMG');
    my $nfs = $self->{capture}->get_namefields;
    $self->{capture}->end_transaction('AIMG');

    for my $p (@$nfs) {
        my $file = $p->{image};
        $file = '' if ( !defined($file) );
        if ( $file && $file !~ /^text:/ ) {
            $file = $self->{namefield_dir} . "/" . $file;
            $file = '' if ( !-r $file );
        }
        push @images, { file => $file, %$p };
    }

    my $iimage = -1;

    if ( $#images < 0 ) {
        debug "Can't find names images...\n";
        $self->{erreur} = __(
"Names images not found... Maybe you forgot using \\namefield command in LaTeX source?"
        );
        return ($self);
    }

    ### Open GUI

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{gui} = Gtk3::Builder->new();
    $self->{gui}->set_translation_domain('auto-multiple-choice');
    $self->{gui}->add_from_file($glade_xml);

    for my $k (
        qw/general tableau titre photo associes_cb copies_tree bouton_effacer bouton_inconnu scrolled_tableau viewport_tableau button_show_all student_typein v_complete_beginning/
      )
    {
        $self->{$k} = $self->{gui}->get_object($k);
    }

    $self->{button_show_all}->set_active( $self->{show_all} );

    $self->{cursor_watch} = Gtk3::Gdk::Cursor->new('GDK_WATCH');

    AMC::Gui::PageArea::add_feuille( $self->{photo} );

    $self->{names_model} =
      Gtk3::ListStore->new( 'Glib::String', 'Glib::String', );

    $self->initial_size;

    my @bouton_nom = ();
    my @bouton_eb  = ();
    $self->{boutons}    = \@bouton_nom;
    $self->{boutons_eb} = \@bouton_eb;
    $self->{taken_list} = [];

    $self->{assoc}->begin_read_transaction('ABUT');

    my ( $x, $y ) = ( 0, 0 );
    for my $i ( 0 .. ( $self->{liste}->taille() - 1 ) ) {
        my $eb   = Gtk3::EventBox->new();
        my $b    = Gtk3::Button->new();
        my $name = $self->{liste}->data_n( $i, '_ID_' );
        my $l    = Gtk3::Label->new($name);
        $self->{names_model}
          ->insert_with_values( $i, NAMES_NAME, $name, NAMES_I, $i );
        $b->add($l);
        $b->set_tooltip_text($name);
        $l->set_ellipsize("middle");

        if (   $self->{rtl}
            && $self->{general}->get_direction() eq 'rtl' )
        {
            $l->set_alignment( 0, .5 );
        }
        $eb->add($b);

        push @bouton_nom, $b;
        push @bouton_eb,  $eb;
        $b->signal_connect( clicked => sub { $self->choisit($i) } );
        $b->set_focus_on_click(0);
        $self->style_bouton($i);
    }

    $self->{assoc}->end_transaction('ABUT');

    $self->set_n_cols();

    # vue arborescente

    my ( $copies_store, $renderer, $column );
    $copies_store = Gtk3::ListStore->new(
        'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String',
        'Glib::String', 'Glib::String', 'Glib::String',
    );

    $self->{copies_tree}->set_model($copies_store);

    $renderer = Gtk3::CellRendererText->new;
    $column   = Gtk3::TreeViewColumn->new_with_attributes(
        "copie",
        $renderer,
        text       => COPIES_N,
        background => COPIES_BG
    );
    $column->set_sort_column_id(COPIES_N);

    $self->{copies_tree}->append_column($column);

    $renderer = Gtk3::CellRendererText->new;
    $column   = Gtk3::TreeViewColumn->new_with_attributes(
        "auto",
        $renderer,
        text       => COPIES_AUTO,
        background => COPIES_BG
    );
    $column->set_sort_column_id(COPIES_AUTO);
    $self->{copies_tree}->append_column($column);

    $renderer = Gtk3::CellRendererText->new;
    $column   = Gtk3::TreeViewColumn->new_with_attributes(
        "manuel",
        $renderer,
        text       => COPIES_MANUEL,
        background => COPIES_BG
    );
    $column->set_sort_column_id(COPIES_MANUEL);
    $self->{copies_tree}->append_column($column);

    $copies_store->set_sort_func( COPIES_N,      \&sort_num, COPIES_N );
    $copies_store->set_sort_func( COPIES_AUTO,   \&sort_num, COPIES_AUTO );
    $copies_store->set_sort_func( COPIES_MANUEL, \&sort_num, COPIES_MANUEL );
    $copies_store->set_sort_column_id( COPIES_N, 'ascending' );

    $self->{copies_store} = $copies_store;

    # remplissage de la liste

    $self->{assoc}->begin_read_transaction('ALST');

    my $ii = 0;
    for my $i (@images) {
        my @sc = ( $i->{student}, $i->{copy} );
        $copies_store->insert_with_values(
            $ii,                             COPIES_N,
            studentids_string(@sc),          COPIES_STUDENT,
            $sc[0],                          COPIES_COPY,
            $sc[1],                          COPIES_AUTO,
            $self->{assoc}->get_auto(@sc),   COPIES_MANUEL,
            $self->{assoc}->get_manual(@sc), COPIES_IIMAGE,
            $ii,
        );
        $ii++;
    }
    $self->{assoc}->end_transaction('ALST');

    # auto-completion

    $self->{completion} = Gtk3::EntryCompletion->new();
    $self->{completion}->set_model( $self->{names_model} );
    $self->{completion}->set_text_column(NAMES_NAME);
    $self->{completion}->set_minimum_key_length(2);
    $self->{completion}->set_match_func( \&compare_names, $self );
    $self->{completion}
      ->signal_connect( "match-selected", \&select_from_entry, $self );
    $self->{student_typein}->set_completion( $self->{completion} );

    # retenir...

    $self->{images} = \@images;

    $self->{gui}->connect_signals( undef, $self );

    $self->{iimage} = -1;

    $self->image_suivante();

    $self->{assoc}->begin_read_transaction('ANCL');
    $self->maj_couleurs_liste();
    $self->{assoc}->end_transaction('ANCL');

    return ($self);
}

# function used to look at a key from the names, for auto-completion
#
# {X:X}
sub compare_names {
    my ( $widget, $key, $iter, $self ) = @_;
    my $name = $self->{names_model}->get( $iter, NAMES_NAME );

    if ( $self->{complete_beginning} ) {
        return ( $name =~ /^\Q$key\E/i );
    } else {
        return ( $name =~ /\Q$key\E/i );
    }
}

# callback when selecting a completion match from the entry
#
# {X:X}
sub select_from_entry {
    my ( $widget, $model, $iter, $self ) = @_;
    my $i    = $model->get( $iter, NAMES_I );
    my $name = $model->get( $iter, NAMES_NAME );
    debug "Selecting from entry auto-completion: I=$i NAME=$name";
    $self->choisit($i);
    $self->{student_typein}->set_text('');
    return (1);
}

# is "show all" button active?
#
# {X:X}
sub get_show_all {
    my ($self) = @_;
    return ( $self->{show_all} );
}

# Resize the table with the requested number of columns, and put the
# buttons where they has to be.
#
# {X:X}
sub set_n_cols {
    my ($self) = @_;

    $self->{general}->get_window()->set_cursor( $self->{cursor_watch} );

    $self->{tableau}->set_sensitive(0);

    # wait for GUI update before going on with the table
    Glib::Idle->add( \&set_n_cols_fill, $self, Glib::G_PRIORITY_LOW );
}

sub set_n_cols_fill {
    my ($self) = @_;

    $self->{tableau}->foreach( sub { $self->{tableau}->remove(shift); } );

    my $x = 0;
    my $y = 0;
    my $i = -1;
  NAME: for my $b ( @{ $self->{boutons_eb} } ) {
        $i++;
        next NAME if ( !$self->{show_all} && $self->{taken_list}->[$i] );
        $self->{tableau}->attach( $b, $x, $y, 1, 1 );
        $x++;
        if ( $x >= $self->{'assoc-ncols'} ) {
            $y++;
            $x = 0;
        }
    }
    $self->{scrolled_tableau}->set_policy( 'never', 'automatic' );

    $self->{tableau}->show_all();
    $self->{tableau}->set_sensitive(1);

    $self->{general}->get_window()->set_cursor(undef);

    return (0);
}

# Add a column to the names table
#
# {X:X}
sub assoc_add_column {
    my ($self) = @_;
    $self->{'assoc-ncols'}++;
    $self->set_n_cols();
}

# Removes a column from the names table
#
# {X:X}
sub assoc_del_column {
    my ($self) = @_;
    $self->{'assoc-ncols'}--;
    $self->{'assoc-ncols'} = 1 if ( $self->{'assoc-ncols'} < 1 );
    $self->set_n_cols();
}

# Gets state of "show all" button and redraw table.
#
# {X:X}
sub set_show_all {
    my ($self) = @_;
    $self->{show_all} = $self->{button_show_all}->get_active();
    $self->set_n_cols();
}

# Gets state of "Beggining" checkbox
#
# {X:X}
sub set_complete_beginning {
    my ($self) = @_;
    $self->{complete_beginning} = $self->{v_complete_beginning}->get_active();
}

# Sets the window size to requested one (saved the last time the
# window was used)
#
# {X:X}
sub initial_size {
    my ($self) = @_;
    if ( $self->{size_prefs} ) {
        AMC::Gui::WindowSize::size_monitor(
            $self->{general},
            {
                config => $self->{size_prefs},
                key    => 'assoc_window_size'
            }
        );
    }
}

# Updates the content of the sheets list (associations already made)
# for one give sheet.
#
# {IN:}
sub maj_contenu_liste {
    my ( $self, $ii, $iter, @sc ) = @_;

    if ($iter) {
        $self->{copies_store}->set(
            $iter, COPIES_AUTO, $self->{assoc}->get_auto(@sc),
            COPIES_MANUEL, $self->{assoc}->get_manual(@sc),
        );
    } else {
        debug_and_stderr "*** [content] no iter for image $ii, sheet "
          . studentids_string(@sc)
          . " ***\n";
    }
}

# Updates the line $iimage of the sheets list.
#
# {X:IN}
sub maj_contenu_liste_iimage {
    my ( $self, $iimage ) = @_;
    my $iter =
      model_id_to_iter( $self->{copies_store}, COPIES_IIMAGE, $iimage );
    my @sc = map { $self->{images}->[$iimage]->{$_} } (qw/student copy/);
    $self->maj_contenu_liste( $iimage, $iter, @sc );
}

# Updates the line corresponding to @sc=(student,copy) of the sheets
# list
#
# {X:IN}
sub maj_contenu_liste_sc {
    my ( $self, @sc ) = @_;
    my $iter = model_id_to_iter( $self->{copies_store}, COPIES_STUDENT, $sc[0],
        COPIES_COPY, $sc[1] );
    my $iimage = $self->{copies_store}->get( $iter, COPIES_IIMAGE );
    $self->maj_contenu_liste( $iimage, $iter, @sc );
}

# Updates the colours of the sheets list.
#
# {IN:}
sub maj_couleurs_liste {    # mise a jour des couleurs la liste
    my ($self) = @_;
    my $counts = $self->{assoc}->counts_hash();
    my $iter   = $self->{copies_store}->get_iter_first();
    my $ok     = defined($iter);
    while ($ok) {
        my @sc =
          $self->{copies_store}->get( $iter, COPIES_STUDENT, COPIES_COPY );
        $self->{copies_store}
          ->set( $iter, COPIES_BG, $counts->{ studentids_string(@sc) }->{color},
          );
        $ok = $self->{copies_store}->iter_next($iter);
    }
}

# Quits.
sub quitter {
    my ($self) = (@_);

    if ( $self->{global} ) {
        Gtk3->main_quit;
    } else {
        $self->{general}->destroy;
        &{ $self->{fin} }($self);
    }
}

sub enregistrer {
    my ($self) = (@_);

    $self->quitter();
}

# inom2code($i) returns the primary key ID corresponding to student on
# line $i from the students list file.
#
# {X:X}
sub inom2code {
    my ( $self, $inom ) = @_;
    return ( $self->{liste}->data_n( $inom, $self->{liste_key} ) );
}

# sc2inom($student,$copy) returns the line number where is the student
# associated with sheet ($student,$copy) in the students list file.
#
# {IN:}
sub sc2inom {
    my ( $self, $student, $copy ) = @_;
    my $code = $self->{assoc}->get_real( $student, $copy );
    if ($code) {
        return (
            $self->{liste}->data(
                $self->{liste_key},
                $code,
                test_numeric => 1,
                all          => 1,
                i            => 1
            )
        );
    } else {
        return ();
    }
}

# cancels association to the student at line number $inom in the
# students list file.
#
# {IN:}
sub delie {
    my ( $self, $inom ) = (@_);

    my $code = $self->inom2code($inom);

    # remove associations to $code, and update list
    for my $sc ( @{ $self->{assoc}->delete_target($code) } ) {
        $self->maj_contenu_liste_sc(@$sc);
    }

    # also update buttons that corresponds to that $code
    $self->style_bouton_code($code);
}

# Associates sheet ($student,$copy) with student at line number $inom
# in the students list file.
#
# {IN:}
sub lie {
    my ( $self, $inom, $student, $copy ) = (@_);
    $self->delie($inom);
    my $oldcode = $self->{assoc}->get_real( $student, $copy );
    $self->{assoc}->set_manual( $student, $copy, $self->inom2code($inom) );

    # updates list
    $self->maj_contenu_liste_sc( $student, $copy );
    $self->maj_couleurs_liste();

    # updates buttons
    # - old one
    $self->style_bouton_code($oldcode);

    # - new one
    $self->style_bouton( $inom, 1 );
}

# Cancels manual association of current sheet.
#
# {OUT:}
sub efface_manuel {
    my ($self) = @_;
    my $i = $self->{iimage};

    if ( $i >= 0 ) {
        $self->{assoc}->begin_transaction('ADEL');

        my @sc = $self->image_sc($i);
        my @r  = $self->sc2inom(@sc);

        $self->{capture}->outdate_annotated_copy(@sc);
        $self->{assoc}->set_manual( @sc, undef );

        # update buttons
        # - old ones
        for (@r) {
            $self->style_bouton($_);
        }

        # - new one
        $self->style_bouton( 'IMAGE', 1 );

        $self->maj_contenu_liste_sc(@sc);
        $self->maj_couleurs_liste();

        $self->set_n_cols() if ( !$self->{show_all} );

        $self->{assoc}->end_transaction('ADEL');
    }
}

# Tells that current sheet is not to be associated with any of the
# students from the list.
#
# {OUT:}
sub inconnu {
    my ($self) = @_;
    my $i = $self->{iimage};

    if ( $i >= 0 ) {
        $self->{assoc}->begin_transaction('AUNK');

        my @sc = $self->image_sc($i);
        my @r  = $self->sc2inom(@sc);

        $self->{capture}->outdate_annotated_copy(@sc);
        $self->{assoc}->set_manual( @sc, 'NONE' );

        for (@r) {
            $self->style_bouton($_);
        }

        $self->maj_contenu_liste_sc(@sc);
        $self->maj_couleurs_liste();

        $self->set_n_cols() if ( !$self->{show_all} );

        $self->{assoc}->end_transaction('AUNK');
    }
}

# Go to the sheet pointed with the mouse in the list.
#
# {OUT:}
sub goto_from_list {
    my ( $self, $widget, $event ) = @_;

    my ( $path, $focus ) = $self->{copies_tree}->get_cursor();
    if ($path) {
        my $iter = $self->{copies_store}->get_iter($path);
        my $etu  = $self->{copies_store}->get( $iter, COPIES_N );
        my $i    = $self->{copies_store}->get( $iter, COPIES_IIMAGE );

        if ( defined($i) ) {
            $self->{assoc}->begin_read_transaction('AGFL');
            $self->charge_image($i);
            $self->{assoc}->end_transaction('AGFL');
        }
    }
    return TRUE;
}

# Go to line $i of the list.
#
# {OUT:}
sub goto_image {
    my ( $self, $i ) = @_;
    debug "goto_image($i)";
    if ( $i >= 0 ) {
        my $iter = model_id_to_iter( $self->{copies_store}, COPIES_IIMAGE, $i );
        my $path = $self->{copies_store}->get_path($iter);
        $self->{copies_tree}->set_cursor( $path, undef, FALSE );
    } else {
        my $sel = $self->{copies_tree}->get_selection;
        $sel->unselect_all();
        $self->{assoc}->begin_read_transaction('ACHI');
        $self->charge_image($i);
        $self->{assoc}->end_transaction('ACHI');
    }
}

# Is a sheet selected? Activate buttons or not depending on that.
#
# {X:X}
sub vraie_copie {
    my ( $self, $oui ) = @_;
    for (qw/bouton_effacer bouton_inconnu/) {
        $self->{$_}->set_sensitive($oui);
    }
}

# Returns the (student,copy) array corresponding to sheet at line $i
# in the sheets list.
#
# {X:X}
sub image_sc {
    my ( $self, $i ) = @_;
    return ( map { $self->{images}->[$i]->{$_} } (qw/student copy/) );
}

# Returns (student,copy) as a single string, corresponding to sheet at
# line $i in the sheets list.
#
# {X:X}
sub image_sc_string {
    my ( $self, $i ) = @_;
    return ( ( __ "Sheet" ) . " " . studentids_string( $self->image_sc($i) ) );
}

# Returns the image file name corresponding to sheet at line $i in the
# sheets list.
#
# {X:X}
sub image_filename {
    my ( $self, $i ) = @_;
    return (undef) if ( $i < 0 || $i > $#{ $self->{images} } );
    return ( $self->{images}->[$i]->{file} );
}

# Shows name field image corresponding to sheet at line $i in the
# sheets list.
#
# {X:IN}
sub charge_image {
    my ( $self, $i ) = (@_);
    $self->style_bouton( 'IMAGE', 0 );
    my $file = $self->image_filename($i);

    if ( defined($file) ) {
        if ($file) {
            if ( $file =~ /^text:(.*)/ ) {
                $self->{photo}->set_content( text => $1 );
            } else {
                $self->{photo}->set_content( image => $file );
            }
        } else {
            my $text = pageids_string( map { $self->{images}->[$i]->{$_} }
                  (qw/student page copy/) );
            $self->{photo}->set_content( text => $text );
        }
        $self->{image_sc} =
          [ $self->image_sc($i) ];
        $self->vraie_copie(1);
    } else {
        $i = -1;
        $self->{photo}
          ->set_content( background_color => '#6CB9ED', text => __ "End" );
        $self->vraie_copie(0);
    }
    $self->{iimage} = $i;
    $self->style_bouton( 'IMAGE', 1 );
    $self->{titre}
      ->set_text( ( $i >= 0 ? $self->image_sc_string($i) : "---" ) );
}

# Returns the line number $i from sheets list adding $pas to it.
#
# {X:X}
sub i_suivant {
    my ( $self, $i, $pas ) = (@_);
    $pas = 1 if ( !$pas );
    $i += $pas;
    if ( $i < 0 ) {
        $i = $#{ $self->{images} };
    }
    if ( $i > $#{ $self->{images} } ) {
        $i = 0;
    }
    return ($i);
}

# Move in the sheets list, adding $pas to current position.
#
# {OUT:}
sub image_suivante {
    my ( $self, $pas ) = (@_);
    $pas = 1 if ( !$pas );
    my $i = $self->i_suivant( $self->{iimage}, $pas );

    $self->{assoc}->begin_read_transaction('ALIS');
    while (
        $i != $self->{iimage}
        && ( $self->{assoc}->with_association( $self->image_sc($i) )
            && !$self->{associes_cb}->get_active() )
      )
    {
        $i = $self->i_suivant( $i, $pas );
        if ( $pas == 1 ) {
            $i = -1 if ( $i == 0 && $self->{iimage} == -1 );
        }
        if ( $pas == -1 ) {
            $i = -1 if ( $i == $#{ $self->{images} } && $self->{iimage} == -1 );
        }
    }

    $self->{assoc}->end_transaction('ALIS');

    if ( $self->{iimage} != $i ) {
        $self->goto_image($i);
    } else {
        $self->goto_image(-1);
    }
}

# Go to next sheet.
#
# {X:OUT}
sub va_suivant {
    my ($self) = (@_);
    $self->image_suivante(1);
}

# Go to previous sheet.
#
# {X:OUT}
sub va_precedent {
    my ($self) = (@_);
    $self->image_suivante(-1);
}

# Sets the content and style of a button, according to the association
# made with the student corresponding to the button.
#
# {IN:}
sub style_bouton {
    my ( $self, $i, $actif ) = (@_);
    my @sc;

    if ( $i eq 'IMAGE' ) {
        return () if ( $self->{iimage} < 0 );
        my @sc = $self->image_sc( $self->{iimage} );

        if (@sc) {
            ($i) = $self->sc2inom(@sc);

            return () if ( !defined($i) );
        } else {
            return ();
        }
    }

    my $pris =
      studentids_string( $self->{assoc}->real_back( $self->inom2code($i) ) );
    $self->{taken_list}->[$i] = $pris;

    my $b  = $self->{boutons}->[$i];
    my $eb = $self->{boutons_eb}->[$i];
    if ($b) {
        if ($pris) {
            $b->set_relief('GTK_RELIEF_NONE');
            $b->override_background_color( 'prelight',
                ( $actif ? $col_actif : $col_pris ) );
            $b->get_child()
              ->set_text( $self->{liste}->data_n( $i, '_ID_' ) . " ($pris)" );
        } else {
            $b->set_relief('GTK_RELIEF_NORMAL');
            $b->override_background_color( 'prelight', undef );
            $b->get_child()->set_text( $self->{liste}->data_n( $i, '_ID_' ) );
        }
        if ($eb) {
            my $col = undef;
            $col = $col_actif_fond if ($actif);
            for (qw/normal active selected/) {
                $eb->override_background_color( $_, $col );
            }
        } else {
            debug_and_stderr "*** no EventBox for $i ***\n";
        }
    } else {
        debug_and_stderr "*** no button for $i ***\n";
    }
}

# Calls style_button for the button of the student whose primary key
# ID is $code.
#
# {X:IN}
sub style_bouton_code {
    my ( $self, $code, $actif ) = @_;
    for (
        $self->{liste}->data(
            $self->{liste_key}, $code,
            test_numeric => 1,
            all          => 1,
            i            => 1
        )
      )
    {
        $self->style_bouton( $_, $actif );
    }
}

# Choose student at line $i in the students list file to be associated
# with current sheet from the list.
#
# {OUT:}
sub choisit {
    my ( $self, $i ) = (@_);

    if ( $self->{iimage} >= 0 ) {
        $self->{assoc}->begin_transaction('ASWT');
        $self->{capture}->outdate_annotated_copy( @{ $self->{image_sc} } );
        $self->lie( $i, @{ $self->{image_sc} } );
        $self->{assoc}->end_transaction('ASWT');
        $self->set_n_cols() if ( !$self->{show_all} );
        $self->image_suivante();
    }
}

1;

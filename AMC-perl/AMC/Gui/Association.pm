#! /usr/bin/perl -w
#
# Copyright (C) 2008-2011 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::Association;

use AMC::Basic;
use AMC::Gui::PageArea;
use AMC::Data;
use AMC::DataModule::capture ':zone';
use AMC::NamesFile;

use Getopt::Long;
use XML::Writer;
use IO::File;
use Encode;

use POSIX;
use Gtk2 -init;

use constant {
    COPIES_N => 0,
    COPIES_STUDENT => 1,
    COPIES_COPY => 2,
    COPIES_AUTO => 3,
    COPIES_MANUEL => 4,
    COPIES_BG => 5,
    COPIES_IIMAGE => 6,
};

use_gettext;

my $col_pris = Gtk2::Gdk::Color->new(65353,208*256,169*256);
my $col_actif = Gtk2::Gdk::Color->new(20*256,147*256,58*256);
my $col_actif_fond = Gtk2::Gdk::Color->new(95*256,213*256,129*256);

sub reduit {
    my $s=shift;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return($s);
}

sub new {
    my %o=(@_);
    my $self={'assoc-ncols'=>3,
	      'cr'=>'',
	      'namefield_dir'=>'',
	      'liste'=>'',
	      'liste_key'=>'',
	      'data_dir'=>'',
	      'data'=>'',
	      'global'=>0,
	      'encodage_liste'=>'UTF-8',
	      'separateur'=>"",
	      'identifiant'=>'',
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;

    $self->{'namefield_dir'}=$self->{'cr'} if(!$self->{'namefield_dir'});

    # Open databases for association and capture

    $self->{'data'}=AMC::Data->new($self->{'data_dir'})
      if(!$self->{'data'});

    $self->{'assoc'}=$self->{'data'}->module('association');
    $self->{'capture'}=$self->{'data'}->module('capture');

    $self->{'assoc'}->begin_transaction('ALSK');
    $self->{'assoc'}->check_keys($self->{'liste_key'},'---');
    $self->{'assoc'}->end_transaction('ALSK');

    # Read the names from the students list

    $self->{'liste'}=AMC::NamesFile::new($self->{'liste'},
					 'encodage'=>$self->{'encodage_liste'},
					 'separateur'=>$self->{'separateur'},
					 'identifiant'=>$self->{'identifiant'},
					 );

    debug "".$self->{'liste'}->taille()." names in list\n";

    return($self) if(!$self->{'liste'}->taille());

    # Find all name field images

    my @images=();

    $self->{'capture'}->begin_read_transaction('AIMG');

    my $sth=$self->{'capture'}->statement('pageZonesAll');
    $sth->execute(@{$self->{'page_id'}},ZONE_NAME);
    while (my $z = $sth->fetchrow_hashref) {
      my $file=$self->{'cr'}."/".$z->{'image'};
      if(-r $file) {
	push @images,{'file'=>$file,%$z};
      }
    }

    $self->{'capture'}->end_transaction('AIMG');

    my $iimage=-1;

    if($#images<0) {
	debug "Can't find names images...\n";
	$self->{'erreur'}=__("Names images not found... Maybe you did not run automatic data capture yet, or you forgot using \\champnom command in LaTeX source, or you don't have papers' scans ?")."\n"
	    .__"For both two latest cases, you can use graphical interface for manual data caption.";
	return($self);
    }

    ### Open GUI

    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{'gui'}=Gtk2::Builder->new();
    $self->{'gui'}->set_translation_domain('auto-multiple-choice');
    $self->{'gui'}->add_from_file($glade_xml);

    for my $k (qw/general tableau titre photo associes_cb copies_tree bouton_effacer bouton_inconnu/) {
	$self->{$k}=$self->{'gui'}->get_object($k);
    }

    AMC::Gui::PageArea::add_feuille($self->{'photo'});

    my $nligs=POSIX::ceil($self->{'liste'}->taille()/$self->{'assoc-ncols'});

    $self->{'tableau'}->resize($self->{'assoc-ncols'},$nligs);

    my @bouton_nom=();
    my @bouton_eb=();
    $self->{'boutons'}=\@bouton_nom;
    $self->{'boutons_eb'}=\@bouton_eb;

    $self->{'assoc'}->begin_read_transaction('ABUT');

    my ($x,$y)=(0,0);
    for my $i (0..($self->{'liste'}->taille()-1)) {
	my $eb=Gtk2::EventBox->new();
	my $b=Gtk2::Button->new($self->{'liste'}->data_n($i,'_ID_'));
	$eb->add($b);
	$self->{'tableau'}->attach($eb,$x,$x+1,$y,$y+1,["expand","fill"],[],1,1);
	push @bouton_nom,$b;
	push @bouton_eb,$eb;
	$b->show();
	$eb->show();
	$b->signal_connect (clicked => sub { $self->choisit($i) });
	$b->set_focus_on_click(0);
	$self->style_bouton($i);

	$x++;
	if($x>=$self->{'assoc-ncols'}) {
	    $y++;
	    $x=0;
	}
    }

    $self->{'assoc'}->end_transaction('ABUT');

    # vue arborescente

    my ($copies_store,$renderer,$column);
    $copies_store = Gtk2::ListStore->new ('Glib::String',
					  'Glib::String',
					  'Glib::String',
					  'Glib::String',
					  'Glib::String',
					  'Glib::String',
					  'Glib::String',
					  );

    $self->{'copies_tree'}->set_model($copies_store);

    $renderer=Gtk2::CellRendererText->new;
    $column = Gtk2::TreeViewColumn->new_with_attributes ("copie",
							 $renderer,
							 text=> COPIES_N,
							 'background'=> COPIES_BG);
    $column->set_sort_column_id(COPIES_N);

    $self->{'copies_tree'}->append_column ($column);

    $renderer=Gtk2::CellRendererText->new;
    $column = Gtk2::TreeViewColumn->new_with_attributes ("auto",
							 $renderer,
							 text=> COPIES_AUTO,
							 'background'=> COPIES_BG);
    $column->set_sort_column_id(COPIES_AUTO);
    $self->{'copies_tree'}->append_column ($column);

    $renderer=Gtk2::CellRendererText->new;
    $column = Gtk2::TreeViewColumn->new_with_attributes ("manuel",
							 $renderer,
							 text=> COPIES_MANUEL,
							 'background'=> COPIES_BG);
    $column->set_sort_column_id(COPIES_MANUEL);
    $self->{'copies_tree'}->append_column ($column);

    $copies_store->set_sort_func(COPIES_N,\&sort_num,COPIES_N);
    $copies_store->set_sort_func(COPIES_AUTO,\&sort_num,COPIES_AUTO);
    $copies_store->set_sort_func(COPIES_MANUEL,\&sort_num,COPIES_MANUEL);

    $self->{'copies_store'}=$copies_store;

    # remplissage de la liste

    $self->{'assoc'}->begin_read_transaction('ALST');

    my $ii=0;
    for my $i (@images) {
      my @sc=($i->{'student'},$i->{'copy'});
      my $iter=$copies_store->append();
      $copies_store->set($iter,
			 COPIES_N,studentids_string(@sc),
			 COPIES_STUDENT,$sc[0],
			 COPIES_COPY,$sc[1],
			 COPIES_AUTO,$self->{'assoc'}->get_auto(@sc),
			 COPIES_MANUEL,$self->{'assoc'}->get_manual(@sc),
			 COPIES_IIMAGE,$ii,
			);
      $ii++;
    }
    $self->{'assoc'}->end_transaction('ALST');

    # retenir...

    $self->{'images'}=\@images;

    $self->{'photo'}->signal_connect('expose_event'=>\&AMC::Gui::PageArea::expose_drawing);
    $self->{'gui'}->connect_signals(undef,$self);

    $self->{'iimage'}=-1;

    $self->image_suivante();

    $self->{'assoc'}->begin_read_transaction('ANCL');
    $self->maj_couleurs_liste();
    $self->{'assoc'}->end_transaction('ANCL');

    return($self);
}

sub maj_contenu_liste {
    my ($self,$ii,$iter,@sc)=@_;

    if($iter) {
      $self->{'copies_store'}
	->set($iter,
	      COPIES_AUTO,$self->{'assoc'}->get_auto(@sc),
	      COPIES_MANUEL,$self->{'assoc'}->get_manual(@sc),
	     );
    } else {
	debug_and_stderr "*** [content] no iter for image $ii, sheet "
	  .studentids_string(@sc)." ***\n";
    }
}

sub maj_contenu_liste_iimage {
  my ($self,$iimage)=@_;
  my $iter=model_id_to_iter($self->{'copies_store'},COPIES_IIMAGE,$ii);
  my @sc=map { $self->{'images'}->[$iimage]->{$_} } (qw/student copy/);
  $self->maj_contenu_liste($iimage,$iter,@sc);
}

sub maj_contenu_liste_sc {
  my ($self,@sc)=@_;
  my $iter=model_id_to_iter($self->{'copies_store'},
			    COPIES_STUDENT,$sc[0],
			    COPIES_COPY,$sc[1]);
  my $iimage=$self->{'copies_store'}->get($iter,COPIES_IIMAGE);
  $self->maj_contenu_liste($iimage,$iter,@sc);
}

sub maj_couleurs_liste { # mise a jour des couleurs la liste
    my ($self)=@_;

    for my $ii (0..$#{$self->{'images'}}) {
      my @sc=$self->image_sc($ii);
      my $iter=model_id_to_iter($self->{'copies_store'},COPIES_IIMAGE,$ii);
      if($iter) {
	my $etat=$self->{'assoc'}->state(@sc);
	my $coul;
	if($etat==0) {
	  my $x=$self->{'assoc'}->get_manual(@sc);
	  if(defined($x) && $x eq 'NONE') {
	    $coul='salmon';
	  } else {
	    $coul=undef;
	  }
	} elsif($etat==1) {
	  if($self->{'assoc'}->get_manual(@sc)) {
	    $coul='lightgreen';
	  } else {
	    $coul='lightblue';
	  }
	} else {
	  $coul='salmon';
	}
	$self->{'copies_store'}->set($iter,
				     COPIES_BG,$coul,
				    );
      } else {
	debug_and_stderr "*** [color] no iter for image $ii, sheet "
	  .studentids_string(@sc)." ***\n";
      }
    }
}

sub quitter {
    my ($self)=(@_);

    if($self->{'global'}) {
	Gtk2->main_quit;
    } else {
	$self->{'general'}->destroy;
    }
}

sub enregistrer {
    my ($self)=(@_);

    $self->quitter();
}

sub inom2code {
    my ($self,$inom)=@_;
    return($self->{'liste'}->data_n($inom,$self->{'liste_key'}));
}

sub sc2inom {
    my ($self,$student,$copy)=@_;
    my $code=$self->{'assoc'}->get_real($student,$copy);
    if($code) {
      return($self->{'liste'}->data($self->{'liste_key'},
				    $code,
				    'all'=>1,'i'=>1));
    } else {
      return();
    }
}

sub delie {
    my ($self,$inom)=(@_);

    my $code=$self->inom2code($inom);

    # remove associations to $code, and update list
    for my $sc (@{$self->{'assoc'}->delete_target($code)}) {
      $self->maj_contenu_liste_sc(@$sc);
    }

    # also update buttons that corresponds to that $code
    $self->style_bouton_code($code);
}

sub lie {
    my ($self,$inom,$student,$copy)=(@_);
    $self->delie($inom);
    my $oldcode=$self->{'assoc'}->get_manual($student,$copy);
    $self->{'assoc'}->set_manual($student,$copy,$self->inom2code($inom));

    # updates list
    $self->maj_contenu_liste_sc($student,$copy);
    $self->maj_couleurs_liste();

    # updates buttons
    # - old one
    $self->style_bouton_code($oldcode);
    # - new one
    $self->style_bouton($inom,1);
}

sub efface_manuel {
    my ($self)=@_;
    my $i=$self->{'iimage'};

    if($i>=0) {
      $self->{'assoc'}->begin_read_transaction('ADEL');

      my @sc=$self->image_sc($i);
      my @r=$self->sc2inom(@sc);

      $self->{'assoc'}->set_manual(@sc,undef);

      for(@r) {
	$self->style_bouton($_);
      }
      $self->maj_contenu_liste_sc(@sc);
      $self->maj_couleurs_liste();

      $self->{'assoc'}->end_transaction('ADEL');
    }
}

sub inconnu {
    my ($self)=@_;
    my $i=$self->{'iimage'};

    if($i>=0) {
      $self->{'assoc'}->begin_transaction('AUNK');

      my @sc=$self->image_sc($i);
      my @r=$self->id2inom($e);

      $self->{'assoc'}->set_manual('NONE');

      for(@r) {
	$self->style_bouton($_);
      }
      $self->maj_contenu_liste_sc(@sc);
      $self->maj_couleurs_liste();

      $self->{'assoc'}->end_transaction('AUNK');
    }
}

sub goto_from_list {
    my ($self,$widget, $event) = @_;

    my ($path,$focus)=$self->{'copies_tree'}->get_cursor();
    if($path) {
	my $iter=$self->{'copies_store'}->get_iter($path);
	my $etu=$self->{'copies_store'}->get($iter,COPIES_N);
	my $i=$self->{'copies_store'}->get($iter,COPIES_IIMAGE);

	if(defined($i)) {
	  $self->{'assoc'}->begin_read_transaction('AGFL');
	  $self->charge_image($i);
	  $self->{'assoc'}->end_transaction('AGFL');
	}
    }
    return TRUE;
}

sub goto_image {
    my ($self,$i)=@_;
    if($i>=0) {
	my $iter=model_id_to_iter($self->{'copies_store'},COPIES_IIMAGE,$i);
	my $path=$self->{'copies_store'}->get_path($iter);
	$self->{'copies_tree'}->set_cursor($path);
    } else {
	my $sel=$self->{'copies_tree'}->get_selection;
	$sel->unselect_all();
	$self->charge_image($i);
    }
}

sub vraie_copie {
    my ($self,$oui)=@_;
    for(qw/bouton_effacer bouton_inconnu/) {
	$self->{$_}->set_sensitive($oui);
    }
}

sub image_sc {
  my ($self,$i)=@_;
  return(map { $self->{'images'}->[$i]->{$_} } (qw/student copy/));
}

sub image_sc_string {
  my ($self,$i)=@_;
  return(studentids_string($self->image_sc($i)));
}

sub image_filename {
  my ($self,$i)=@_;
  return('') if ($i<0 || $i>$#{$self->{'images'}});
  my $f=$self->{'namefield_dir'}.'/'.$self->{'images'}->[$i]->{'image'};
  return(-r $f ? $f : '');
}

sub charge_image {
    my ($self,$i)=(@_);
    $self->style_bouton('IMAGE',0);
    my $file=$self->image_filename($i);

    if($file) {
	$self->{'photo'}->set_image($file);
	$self->{'image_sc'}
	  = [$self->image_sc($i)];
	$self->vraie_copie(1);
    } else {
	$i=-1;
	$self->{'photo'}->set_image();
	$self->vraie_copie(0);
    }
    $self->{'iimage'}=$i;
    $self->style_bouton('IMAGE',1);
    $self->{'titre'}->set_text(($i>=0 ? $self->image_sc_string($i) : "---"));
}

sub i_suivant {
    my ($self,$i,$pas)=(@_);
    $pas=1 if(!$pas);
    $i+=$pas;
    if($i<0) {
	$i=$#{$self->{'images'}};
    }
    if($i>$#{$self->{'images'}}) {
	$i=0;
    }
    return($i);
}

sub image_suivante {
    my ($self,$pas)=(@_);
    $pas=1 if(!$pas);
    my $i=$self->i_suivant($self->{'iimage'},$pas);

    $self->{'assoc'}->begin_read_transaction('ALIS');
    while($i != $self->{'iimage'}
	  && ($self->{'assoc'}->get_real($self->image_sc($i))
	      && ! $self->{'associes_cb'}->get_active()) ) {
	$i=$self->i_suivant($i,$pas);
	if($pas==1) {
	    $i=-1 if($i==0 && $self->{'iimage'}==-1);
	}
	if($pas==-1) {
	    $i=-1 if($i==$#{$self->{'images'}} && $self->{'iimage'}==-1);
	}
    }

    if($self->{'iimage'} != $i) {
	$self->goto_image($i) ;
    } else {
	$self->goto_image(-1) ;
    }

    $self->{'assoc'}->end_transaction('ALIS');
}

sub va_suivant {
    my ($self)=(@_);
    $self->image_suivante(1);
}

sub va_precedent {
    my ($self)=(@_);
    $self->image_suivante(-1);
}

#<

sub style_bouton {
    my ($self,$i,$actif)=(@_);
    my @sc;

    if($i eq 'IMAGE') {
	return() if($self->{iimage}<0);
	my @sc=$self->image_sc($self->{iimage});

	if(@sc) {
	    ($i)=$self->sc2inom(@sc);

	    return() if(!defined($i));
	} else {
	    return();
	}
    }

    my $pris=studentids_string($self->{'assoc'}->real_back($self->inom2code($i)));

    my $b=$self->{'boutons'}->[$i];
    my $eb=$self->{'boutons_eb'}->[$i];
    if($b) {
	if($pris) {
	    $b->set_relief(GTK_RELIEF_NONE);
	    $b->modify_bg('prelight',($actif ? $col_actif : $col_pris));
	    $b->set_label($self->{'liste'}->data_n($i,'_ID_')." ($pris)");
	} else {
	    $b->set_relief(GTK_RELIEF_NORMAL);
	    $b->modify_bg('prelight',undef);
	    $b->set_label($self->{'liste'}->data_n($i,'_ID_'));
	}
	if($eb) {
	    my $col=undef;
	    $col=$col_actif_fond if($actif);
	    for(qw/normal active selected/) {
		$eb->modify_bg($_,$col);
	    }
	} else {
	    debug_and_stderr "*** no EventBox for $i ***\n";
	}
    } else {
	debug_and_stderr "*** no button for $i ***\n";
    }
}

sub style_bouton_code {
  my ($self,$code,$actif)=@_;
  for($self->{'liste'}->data($self->{'liste_key'},$code,
			     'all'=>1,'i'=>1)) {
    $self->style_bouton($_,$actif);
  }
}

sub choisit {
    my ($self,$i)=(@_);

    $self->{'assoc'}->begin_transaction('ASWT');
    $self->lie($i,@{$self->{'image_sc'}});
    $self->{'assoc'}->end_transaction('ASWT');
    $self->image_suivante();
}

1;

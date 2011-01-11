#! /usr/bin/perl -w
#
# Copyright (C) 2008-2010 Alexis Bienvenue <paamc@passoire.fr>
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

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw();
}

use AMC::Basic;
use AMC::Gui::PageArea;
use AMC::AssocFile;
use AMC::NamesFile;

use Getopt::Long;
use XML::Writer;
use IO::File;
use Encode;

use POSIX;
use Gtk2 -init;
use Gtk2::GladeXML;

use constant {
    COPIES_N => 0,
    COPIES_AUTO => 1,
    COPIES_MANUEL => 2,
    COPIES_BG => 3,
    COPIES_IIMAGE => 4,
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
	      'liste'=>'',
	      'liste_key'=>'',
	      'fichier-liens'=>'',
	      'global'=>0,
	      'encodage_liste'=>'UTF-8',
	      'encodage_interne'=>'UTF-8',
	      'separateur'=>"",
	      'identifiant'=>'',
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;
    
    $self->{'fichier-liens'}=$self->{'cr'}."/association.xml" if(!$self->{'fichier-liens'});

    $self->{'assoc'}=AMC::AssocFile::new($self->{'fichier-liens'},
					 'liste_key'=>$self->{'liste_key'},
					 'encodage'=>$self->{'encodage_interne'},
					 );
    $self->{'assoc'}->load();

    $self->{'liste'}=AMC::NamesFile::new($self->{'liste'},
					 'encodage'=>$self->{'encodage_liste'},
					 'separateur'=>$self->{'separateur'},
					 'identifiant'=>$self->{'identifiant'},
					 );

    debug "".$self->{'liste'}->taille()." names in list\n";
    
    return($self) if(!$self->{'liste'}->taille());
    
    # liste des images :
    my @images;
    opendir(DIR, $self->{'cr'}) 
	|| die "Erreur opening directory <$self->{'cr'}> : $!";
    @images = map {"$self->{'cr'}/$_" } sort { $a cmp $b } grep { /^nom-/ && -f "$self->{'cr'}/$_" } readdir(DIR);
    closedir DIR;
    
    my $iimage=-1;
    my $image_etud='';
    
    if($#images<0) {
	print "Can't find names images...\n";
	$self->{'erreur'}=__("Names images not found... Maybe you did not run automatic data capture yet, or you forgot using \\champnom command in LaTeX source, or you don't have papers' scans ?")."\n"
	    .__"For both two latest cases, you can use graphical interface for manual data caption.";
	return($self);
    }
    
    ### GUI

    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{'gui'}=Gtk2::GladeXML->new($glade_xml,undef,'auto-multiple-choice');

    for my $k (qw/tableau titre photo associes_cb copies_tree bouton_effacer bouton_inconnu/) {
	$self->{$k}=$self->{'gui'}->get_widget($k);
    }

    AMC::Gui::PageArea::add_feuille($self->{'photo'});
    
    my $nligs=POSIX::ceil($self->{'liste'}->taille()/$self->{'assoc-ncols'});
   
    $self->{'tableau'}->resize($self->{'assoc-ncols'},$nligs);
    
    my @bouton_nom=();
    my @bouton_eb=();
    $self->{'boutons'}=\@bouton_nom;
    $self->{'boutons_eb'}=\@bouton_eb;

    $self->{'lignes'}=[];

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
	push @{$self->{'lignes'}->[$y]},$eb;
	$b->signal_connect (clicked => sub { $self->choisit($i) });
	$b->set_focus_on_click(0);
	$self->style_bouton($i);

	$x++;
	if($x>=$self->{'assoc-ncols'}) {
	    $y++;
	    $x=0;
	}
    }

    # vue arborescente

    my ($copies_store,$renderer,$column);
    $copies_store = Gtk2::ListStore->new ('Glib::String',
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

    for my $i (0..$#images) {
	my $e=fich2etud($images[$i]);
	my $iter=$copies_store->append();
	$copies_store->set($iter,
			   COPIES_N,$e,
			   COPIES_AUTO,$self->{'assoc'}->get('auto',$e),
			   COPIES_MANUEL,$self->{'assoc'}->get('manuel',$e),
			   COPIES_IIMAGE,$i,
			   );
    }

    # retenir...
    
    $self->{'images'}=\@images;

    $self->{'gui'}->signal_autoconnect_from_package($self);

    $self->{'iimage'}=-1;

    $self->image_suivante();
    $self->maj_couleurs_liste();

    return($self);
}

sub maj_contenu_liste {
    my ($self,$etu)=@_;

    my $iter=model_id_to_iter($self->{'copies_store'},COPIES_N,$etu);
    if($iter) {
	$self->{'copies_store'}->set($iter,
				     COPIES_AUTO,$self->{'assoc'}->get('auto',$etu),
				     COPIES_MANUEL,$self->{'assoc'}->get('manuel',$etu),
				     );
    } else {
	print STDERR "*** [content] no iter for sheet $etu ***\n";
    }
}

sub maj_couleurs_liste { # mise a jour des couleurs la liste
    my ($self)=@_;

    for my $e (map { fich2etud($_) ; } @{$self->{'images'}}) {
	my $iter=model_id_to_iter($self->{'copies_store'},COPIES_N,$e);
	if($iter) {
	    my $etat=$self->{'assoc'}->etat($e);
	    my $coul;
	    if($etat==0) {
		my $x=$self->{'assoc'}->get('manuel',$e);
		if(defined($x) && $x eq 'NONE') {
		    $coul='salmon';
		} else {
		    $coul=undef;
		}
	    } elsif($etat==1) {
		if($self->{'assoc'}->get('manuel',$e)) {
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
	    print STDERR "*** [color] no iter for sheet $e ***\n";
	}
    }
    
}

sub expose_photo {
    my ($self,$widget,$evenement,@donnees)=@_;

    $widget->expose_drawing($evenement,@donnees);
}

sub quitter {
    my ($self)=(@_);

    if($self->{'global'}) {
	Gtk2->main_quit;
    } else {
	$self->{'gui'}->get_widget('general')->destroy;
    }
}

sub enregistrer {
    my ($self)=(@_);

    $self->{'assoc'}->save();

    $self->quitter();
}

sub fich2etud {
    my $f=shift;
    if($f =~ /nom-([0-9]+)-([0-9]+)-([0-9]+)\.jpg$/) {
	return($1); 
    } else {
	return('');
    }
}

sub inom2id {
    my ($self,$inom)=@_;
    return($self->{'liste'}->data_n($inom,$self->{'assoc'}->{'a'}->{'liste_key'}));
}

sub id2inom {
    my ($self,$id)=@_;
    if($self->{'assoc'}->effectif($id)) {
	return($self->{'liste'}->data($self->{'assoc'}->{'a'}->{'liste_key'},
				      $self->{'assoc'}->effectif($id),
				      'all'=>1,'i'=>1));
    } else {
	return();
    }
}

sub delie {
    my ($self,$inom,$etud)=(@_);

    my $id=$self->inom2id($inom);
    # tout lien vers le nom choisi est efface
    for ($self->{'assoc'}->inverse($id)) {
	# print STDERR "Efface $_ -> i=$inom\n";
	$self->{'assoc'}->set('manuel',$_,
			      ( $self->{'assoc'}->get('auto',$_) eq $id ? 'NONE' : ''));
	$self->maj_contenu_liste($_);
    }

    # l'ancien nom ne pointe plus vers rien -> bouton
    my @r=$self->id2inom($etud);
    $self->{'assoc'}->set('manuel',$etud,'NONE');
    $self->maj_contenu_liste($etud);
    for(@r) {
	$self->style_bouton($_);
    }

}

sub lie {
    my ($self,$inom,$etud)=(@_);
    $self->delie($inom,$etud);
    $self->{'assoc'}->set('manuel',$etud,$self->inom2id($inom));
    
    $self->maj_contenu_liste($etud);
    $self->maj_couleurs_liste();

    $self->style_bouton($inom);
}

sub efface_manuel {
    my ($self)=@_;
    my $i=$self->{'iimage'};

    if($i>=0) {
	my $e=fich2etud($self->{'images'}->[$i]);

	my @r=$self->id2inom($e);

	$self->{'assoc'}->efface('manuel',$e);

	for(@r) {
	    $self->style_bouton($_);
	}
	$self->maj_contenu_liste($e);
	$self->maj_couleurs_liste();
    }
}

sub inconnu {
    my ($self)=@_;
    my $i=$self->{'iimage'};

    if($i>=0) {
	my $e=fich2etud($self->{'images'}->[$i]);
	my @r=$self->id2inom($e);

	$self->{'assoc'}->set('manuel',$e,'NONE');

	for(@r) {
	    $self->style_bouton($_);
	}
	$self->maj_contenu_liste($e);
	$self->maj_couleurs_liste();
    }
}

sub goto_from_list {
    my ($self,$widget, $event) = @_;

    my ($path,$focus)=$self->{'copies_tree'}->get_cursor();
    if($path) {
	my $iter=$self->{'copies_store'}->get_iter($path);
	my $etu=$self->{'copies_store'}->get($iter,COPIES_N);
	my $i=$self->{'copies_store'}->get($iter,COPIES_IIMAGE);
	#print STDERR "N=$etu I=$i\n";
	if(defined($i)) {
	    $self->charge_image($i);
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

sub charge_image {
    my ($self,$i)=(@_);
    $self->style_bouton('IMAGE',0);
    if($i>=0 && $i<=$#{$self->{'images'}} && -f $self->{'images'}->[$i]) {
	$self->{'photo'}->set_image($self->{'images'}->[$i]);
	$self->{'image_etud'} = fich2etud($self->{'images'}->[$i]) || 'xxx';
	$self->vraie_copie(1);
    } else {
	$i=-1;
	$self->{'photo'}->set_image();
	$self->vraie_copie(0);
    }
    $self->{'iimage'}=$i;
    $self->style_bouton('IMAGE',1);
    $self->{'titre'}->set_text(($i>=0 ? $self->{'images'}->[$i] : "---"));
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

    while($i != $self->{'iimage'}
	  && ($self->{'assoc'}->effectif(fich2etud($self->{'images'}->[$i]))
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

    if($i eq 'IMAGE') {
	return() if($self->{iimage}<0);
	my $id=fich2etud($self->{'images'}->[$self->{iimage}]);

	if($id) {
	    ($i)=$self->id2inom($id);

	    return() if(!defined($i));
	} else {
	    return();
	}
    }

    my $pris=join(',',$self->{'assoc'}->inverse($self->inom2id($i)));

    #print STDERR "STYLE($i,".$self->inom2id($i)."):$pris\n";

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
	    print STDERR "*** no EventBox for $i ***\n";
	}
    } else {
	print STDERR "*** no buttun for $i ***\n";
    }
}

sub choisit {
    my ($self,$i)=(@_);

    $self->lie($i,$self->{'image_etud'});
    $self->image_suivante();
}

1;

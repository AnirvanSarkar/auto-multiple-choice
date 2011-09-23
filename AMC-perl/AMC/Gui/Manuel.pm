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

package AMC::Gui::Manuel;

use Getopt::Long;
use Gtk2 -init;

use XML::Simple;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;

use AMC::Basic;
use AMC::Gui::PageArea;
use AMC::MEPList;

use constant {
    MDIAG_ID => 0,
    MDIAG_ID_BACK => 1,
    MDIAG_EQM => 2,
    MDIAG_DELTA => 3,
    MDIAG_EQM_BACK => 4,
    MDIAG_DELTA_BACK => 5,
    MDIAG_I => 6,
};

use_gettext;

sub new {
    my %o=(@_);
    my $self={'mep-dir'=>'',
	      'mep-data'=>'',
	      'an-data'=>'',
	      'cr-dir'=>'',
	      'liste'=>'',
	      'sujet'=>'',
	      'etud'=>'',
	      'dpi'=>75,
	      'seuil'=>0.1,
	      'seuil_sens'=>8.0,
	      'seuil_eqm'=>3.0,
	      'fact'=>1/4,
	      'coches'=>[],
	      'lay'=>{},
	      'ids'=>[],
	      'retient_m'=>'',
	      'ids_m'=>{},
	      'iid'=>0,
	      'global'=>0,
	      'en_quittant'=>'',
	      'encodage_liste'=>'UTF-8',
	      'encodage_interne'=>'UTF-8',
	      'image_type'=>'xpm',
	      'editable'=>1,
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    # recupere la liste des fichiers MEP des pages qui correspondent 

    my $dispos;

    if($self->{'mep-data'}) {
	$dispos=$self->{'mep-data'};
    } else {
	debug "Making again MEPList...";
	$dispos=AMC::MEPList::new($self->{'mep-dir'},'id'=>$self->{'etud'});
	debug "ok";
    }

    $self->{'dispos'}=$dispos;

    # an-list aussi

    my $an_list;

    if($self->{'an-data'}) {
	$an_list=$self->{'an-data'};
    } else {
	debug "Making again ANList...";
	$an_list=AMC::ANList::new($self->{'cr-dir'});
	debug "ok";
    }

    $self->{'an_list'}=$an_list;

    die "No PDF subject file" if(! $self->{'sujet'});
    die "Subject file ".$self->{'sujet'}." not found" if(! -f $self->{'sujet'});

    my $temp_loc=tmpdir();
    $self->{'temp-dir'} = tempdir( DIR=>$temp_loc,
				   CLEANUP => (!get_debug()) );

    $self->{'tmp-image'}=$self->{'temp-dir'}."/page";

    $self->{'ids'}=[$dispos->ids()];

    $self->{'iid'}=0;

    ## GUI

    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{'gui'}=Gtk2::Builder->new();
    $self->{'gui'}->set_translation_domain('auto-multiple-choice');
    $self->{'gui'}->add_from_file($glade_xml);

    bless $self;

    for my $k (qw/general area navigation_h navigation_v goto goto_v etudiant_cb nom_etudiant diag_tree/) {
	$self->{$k}=$self->{'gui'}->get_object($k);
    }

    $self->{'etudiant_cbe'}=$self->{'etudiant_cb'}->get_children();

    if(!$self->{'editable'}) {
	$self->{'navigation_v'}->show();
    } else {
	$self->{'navigation_h'}->show();
    }

    $self->{'cursor_watch'}=Gtk2::Gdk::Cursor->new('GDK_WATCH');

    AMC::Gui::PageArea::add_feuille($self->{'area'},'',
	'marks'=>($self->{'editable'} ? '' : 'blue'));
    
    ### modele DIAGNOSTIQUE SAISIE

    if($self->{'editable'}) {
	
	my ($diag_store,$renderer,$column);
	
	$diag_store = Gtk2::ListStore->new ('Glib::String',
					    'Glib::String', 
					    'Glib::String', 
					    'Glib::String', 
					    'Glib::String', 
					    'Glib::String', 
					    'Glib::String', 
					    );
	
	$self->{'diag_tree'}->set_model($diag_store);
	
	$renderer=Gtk2::CellRendererText->new;
	$column = Gtk2::TreeViewColumn->new_with_attributes (__"page",
							     $renderer,
							     text=> MDIAG_ID,
							     'background'=> MDIAG_ID_BACK);
	$column->set_sort_column_id(MDIAG_ID);
	$self->{'diag_tree'}->append_column ($column);

	$renderer=Gtk2::CellRendererText->new;
	$column = Gtk2::TreeViewColumn->new_with_attributes (__"MSE",
							     $renderer,
							     'text'=> MDIAG_EQM,
							     'background'=> MDIAG_EQM_BACK);
	$column->set_sort_column_id(MDIAG_EQM);
	$self->{'diag_tree'}->append_column ($column);

	$renderer=Gtk2::CellRendererText->new;
	$column = Gtk2::TreeViewColumn->new_with_attributes (__"sensitivity",
							     $renderer,
							     'text'=> MDIAG_DELTA,
							     'background'=> MDIAG_DELTA_BACK);
	$column->set_sort_column_id(MDIAG_DELTA);
	$self->{'diag_tree'}->append_column ($column);

	$diag_store->set_sort_func(MDIAG_EQM,\&sort_num,MDIAG_EQM);
	$diag_store->set_sort_func(MDIAG_DELTA,\&sort_num,MDIAG_DELTA);
	$diag_store->set_sort_func(MDIAG_ID,\&sort_id,MDIAG_ID);

	$self->{'diag_store'}=$diag_store;

	my @ids=$dispos->ids();
	if(@ids) {
	    for my $i (0..$#ids) {
		$self->maj_list($ids[$i],$i);
	    }
	}
    }

    ### liste des noms d'etudiants

    if(-f $self->{'liste'} && $self->{'editable'}) {
	
	$self->{'liste-ent'}=Gtk2::ListStore->new ('Glib::String');
	
	open(LISTE,"<:encoding(".$self->{'encodage_liste'}.")",$self->{'liste'}) 
	    or die "Error opening <".$self->{'liste'}."> : $!";
      NOM: while(<LISTE>) {
	  s/\#.*//;
	  next NOM if(/^\s*$/);
	  s/^\s+//;
	  s/\s+$//;
	  $self->{'liste-ent'}->set($self->{'liste-ent'}->append,0,$_);
      }
	close(LISTE);
	
	$self->{'etudiant_cb'}->set_model($self->{'liste-ent'});
	$self->{'etudiant_cb'}->set_text_column(0);
    }
    
    $self->{'gui'}->connect_signals(undef,$self);
    
    $self->charge_i();
    
    
    
    return($self);
}

###

sub goto_from_list {
    my ($self,$widget, $event) = @_;
    return FALSE unless $event->button == 1;
    return TRUE unless $event->type eq 'button-release';
    my ($path, $column, $cell_x, $cell_y) = 
	$self->{'diag_tree'}->get_path_at_pos ($event->x, $event->y);
    if($path) {
	$self->ecrit();
	$self->{'iid'}=$self->{'diag_store'}->get($self->{'diag_store'}->get_iter($path),
						  MDIAG_I);
	$self->charge_i();
    }
    return TRUE;
}

sub maj_list {
    my ($self,$id,$i)=(@_);
    return if(!$self->{'editable'});

    my $iter=model_id_to_iter($self->{'diag_store'},MDIAG_ID,$id);
    $iter=$self->{'diag_store'}->append if(!$iter);

    my ($eqm,$eqm_coul)=$self->{'an_list'}
    ->mse_string($id,
		 $self->{'seuil_eqm'},
		 'red');
    my ($sens,$sens_coul)=$self->{'an_list'}
    ->sensibilite_string($id,$self->{'seuil'},
			 $self->{'seuil_sens'},
			 'red');
    $self->{'diag_store'}->set($iter,
			       MDIAG_ID,$id,
			       MDIAG_ID_BACK,$self->{'an_list'}->couleur($id),
			       MDIAG_EQM,$eqm,
			       MDIAG_EQM_BACK,$eqm_coul,
			       MDIAG_DELTA,$sens,
			       MDIAG_DELTA_BACK,$sens_coul,
			       );
    if(defined($i)) {
	$self->{'diag_store'}->set($iter,
				   MDIAG_I,$i);
    }
    
}

sub choix {
    my ($self,$widget,$event)=(@_);
    $widget->choix($event);
}

sub expose_area {
    my ($self,$widget,$evenement,@donnees)=@_;

    $widget->expose_drawing($evenement,@donnees);
}

sub une_modif {
    my ($self)=@_;
    $self->{'area'}->modif();
}

sub charge_i {
    my ($self)=(@_);

    $self->{'coches'}=[];
    
    $self->{'lay'}=$self->{'dispos'}->mep($self->{'ids'}->[$self->{'iid'}]);
    my $page=$self->{'lay'}->{'page'};

    ################################
    # fabrication du xpm
    ################################

    $self->{'general'}->window()->set_cursor($self->{'cursor_watch'});
    Gtk2->main_iteration while ( Gtk2->events_pending );

    debug "ID ".$self->{'ids'}->[$self->{'iid'}]." PAGE $page\n";
    system("pdftoppm","-f",$page,"-l",$page,
	   "-r",$self->{'dpi'},
	   $self->{'sujet'},
	   $self->{'temp-dir'}."/page");
    # recherche de ce qui a ete fabrique...
    opendir(TDIR,$self->{'temp-dir'}) || die "can't opendir $self->{'temp-dir'} : $!";
    my @candidats = grep { /^page-.*\.ppm$/ && -f $self->{'temp-dir'}."/$_" } readdir(TDIR);
    closedir TDIR;
    debug "Candidates : ".join(' ',@candidats);
    my $tmp_ppm=$self->{'temp-dir'}."/".$candidats[0];
    my $tmp_image=$tmp_ppm;

    if($self->{'image_type'} && $self->{'image_type'} ne 'ppm') {
	$tmp_image=$self->{'tmp-image'}.".".$self->{'image_type'};
	debug "ppmto".$self->{'image_type'}." : $tmp_ppm -> $tmp_image";
	system("ppmto".$self->{'image_type'}." \"$tmp_ppm\" > \"$tmp_image\"");
    }

    ################################
    # synchro variables
    ################################

    $self->{'etudiant_cbe'}->set_text('');
    $self->{'scan-file'}='';

    # mise a jour des cases suivant fichier XML deja present
    $_=$self->{'ids'}->[$self->{'iid'}]; s/\+//g; s/\//-/g; s/^-+//; s/-+$//;
    my $tid=$_;
    
    my $x=$self->{'an_list'}->analyse($self->{'ids'}->[$self->{'iid'}]);

    if(defined($x)) {
	for my $i (0..$#{$self->{'lay'}->{'case'}}) {
	    my $id=$self->{'lay'}->{'case'}->[$i]->{'question'}."."
		.$self->{'lay'}->{'case'}->[$i]->{'reponse'};
	    debug "ID=".$tid." Q=$id R=".$x->{'case'}->{$id}->{'r'};
	    $self->{'coches'}->[$i]=$x->{'case'}->{$id}->{'r'} > $self->{'seuil'};
	}
	my $t=$x->{'nometudiant'}; $t='' if(!defined($t));
	$self->{'etudiant_cbe'}->set_text($t);
	$self->{'scan-file'}=$x->{'src'};
    }
    
    $self->{'xml-file'}=$self->{'cr-dir'}."/analyse-manuelle-$tid.xml";

    $self->{'nom_etudiant'}->set_sensitive($self->{'lay'}->{'nom'});

    # utilisation

    $self->{'area'}->set_image($tmp_image,
			       $self->{'lay'},
			       $self->{'coches'});

    unlink($tmp_ppm);
    unlink($tmp_image) if($tmp_ppm ne $tmp_image && !get_debug());

    # dans la liste

    $self->{'diag_tree'}->set_cursor($self->{'diag_store'}->get_path(model_id_to_iter($self->{'diag_store'},MDIAG_I,$self->{'iid'}))) if($self->{'editable'});

    # fin du traitement...

    $self->{'general'}->window()->set_cursor(undef);
}

sub ecrit {
    my ($self)=(@_);

    return if(!$self->{'editable'});

    if($self->{'xml-file'} && $self->{'area'}->modifs()) {
	debug "Saving file ".$self->{'xml-file'};
	open(XML,">:encoding(".$self->{'encodage_interne'}.")",$self->{'xml-file'}) 
	    or die "Error writing ".$self->{'xml-file'}." : $!";
	print XML "<?xml version='1.0' encoding='".$self->{'encodage_interne'}."' standalone='yes'?>\n<analyse src=\""
	    .$self->{'scan-file'}."\" manuel=\"1\" id=\""
	    .$self->{'ids'}->[$self->{'iid'}]."\" nometudiant=\""
	    .$self->{'etudiant_cbe'}->get_text()."\">\n";
	for my $i (0..$#{$self->{'lay'}->{'case'}}) {
	    my $q=$self->{'lay'}->{'case'}->[$i]->{'question'};
	    my $r=$self->{'lay'}->{'case'}->[$i]->{'reponse'};
	    my $id="$q.$r";
	    print XML "  <case id=\"$id\" question=\"$q\" reponse=\"$r\" r=\"".($self->{'coches'}->[$i] ? 1 : 0)."\"/>\n";
	}
	print XML "</analyse>\n";
	close(XML);

	$self->synchronise();
    }
}

sub synchronise {
    my ($self)=(@_);

    $self->{'area'}->sync();

    for($self->{'an_list'}->maj('effaces'=>1)) { $self->{'ids_m'}->{$_}=1; }
    $self->maj_list($self->{'ids'}->[$self->{'iid'}],undef);
}

sub passe_suivant {
    my ($self)=(@_);

    $self->ecrit();
    $self->{'iid'}++;
    $self->{'iid'}=0 if($self->{'iid'}>$#{$self->{'ids'}});
    $self->charge_i();
}

sub passe_precedent {
    my ($self)=(@_);

    $self->ecrit();
    $self->{'iid'}--;
    $self->{'iid'}=$#{$self->{'ids'}} if($self->{'iid'}<0);
    $self->charge_i();
}

sub annule {
    my ($self)=(@_);

    $self->charge_i();
}

sub efface_saisie {
    my ($self)=(@_);

    my $id=$self->{'ids'}->[$self->{'iid'}];
    my $fs=$self->{'an_list'}->attribut($id,'fichier-scan');
    my $f=$self->{'an_list'}->attribut($id,'fichier');
    if(-e $f && (!$fs || ($f ne $fs))) {
	unlink($f);
    }
    $self->synchronise();
    $self->charge_i();
}

sub ok_quitter {
    my ($self)=(@_);

    $self->ecrit();
    $self->quitter();
}

sub quitter {
    my ($self)=(@_);
    if($self->{'global'}) {
	Gtk2->main_quit;
    } else {
	$self->{'general'}->destroy;
	if($self->{'en_quittant'}) {
	    if($self->{'retient_m'}) {
		&{$self->{'en_quittant'}}('ids_m'=>[keys %{$self->{'ids_m'}}]);
	    } else {
		&{$self->{'en_quittant'}}();
	    }
	}
    }
}

sub goto_activate_cb {
    my ($self)=(@_);

    my $dest=$self->{($self->{'editable'} ? 'goto' : 'goto_v')}->get_text();

    $self->ecrit();

    debug "Go to $dest";
    
    # recherche d'un ID correspondant 
    my $did='';
  CHID: for my $i (0..$#{$self->{'ids'}}) {
      my $k=$self->{'ids'}->[$i];
      if($k =~ /\+$dest\//) {
	  $self->{'iid'}=$i;
	  last CHID;
      }
  }

    $self->charge_i();
}

1;

__END__


#! /usr/bin/perl -w
#
# Copyright (C) 2008 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3 of
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

use Getopt::Long;
use Gtk2 -init;
use Gtk2::GladeXML;
use XML::Simple;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;

use AMC::MEPList;

sub attention {
    my $msg=shift;
    print "\n";
    print "*" x (length($msg)+4)."\n";
    print "* ".$msg." *\n";
    print "*" x (length($msg)+4)."\n";
    print "\n";
}

sub new {
    my %o=(@_);
    my $self={'mep-dir'=>'',
	      'mep-data'=>'',
	      'cr-dir'=>'',
	      'liste'=>'',
	      'sujet'=>'',
	      'etud'=>'',
	      'dpi'=>75,
	      'debug'=>0,
	      'seuil'=>0.1,
	      'fact'=>1/4,
	      'coches'=>[],
	      'lay'=>{},
	      'ids'=>[],
	      'iid'=>0,
	      'global'=>0,
	      'en_quittant'=>'',
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    print "DEBUG MODE\n" if($self->{'debug'});

    # recupere la liste des fichiers MEP des pages qui correspondent 

    my $dispos;

    if($self->{'mep-data'}) {
	$dispos=$self->{'mep-data'};
    } else {
	$dispos=AMC::MEPList::new($self->{'mep-dir'},'id'=>$self->{'etud'});
    }

    $self->{'dispos'}=$dispos;

    # intuite le sujet.pdf s'il n'est pas donne, a partir du source latex

    if(!$self->{'sujet'}) {
	my $src=$dispos->attr('','src');
	if($src) {
	    my $sujet;
	    $sujet=$src;
	    $sujet =~ s/\.tex$/-sujet.pdf/ or $sujet='';
	    $self->{'sujet'}=$sujet;
	}
    }

    die "Aucun fichier pdf de sujet fourni" if(! $self->{'sujet'});
    die "Fichier sujet ".$self->{'sujet'}." introuvable" if(! -f $self->{'sujet'});

    my $temp_loc=tmpdir();
    $self->{'temp-dir'} = tempdir( DIR=>$temp_loc,
				   CLEANUP => (!$self->{'debug'}) );

    $self->{'tmp-xpm'}=$self->{'temp-dir'}."/page.xpm";

    $self->{'ids'}=[$dispos->ids()];

    $self->{'iid'}=0;

    ## GUI

    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{'gui'}=Gtk2::GladeXML->new($glade_xml);

    bless $self;

    for my $k (qw/area scrolled_area viewport_area goto etudiant_cb etudiant_cbe/) {
	$self->{$k}=$self->{'gui'}->get_widget($k);
    }
    
    if(-f $self->{'liste'}) {
	
	$self->{'liste-ent'}=Gtk2::ListStore->new ('Glib::String');
	
	open(LISTE,$self->{'liste'}) 
	    or die "Erreur a l'ouverture du fichier <".$self->{'liste'}."> : $!";
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
    
    $self->{'gui'}->signal_autoconnect_from_package($self);
    
    $self->charge_i();
    
    
    
    return($self);
}

###

sub get_color {
    my ($colormap,$name) = @_;
    my $ret;

    if ($ret = $allocated_colors{$name}) {
        return $ret;
    }

    my $color = Gtk2::Gdk::Color->parse($name);
    $colormap->alloc_color($color,TRUE,TRUE);

    $allocated_colors{$name} = $color;

    return $color;
}

sub dessine_case {
    my ($self,$i)=(@_);

    my $case=$self->{'lay'}->{'case'}->[$i];
    my $coche=$self->{'coches'}->[$i];
    if(!$coche) {
	$self->{'gc'}->set_foreground(get_color($self->{'area'}->get_colormap,'white'));
	$self->{'pixmap'}->draw_rectangle(
				$self->{'gc'},
				1,
				$case->{'xmin'}*$self->{'fact'},
				$case->{'ymin'}*$self->{'fact'},
				($case->{'xmax'}-$case->{'xmin'})*$self->{'fact'},
				($case->{'ymax'}-$case->{'ymin'})*$self->{'fact'}
				);
    }
    $self->{'gc'}->set_foreground(get_color($self->{'area'}->get_colormap,'red'));
    $self->{'pixmap'}->draw_rectangle(
				      $self->{'gc'},
				      $coche,
				      $case->{'xmin'}*$self->{'fact'},
				      $case->{'ymin'}*$self->{'fact'},
				      ($case->{'xmax'}-$case->{'xmin'})*$self->{'fact'},
				      ($case->{'ymax'}-$case->{'ymin'})*$self->{'fact'}
				      );
}

sub choix {
  my ($self,$widget,$event)=(@_);

  if ($event->button == 1) {
      my ($x,$y)=$event->coords;
      print "Clic $x $y\n" if($self->{'debug'});
      for my $i (0..$#{$self->{'lay'}->{'case'}}) {
	  $self->{'modifs'}=1;

	  my $case=$self->{'lay'}->{'case'}->[$i];
	  if($x<=$case->{'xmax'}*$self->{'fact'} && $x>=$case->{'xmin'}*$self->{'fact'}
	     && $y<=$case->{'ymax'}*$self->{'fact'} && $y>=$case->{'ymin'}*$self->{'fact'}) {
	      print " -> case $i\n" if($self->{'debug'});
	      $self->{'coches'}->[$i]=!$self->{'coches'}->[$i];
	      $self->dessine_case($i);
	      $self->{'area'}->window->show;
	  }
      }
  }
  return TRUE;
}

sub charge_image {
    my ($self)=(@_);

    ($self->{'pixmap'},undef)=Gtk2::Gdk::Pixmap->create_from_xpm($self->{'area'}->window,undef,$self->{'tmp-xpm'});

    ($sx,$sy)=$self->{'pixmap'}->get_size();
    $self->{'area'}->set_size_request($sx,$sy);
    #$self->{'viewport_area'}->set_size_request($sx,$sy);

    print "Taille : $sx $sy\n";

    if($self->{'lay'}->{'tx'} && $self->{'lay'}->{'ty'}) {
	$self->{'fact'}=($sx/$self->{'lay'}->{'tx'} + $sy/$self->{'lay'}->{'ty'})/2;
	print "Rapport : ".$self->{'fact'}."\n";
    }

    $self->{'gc'} = Gtk2::Gdk::GC->new( $self->{'pixmap'} );
    $self->{'gc'}->set_foreground(get_color($self->{'area'}->get_colormap,'red'));

    for my $i (0..$#{$self->{'lay'}->{'case'}}) {
	$self->dessine_case($i);
    }

    $self->{'area'}->window->set_back_pixmap($self->{'pixmap'},0);
    $self->{'area'}->window->show();

}

sub charge_i {
    my ($self)=(@_);

    $self->{'coches'}=[];
    
    $self->{'lay'}=$self->{'dispos'}->mep($self->{'ids'}->[$self->{'iid'}]);
    my $page=$self->{'lay'}->{'page'};

    # fabrication du xpm
    print "ID ".$self->{'ids'}->[$self->{'iid'}]." PAGE $page\n";
    system("pdftoppm","-f",$page,"-l",$page,
	   "-r",$self->{'dpi'},
	   $self->{'sujet'},
	   $self->{'temp-dir'}."/page");
    # recherche de ce qui a ete fabrique...
    opendir(TDIR,$self->{'temp-dir'}) || die "can't opendir $self->{'temp-dir'} : $!";
    my @candidats = grep { /^page-.*\.ppm$/ && -f $self->{'temp-dir'}."/$_" } readdir(TDIR);
    closedir TDIR;
    print "Candidats : ".join(' ',@candidats)."\n" if($self->{'debug'});
    my $tmp_ppm=$self->{'temp-dir'}."/".$candidats[0];
    # sprintf($self->{'temp-dir'}."/page-%06d.ppm",$page);
    system("ppmtoxpm \"$tmp_ppm\" > \"".$self->{'tmp-xpm'}."\"");
    unlink($tmp_ppm) if(!$self->{'debug'});

    $self->{'etudiant_cbe'}->set_text('');
    $self->{'scan-file'}='';

    # mise a jour des cases suivant fichier XML deja present
    $_=$self->{'ids'}->[$self->{'iid'}]; s/\+//g; s/\//-/g; s/^-+//; s/-+$//;
    my $tid=$_;
    
    my $xml_file;
    $xml_file=$self->{'cr-dir'}."/analyse-manuelle-$tid.xml";
    $xml_file=$self->{'cr-dir'}."/analyse-$tid.xml" if(! -f $xml_file);
    if(-f $xml_file) {
	my $x=XMLin($xml_file,ForceArray => 1,KeyAttr=>['id']);
	for my $i (0..$#{$self->{'lay'}->{'case'}}) {
	    my $id=$self->{'lay'}->{'case'}->[$i]->{'question'}."."
		.$self->{'lay'}->{'case'}->[$i]->{'reponse'};
	    $self->{'coches'}->[$i]=$x->{'case'}->{$id}->{'r'} > $self->{'seuil'};
	}
	my $t=$x->{'nometudiant'}; $t='' if(!defined($t));
	$self->{'etudiant_cbe'}->set_text($t);
	$self->{'scan-file'}=$x->{'src'};
    }
    
    $xml_file=$self->{'cr-dir'}."/analyse-manuelle-$tid.xml";

    $self->{'xml-file'}=$xml_file;

    # utilisation
    $self->charge_image();

    $self->{'modifs'}=0;
}

sub ecrit {
    my ($self)=(@_);

    if($self->{'xml-file'} && $self->{'modifs'}) {
	print "Sauvegarde du fichier ".$self->{'xml-file'}."\n";
	open(XML,">".$self->{'xml-file'}) 
	    or die "Erreur a l'ecriture de ".$self->{'xml-file'}." : $!";
	print XML "<?xml version='1.0' standalone='yes'?>\n<analyse src=\""
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

	$self->{'modifs'}=0;
    }
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

sub une_modif {
    my ($self)=(@_);

    $self->{'modifs'}=1;
}

sub annule {
    my ($self)=(@_);

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
	$self->{'gui'}->get_widget('general')->destroy;
	if($self->{'en_quittant'}) {
	    &{$self->{'en_quittant'}}();
	}
    }
}

sub goto_activate_cb {
    my ($self)=(@_);

    my $dest=$self->{'goto'}->get_text();

    $self->ecrit();

    print "On va a $dest\n";
    
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

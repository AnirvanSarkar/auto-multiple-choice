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

my $col_pris = Gtk2::Gdk::Color->new(65353,208*256,169*256);

sub reduit {
    my $s=shift;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return($s);
}

sub new {
    my %o=(@_);
    my $self={'assoc-ncols'=>5,
	      'cr'=>'',
	      'liste'=>'',
	      'liste_key'=>'',
	      'fichier-liens'=>'',
	      'global'=>0,
	      'encodage_liste'=>'UTF-8',
	      'encodage_interne'=>'UTF-8',
	      'separateur'=>":",
	      'identifiant'=>'(nom) (prenom)',
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

    print "".$self->{'liste'}->taille()." noms\n";
    
    return($self) if(!$self->{'liste'}->taille());
    
    # liste des images :
    my @images;
    opendir(DIR, $self->{'cr'}) 
	|| die "Erreur a l'ouverture du repertoire <$self->{'cr'}> : $!";
    @images = map {"$self->{'cr'}/$_" } sort { $a cmp $b } grep { /^nom-/ && -f "$self->{'cr'}/$_" } readdir(DIR);
    closedir DIR;
    
    my $iimage=-1;
    my $image_etud='';
    
    if($#images<0) {
	print "Je ne trouve pas d'images de noms...\n";
	return($self);
    }
    
    my $xmax=-1;
    my $ymax=-1;
    
    open(GETSIZE,"-|","identify",@images);
    while(<GETSIZE>) {
	if(/\s+([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)\s+/) {
	    $xmax=$1 if($xmax<$1);
	    $ymax=$2 if($ymax<$2);
	}
    }
    close(GETSIZE);

    ### GUI

    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{'gui'}=Gtk2::GladeXML->new($glade_xml);

    for my $k (qw/tableau titre photo/) {
	$self->{$k}=$self->{'gui'}->get_widget($k);
    }

    AMC::Gui::PageArea::add_feuille($self->{'photo'});
    
    my $nligs=POSIX::ceil($self->{'liste'}->taille()/$self->{'assoc-ncols'});
    
    $self->{'tableau'}->resize($self->{'assoc-ncols'},$nligs);
    
    my @bouton_nom=();
    $self->{'boutons'}=\@bouton_nom;

    my ($x,$y)=(0,0);
    for my $i (0..($self->{'liste'}->taille()-1)) {
	my $b=Gtk2::Button->new($self->{'liste'}->data_n($i,'_ID_'));
	$self->{'tableau'}->attach_defaults($b,$x,$x+1,$y,$y+1);
	$y++;
	if($y>=$nligs) {
	    $y=0;
	    $x++;
	}
	push @bouton_nom,$b;
	$b->show();
	$b->signal_connect (clicked => sub { $self->choisit($i) });
	$b->set_focus_on_click(0);

	$self->style_bouton($i);
    }

    # retenir...
    
    $self->{'images'}=\@images;
    $self->{'iimage'}='';

    $self->{'gui'}->signal_autoconnect_from_package($self);

    $self->charge_image(0);

    return($self);
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
    }

    # l'ancien nom ne pointe plus vers rien -> bouton
    my @r=$self->id2inom($etud);
    $self->{'assoc'}->set('manuel',$etud,'NONE');
    for(@r) {
	$self->style_bouton($_);
    }

}

sub lie {
    my ($self,$inom,$etud)=(@_);
    $self->delie($inom,$etud);
    $self->{'assoc'}->set('manuel',$etud,$self->inom2id($inom));
    $self->style_bouton($inom);
}

sub charge_image {
    my ($self,$i)=(@_);
    if($i>=0 && $i<=$#{$self->{'images'}} && -f $self->{'images'}->[$i]) {
	$self->{'photo'}->set_image($self->{'images'}->[$i]);
	$self->{'image_etud'} = fich2etud($self->{'images'}->[$i]) || 'xxx';
    } else {
	$i=-1;
	$self->{'photo'}->set_image();
    }
    $self->{'iimage'}=$i;
    $self->{'titre'}->set_text(($i>=0 ? $self->{'images'}->[$i] : "---"));
}

sub i_suivant {
    my ($self,$i)=(@_);
    $i++;
    $i=0 if($i>$#{$self->{'images'}});
    return($i);
}

sub image_suivante {
    my ($self)=(@_);
    my $i=$self->i_suivant($self->{'iimage'});
    #print "Suivant($iimage/$i)\n";
    while($i != $self->{'iimage'}
	  && $self->{'assoc'}->effectif(fich2etud($self->{'images'}->[$i])) ) {
	$i=$self->i_suivant($i);
	#print "->$i\n";
    }
    if($self->{'iimage'} != $i) {
	$self->charge_image($i) ;
    } else {
	$self->charge_image(-1) ;
    }
}

#<

sub style_bouton {
    my ($self,$i)=(@_);
    
    my $pris=join(',',$self->{'assoc'}->inverse($self->inom2id($i)));

    #print STDERR "STYLE($i,".$self->inom2id($i)."):$pris\n";

    my $b=$self->{'boutons'}->[$i];
    if($b) {
	if($pris) {
	    $b->set_relief(GTK_RELIEF_NONE);
	    $b->modify_bg('prelight',$col_pris);
	    $b->set_label($self->{'liste'}->data_n($i,'_ID_')." ($pris)");
	} else {
	    $b->set_relief(GTK_RELIEF_NORMAL);
	    $b->modify_bg('prelight',undef);
	    $b->set_label($self->{'liste'}->data_n($i,'_ID_'));
	}
    } else {
	print STDERR "*** pas de bouton $i ***\n";
    }
}

sub choisit {
    my ($self,$i)=(@_);
    #print "Bouton $i\n";
    $self->lie($i,$self->{'image_etud'});
    $self->image_suivante();
}

1;

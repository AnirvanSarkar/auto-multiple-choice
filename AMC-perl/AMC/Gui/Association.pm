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

    my @liste;

    my @heads=();
    
    open LISTE,"<:encoding(".$self->{'encodage_liste'}.")",$self->{'liste'}
	or die "Erreur a l'ouverture du fichier \"$self->{'liste'}\" : $!";
  NOM: while(<LISTE>) {
      chomp();
      s/\#.*//;
      next NOM if(/^\s*$/);
      if(!@heads) {
	  if(/$self->{'separateur'}/) {
	      @heads=map { reduit($_) } split(/$self->{'separateur'}/,$_);
	      next NOM;
	  } else {
	      @heads='nom';
	  }
      }
      s/^\s+//;
      s/\s+$//;
      push @liste,[map { reduit($_) } split(/$self->{'separateur'}/,$_)];
  }
    close(LISTE);

    my %h=();
    for (0..$#heads) { $h{$heads[$_]}=$_; }
    
    $self->{'heads'}=\%h;

    print "".($#liste+1)." noms\n";
    
    return($self) if($#liste<0);
    
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
    
    my $nligs=POSIX::ceil((1+$#liste)/$self->{'assoc-ncols'});
    
    $self->{'tableau'}->resize($self->{'assoc-ncols'},$nligs);
    
    my @bouton_nom=();
    my ($x,$y)=(0,0);
    for my $i (0..$#liste) {
	my $b=Gtk2::Button->new($self->get_identifiant($liste[$i]));
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
    }

    # retenir...
    
    $self->{'liens'}={}; # inom=>etud
    $self->{'liste-noms'}=\@liste;
    $self->{'images'}=\@images;
    $self->{'boutons'}=\@bouton_nom;
    $self->{'iimage'}='';

    $self->{'gui'}->signal_autoconnect_from_package($self);

    $self->charge_image(0);

    return($self);
}

sub expose_photo {
    my ($self,$widget,$evenement,@donnees)=@_;

    $widget->expose_drawing($evenement,@donnees);
}

sub get_identifiant {
    my ($self,$n)=@_;
    my $id=$self->{'identifiant'};
    $id =~ s/\(([^\)]+)\)/(defined($self->{'heads'}->{$1}) ? $n->[$self->{'heads'}->{$1}] : '')/gei;
    $id =~ s/^\s+//;
    $id =~ s/\s+$//;
    return($id);
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
    
    my $output=new IO::File($self->{'fichier-liens'},">:encoding(".$self->{'encodage_interne'}.")");
    if(! $output) {
	print "Impossible d'ouvrir ".$self->{'fichier-liens'}." : $!";
	return();
    }
    
    my $writer = new XML::Writer(OUTPUT=>$output,NEWLINES=>1,ENCODING=>$self->{'encodage_interne'},DATA_INDENT=>2);
    $writer->xmlDecl($self->{'encodage_interne'});
    $writer->startTag('association');

    for my $i (keys %{$self->{'liens'}}) {
	$writer->startTag('etudiant',
			  'id'=>$self->{'liens'}->{$i},
			  map { $_=>$self->{'liste-noms'}->[$i]->[$self->{'heads'}->{$_}] } (keys %{$self->{'heads'}}),
			  );
	$writer->characters($self->get_identifiant($self->{'liste-noms'}->[$i]));
	$writer->endTag('etudiant');
    }
    $writer->endTag('association');
    
    $writer->end();
    $output->close();
    
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

sub get_etud {
    my $inom=shift;
    return($liens{$inom});
}

sub get_inom {
    my ($self,$etud)=(@_);
    my $i=-1;
    for my $k (keys %{$self->{'liens'}}) {
	$i=$k if($self->{'liens'}->{$k} eq $etud);
    }
    return($i);
}

sub delie {
    my ($self,$inom,$etud)=(@_);

    $self->style_bouton($inom,'');
    $self->{'liens'}->{$inom}='';
    for my $k (keys %{$self->{'liens'}}) {
	if($self->{'liens'}->{$k} eq $etud) { 
	    $self->{'liens'}->{$k}='';
	    $self->style_bouton($k,'');
	}
    }
}

sub lie {
    my ($self,$inom,$etud)=(@_);
    $self->delie($inom,$etud);
    $self->style_bouton($inom,$etud);
    $self->{'liens'}->{$inom}=$etud;
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
	  && $self->get_inom(fich2etud($self->{'images'}->[$i]))>=0 ) {
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
    my ($self,$i,$pris)=(@_);
    #print "STYLE $i <$pris>\n";
    my $b=$self->{'boutons'}->[$i];
    if($b) {
	if($pris) {
	    $b->set_relief(GTK_RELIEF_NONE);
	    $b->modify_bg('prelight',$col_pris);
	    $b->set_label($self->get_identifiant($self->{'liste-noms'}->[$i])." ($pris)");
	} else {
	    $b->set_relief(GTK_RELIEF_NORMAL);
	    $b->modify_bg('prelight',undef);
	    $b->set_label($self->get_identifiant($self->{'liste-noms'}->[$i]));
	}
    }
}

sub choisit {
    my ($self,$i)=(@_);
    #print "Bouton $i\n";
    $self->lie($i,$self->{'image_etud'});
    $self->image_suivante();
}

1;

#! /usr/bin/perl -w
#
# Copyright (C) 2009-2010 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::Notes;

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

use Encode;
use XML::Simple;

use Gtk2 -init;
use Gtk2::GladeXML;

use constant {
    TAB_ID => 0,
    TAB_NOTE => 1,
    TAB_DETAIL => 2,
};

sub ajoute_colonne {
    my ($tree,$store,$titre,$i)=@_;
    my $renderer=Gtk2::CellRendererText->new;
    my $column = Gtk2::TreeViewColumn->new_with_attributes(
	decode('utf-8',$titre),
	$renderer,
	text=> $i);
    $column->set_sort_column_id($i);
    $tree->append_column($column);
    $store->set_sort_func($i,\&sort_num,$i);
}

sub formatte {
    my ($x)=@_;
    $x=(defined($x) ? sprintf("%.2f",$x) : '');
    $x =~ s/0+$//;
    $x =~ s/\.$//;
    return($x);
}

sub new {
    my %o=(@_);
    my $self={'fichier'=>'',
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;

    my $notes=eval { XMLin($self->{'fichier'},
			   'ForceArray'=>1,
			   'KeyAttr'=>['id'],
			   ) };

    if(!$notes) {
	print STDERR "Error analysing marks file ".$self->{'fichier'}."\n";
	return($self);
    }
    
    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{'gui'}=Gtk2::GladeXML->new($glade_xml,undef,'auto-multiple-choice');

    for my $k (qw/general tableau/) {
	$self->{$k}=$self->{'gui'}->get_widget($k);
    }
    
    $self->{'gui'}->signal_autoconnect_from_package($self);

    my @codes=sort { $a cmp $b } (keys %{$notes->{'code'}});
    my @keys=sort { $a cmp $b } grep { if(s/\.[0-9]+$//) { !$notes->{'code'}->{$_} } else { 1; } } (keys %{$notes->{'copie'}->{'max'}->{'question'}});
    
    print STDERR "CODES : ".join(",",@codes)."\n";
    print STDERR "KEYS : ".join(",",@keys)."\n";

    my $store = Gtk2::ListStore->new ( map {'Glib::String' } (1..(2+1+$#codes+1+$#keys)) ); 

    $self->{'tableau'}->set_model($store);

    ajoute_colonne($self->{'tableau'},$store,"copie",TAB_ID);
    ajoute_colonne($self->{'tableau'},$store,"note",TAB_NOTE);

    my $i=TAB_DETAIL ;
    for(@keys,@codes) {
	ajoute_colonne($self->{'tableau'},$store,$_,$i++);
    }

  COPIE:for my $k (sort { $a cmp $b } (keys %{$notes->{'copie'}})) {
      my $c=$notes->{'copie'}->{$k};
      my $it=$store->append();
      
      $store->set($it,
		  TAB_ID,$k,
		  TAB_NOTE,formatte($c->{'total'}->[0]->{'note'}),
		  );
      
      my $i=TAB_DETAIL ;
      for(@keys) {
	  $store->set($it,$i++,
		      formatte($c->{'question'}->{$_}->{'note'}));
      }
      for(@codes) {
	  $store->set($it,$i++,$c->{'code'}->{$_}->{'content'});
      }
  }

    return($self);
}

sub quitter {
    my ($self)=(@_);

    if($self->{'global'}) {
	Gtk2->main_quit;
    } else {
	$self->{'gui'}->get_widget('general')->destroy;
    }
}

1;

__END__

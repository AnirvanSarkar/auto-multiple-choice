#! /usr/bin/perl
#
# Copyright (C) 2011 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::Zooms;

use AMC::Basic;
use AMC::ANList;

use Gtk2 -init;
use Gtk2::GladeXML;

use XML::Simple;

use POSIX qw(ceil);

sub new {
    my %o=(@_);

    my $self={
	'n_cols'=>4,
	'factor'=>0.75,
	'seuil'=>0.15,
	'global'=>0,
	'zooms_dir'=>"",
	'page_id'=>'',
	'an-data'=>'',
	'cr-dir'=>'',
	'size-prefs'=>'',
    };
    
    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    $self->{'ids'}=[];
    $self->{'pb_src'}={};
    $self->{'pb'}={};
    $self->{'image'}={};
    $self->{'label'}={};
    $self->{'n_ligs'}={};

    bless $self;

    if($self->{'an-data'}) {
	$self->{'an_list'}=$self->{'an-data'};
    } else {
	debug "Making again ANList...";
	$self->{'an_list'}=AMC::ANList::new($self->{'cr-dir'});
	debug "ok";
    }

    $self->{'ANS'}=$self->{'an_list'}->analyse($self->{'page_id'},'scan'=>1);
    $self->{'AN'}=$self->{'an_list'}->analyse($self->{'page_id'});

    if($self->{'size-prefs'}) {
	$self->{'factor'}=$self->{'size-prefs'}->{'zoom_window_factor'}
	if($self->{'size-prefs'}->{'zoom_window_factor'});
    }
    $self->{'factor'}=0.1 if($self->{'factor'}<0.1);
    $self->{'factor'}=5 if($self->{'factor'}>5);

    my @ids;
    
    for my $id (keys %{$self->{'ANS'}->{'case'}}) {
	my $fid=$id;
	$fid =~ s/\./-/;
	$fid=$self->{'zooms_dir'}."/$fid.png";
	if(-f $fid) {
	    $self->{'pb_src'}->{$id}=
		Gtk2::Gdk::Pixbuf->new_from_file($fid);
	    $self->{'image'}->{$id}=Gtk2::Image->new();
	    $self->{'label'}->{$id}=Gtk2::Label->new(sprintf("%.3f",$self->{'ANS'}->{'case'}->{$id}->{'r'}));
	    push @ids,$id;
	}
    }
    
    $self->{'ids'}=[sort { $self->{'ANS'}->{'case'}->{$a}->{'r'} <=> $self->{'ANS'}->{'case'}->{$b}->{'r'} } (@ids)];
    
    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;
    
    $self->{'gui'}=Gtk2::GladeXML->new($glade_xml,undef,'auto-multiple-choice');
    
    for(qw/main_window zooms_table_0 zooms_table_1 decoupage view_0 view_1 scrolled_0 scrolled_1 label_0 label_1 button_apply button_close info/) {
	$self->{$_}=$self->{'gui'}->get_widget($_);
    }
    
    $self->{'label_0'}->set_markup('<b>'.$self->{'label_0'}->get_text.'</b>');
    $self->{'label_1'}->set_markup('<b>'.$self->{'label_1'}->get_text.'</b>');
    $self->{'info'}->set_markup('<b>'.sprintf(__("Boxes zooms for page %s"),$self->{'page_id'}).'</b>');

    $self->{'decoupage'}->child1_resize(1);
    $self->{'decoupage'}->child2_resize(1);

    $self->remplit(0);
    $self->remplit(1);
    $self->zoom_it();
    
    $self->{'gui'}->signal_autoconnect_from_package($self);
    
    if($self->{'size-prefs'}) {
	my @s=$self->{'main_window'}->get_size();
	$s[1]=$self->{'size-prefs'}->{'zoom_window_height'};
	$s[1]=200 if($s[1]<200);
	$self->{'main_window'}->resize(@s);
    }

    $self->{'main_window'}->show_all();
    $self->{'button_apply'}->hide();

    Gtk2->main_iteration while ( Gtk2->events_pending );

    $self->ajuste_sep();
    
    my $va=$self->{'view_0'}->get_vadjustment();
    $va->value($va->upper());

    return($self);
}

sub remplit {
    my ($self,$cat)=@_;
    my @good_ids=grep { 
	$r=$self->{'AN'}->{'case'}->{$_}->{'r'};
	($cat==1 ? $r>=$self->{'seuil'} : $r<$self->{'seuil'}); }
    (@{$self->{'ids'}});

    my $n_ligs=ceil((@good_ids ? (1+$#good_ids)/$self->{'n_cols'} : 1));
    $self->{'zooms_table_'.$cat}->resize($n_ligs,$self->{'n_cols'});
    $self->{'n_ligs'}->{$cat}=$n_ligs;
    
    for my $i (0..$#good_ids) {
	my $id=$good_ids[$i];
	my $x=$i % $self->{'n_cols'};
	my $y=int($i/$self->{'n_cols'});
	
	my $hb=Gtk2::HBox->new();
	
	$self->{'label'}->{$id}->set_justify(GTK_JUSTIFY_LEFT);
	
	$hb->add($self->{'image'}->{$id});
	$hb->add($self->{'label'}->{$id});
	
	$self->{'zooms_table_'.$cat}->attach($hb,$x,$x+1,$y,$y+1,[],[],4,3);
    }
}

sub ajuste_sep {
    my ($self)=@_;
    my $s=$self->{'decoupage'}->get_property('max-position');
    
    $self->{'decoupage'}->set_position($self->{'n_ligs'}->{0}/($self->{'n_ligs'}->{0}+$self->{'n_ligs'}->{1})*$s);
}

sub zoom_it {
    my ($self)=@_;
    for my $id (@{$self->{'ids'}}) {
	$self->{'pb'}->{$id}=$self->{'pb_src'}->{$id}->scale_simple(int($self->{'pb_src'}->{$id}->get_width * $self->{'factor'}),int($self->{'pb_src'}->{$id}->get_height * $self->{'factor'}),GDK_INTERP_BILINEAR);
	$self->{'image'}->{$id}->set_from_pixbuf($self->{'pb'}->{$id});
    }
    $self->{'zooms_table_0'}->queue_resize();
    $self->{'zooms_table_1'}->queue_resize();
    my @size=$self->{'main_window'}->get_size();
    $size[0]=1;
    $self->{'main_window'}->resize(@size);
}

sub zoom_avant {
    my ($self)=@_;
    $self->{'factor'} *= 1.25;
    $self->zoom_it();
}

sub zoom_arriere {
    my ($self)=@_;
    $self->{'factor'} /= 1.25;
    $self->zoom_it();
}

sub close {
    my ($self)=@_;

    if($self->{'size-prefs'}) {
	my ($x,$y)=$self->{'main_window'}->get_size();
	$self->{'size-prefs'}->{'zoom_window_factor'}=$self->{'factor'};
	$self->{'size-prefs'}->{'zoom_window_height'}=$y;
	$self->{'size-prefs'}->{'_modifie_ok'}=1;
    }

    if($self->{'global'}) {
        Gtk2->main_quit;
    } else {
        $self->{'main_window'}->destroy;
    }
}

1;

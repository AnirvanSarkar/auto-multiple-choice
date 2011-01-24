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

use constant ID_AMC_BOX => 100;

my $col_manuel = Gtk2::Gdk::Color->new(223*256,224*256,133*256);
my $col_modif = Gtk2::Gdk::Color->new(226*256,184*256,178*256);

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
	'encodage_interne'=>'UTF-8',
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
    $self->{'position'}={};
    $self->{'eb'}={};
    $self->{'conforme'}=1;

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
	    $self->{'label'}->{$id}->set_justify(GTK_JUSTIFY_LEFT);

	    my $hb=Gtk2::HBox->new();
	    $self->{'eb'}->{$id}=Gtk2::EventBox->new();
	    $self->{'eb'}->{$id}->add($hb);
	    
	    $hb->add($self->{'image'}->{$id});
	    $hb->add($self->{'label'}->{$id});
	
	    $self->{'eb'}->{$id}->drag_source_set(GDK_BUTTON1_MASK,
						  GDK_ACTION_MOVE,
						  {
						      target => 'STRING',
						      flags => [],
						      info => ID_AMC_BOX,
						  });
	    $self->{'eb'}->{$id}->signal_connect(
		'drag-data-get' => \&source_drag_data_get,
		$id );
	    $self->{'eb'}->{$id}->signal_connect(
		'drag-begin'=>sub {
		    $self->{'eb'}->{$id}
		    ->drag_source_set_icon_pixbuf($self->{'image'}->{$id}->get_pixbuf);
		});
	    
	    push @ids,$id;
	}
    }
    
    $self->{'ids'}=[sort { $self->{'ANS'}->{'case'}->{$a}->{'r'} <=> $self->{'ANS'}->{'case'}->{$b}->{'r'} } (@ids)];
    
    for my $id (@{$self->{'ids'}}) {
	$self->{'position'}->{$id}=$self->category($id,'AN');
    }

    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;
    
    $self->{'gui'}=Gtk2::GladeXML->new($glade_xml,undef,'auto-multiple-choice');
    
    for(qw/main_window zooms_table_0 zooms_table_1 decoupage view_0 view_1 scrolled_0 scrolled_1 label_0 label_1 event_0 event_1 button_apply button_close info/) {
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

    for(0,1) {
	$self->{'event_'.$_}->drag_dest_set('all', [GDK_ACTION_MOVE],
					    {'target' => 'STRING',
					      'flags' => [],
					      'info' => ID_AMC_BOX },
					    );
	$self->{'event_'.$_}->signal_connect(
	    'drag-data-received' => \&target_drag_data_received,[$self,$_]);
    }

    
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

sub refill {
    my ($self)=@_;
    $self->{'conforme'}=1;
    for(0,1) { $self->vide($_); }
    for(0,1) { $self->remplit($_); }
    if($self->{'conforme'}) {
	$self->{'button_apply'}->hide();
    } else {
	$self->{'button_apply'}->show();
    }
}

sub category {
    my ($self,$id,$antype)=@_;
    return($self->{$antype}->{'case'}->{$id}->{'r'}>$self->{'seuil'} ? 1 : 0);
}

sub source_drag_data_get {
    my ($widget, $context, $data, $info, $time,$string) = @_;
    $data->set_text($string,-1);
}

sub target_drag_data_received {
    my ($widget, $context, $x, $y, $data, $info, $time,$args) = @_;
    my ($self,$cat)=@$args;
    my $id=$data->get_text();
    debug "Page ".$self->{'page_id'}.": move $id to category $cat\n";
    if($self->{'position'}->{$id} != $cat) {
	$self->{'position'}->{$id}=$cat;
	$self->refill;
    }
}

sub vide {
    my ($self,$cat)=@_;
    for($self->{'zooms_table_'.$cat}->get_children) {
	$self->{'zooms_table_'.$cat}->remove($_);
    }
}

sub remplit {
    my ($self,$cat)=@_;

    my @good_ids=grep { $self->{'position'}->{$_} == $cat } (@{$self->{'ids'}});

    my $n_ligs=ceil((@good_ids ? (1+$#good_ids)/$self->{'n_cols'} : 1));
    $self->{'zooms_table_'.$cat}->resize($n_ligs,$self->{'n_cols'});
    $self->{'n_ligs'}->{$cat}=$n_ligs;
    
    for my $i (0..$#good_ids) {
	my $id=$good_ids[$i];
	my $x=$i % $self->{'n_cols'};
	my $y=int($i/$self->{'n_cols'});
	
	if($self->category($id,'AN') != $cat) {
	    $self->{'eb'}->{$id}->modify_bg(GTK_STATE_NORMAL,$col_modif);
	    $self->{'conforme'}=0;
	} else {
	    if($self->category($id,'ANS') == $cat) {
		$self->{'eb'}->{$id}->modify_bg(GTK_STATE_NORMAL,undef);
	    } else {
		$self->{'eb'}->{$id}->modify_bg(GTK_STATE_NORMAL,$col_manuel);
	    }
	}

	$self->{'zooms_table_'.$cat}->attach($self->{'eb'}->{$id},
					     $x,$x+1,$y,$y+1,[],[],4,3);
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

sub quit {
    my ($self)=@_;

    if($self->{'size-prefs'}) {
	my ($x,$y)=$self->{'main_window'}->get_size();
	$self->{'size-prefs'}->{'zoom_window_factor'}=$self->{'factor'};
	$self->{'size-prefs'}->{'zoom_window_height'}=$y;
	$self->{'size-prefs'}->{'_modifie_ok'}=1;
    }
    
    if(!$self->{'conforme'}) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($self->{'main_window'},
			      'destroy-with-parent',
			      'warning','yes-no',
			      __"You moved some boxes to correct automatic data query, but this work is not saved yet. Dou you really want to close and ignore these modifications?"
	    );
	my $reponse=$dialog->run;
	$dialog->destroy;      
	return() if($reponse eq 'no');
    }

    if($self->{'global'}) {
        Gtk2->main_quit;
    } else {
        $self->{'main_window'}->destroy;
    }
}

sub all_keys {
    my ($self)=@_;
    my %k=();
    for(keys %{$self->{'AN'}->{'case'}}) {
	$k{$_}=1;
    }
    for(keys %{$self->{'position'}}) {
	$k{$_}=1;
    }
    return(keys %k);
}

sub checked {
    my ($self,$id)=@_;
    if(defined($self->{'position'}->{$id})) {
	return($self->{'position'}->{$id});
    } else {
	$self->category($id,'AN');
    }
}

sub apply {
    my ($self)=@_;

    # save modifications to a manual analysis file
    my $file=$self->{'cr-dir'}."/analyse-manuelle-".id2idf($self->{'page_id'}).".xml";

    debug "Saving file $file";
    if(open(XML,">:encoding(".$self->{'encodage_interne'}.")",$file)) {
	print XML "<?xml version='1.0' encoding='".$self->{'encodage_interne'}."' standalone='yes'?>\n<analyse src=\""
	    .$self->{'AN'}->{'src'}."\" manuel=\"1\" id=\""
	    .$self->{'page_id'}."\" nometudiant=\""
	    .$self->{'AN'}->{'nometudiant'}."\">\n";
	for my $id ($self->all_keys()) {
	    my ($q,$r)=get_qr($id);
	    print XML "  <case id=\"$id\" question=\"$q\" reponse=\"$r\" r=\""
		.$self->checked($id)."\"/>\n";
	}
	print XML "</analyse>\n";
	close(XML);
	
	$self->{'conforme'}=1;
	$self->quit();
    } else {
	# error opening file
	my $dialog = Gtk2::MessageDialog
            ->new_with_markup($self->{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      sprintf(__("Error saving to <i>%s</i>: <b>%s</b>"),
				      $file,$!));
	$dialog->run;
	$dialog->destroy;
    }

}

1;

#! /usr/bin/perl -w
#
# Copyright (C) 2008-2014 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::PageArea;

use Gtk3;
use AMC::Basic;

@ISA=("Gtk3::DrawingArea");

sub add_feuille {
    my ($self,%oo)=@_;
    bless($self,"AMC::Gui::PageArea");

    $self->{image_file}='';
    $self->{text}='';
    $self->{background_color}='';

    $self->{'marks'}='';

    $self->{'i-src'}='';
    $self->{'tx'}=1;
    $self->{'ty'}=1;
    $self->{'yfactor'}=1;

    $self->{'min_render_size'}=10;

    $self->{'case'}='';
    $self->{'coches'}='';
    $self->{'editable'}=1;

    $self->{'onscan'}='';
    $self->{'unticked_color_name'}="#429DE5";
    $self->{question_color_name}="#47D265";
    $self->{scorezone_color_name}="#DE61E2";
    $self->{drawings_color_name}="red";

    $self->{'font'}=Pango::FontDescription::from_string("128");

    for (keys %oo) {
	$self->{$_}=$oo{$_} if(defined($self->{$_}));
    }

    $self->{'text_color'}=Gtk3::Gdk::RGBA::parse('black');
    $self->{'scorezone_color'}=
      Gtk3::Gdk::RGBA::parse($self->{scorezone_color_name});
    $self->{'question_color'}=
      Gtk3::Gdk::RGBA::parse($self->{question_color_name});
    $self->{'unticked_color'}=
      Gtk3::Gdk::RGBA::parse($self->{'unticked_color_name'});
    $self->{'drawings_color'}=
      Gtk3::Gdk::RGBA::parse($self->{'drawings_color_name'});

    if($self->{'marks'}) {
	$self->{'colormark'}= Gtk3::Gdk::RGBA::parse($self->{'marks'});
    }

    $self->signal_connect('size-allocate'=>\&allocate_drawing);
    $self->signal_connect('draw'=>\&draw);

    return($self);
}

sub set_background {
  my ($self,$color)=@_;
  if($color) {
    $self->{background_color}=Gtk3::Gdk::RGBA::parse($color);
  } else {
    $self->{background_color}='';
  }
}

sub set_text {
  my ($self,$text)=@_;
  $self->{text}=$text;
}

sub set_image {
    my ($self,$image,$layinfo)=@_;
    $self->{image_file}=$image;
    if($image && -f $image) {
      eval { $self->{'i-src'}=Gtk3::Gdk::Pixbuf->new_from_file($image); };
      if($@) {
	# Error loading scan...
	$self->{'i-src'}='';
      } else {
	$layinfo->{'page'}->{'width'}=$self->{'i-src'}->get_width
	  if(!$layinfo->{'page'}->{'width'});
	$layinfo->{'page'}->{'height'}=$self->{'i-src'}->get_height
	  if(!$layinfo->{'page'}->{'height'});
      }
    } else {
      $self->{'i-src'}='';
    }
    $self->{'layinfo'}=$layinfo;
    $self->{'modifs'}=0;
    $self->allocate_drawing();
    $self->get_window->show;
}

sub set_content {
  my ($self,%o)=@_;
  $self->set_background($o{background_color});
  $self->set_text($o{text});
  $self->set_image($o{image},$o{layout_info});
}

sub get_image {
   my ($self)=@_;
   return($self->{'i-src'});
 }

sub modifs {
    my $self=shift;
    return($self->{'modifs'});
}

sub sync {
    my $self=shift;
    $self->{'modifs'}=0;
}

sub modif {
    my $self=shift;
    $self->{'modifs'}=1;
}

sub choix {
  my ($self,$event)=(@_);

  if(!$self->{'editable'}) {
    return TRUE;
  }

  if($self->{'layinfo'}->{'block_message'}) {
    my $dialog = Gtk3::MessageDialog
      ->new(undef,
	    'destroy-with-parent',
	    'error','ok','');
    $dialog->set_markup($self->{'layinfo'}->{'block_message'});
    $dialog->run;
    $dialog->destroy;

    return TRUE;
  }

  if($self->{'layinfo'}->{'box'}) {

      if ($event->button == 1) {
	  my ($x,$y)=($event->x,$event->y);
	  debug "Click $x $y\n";
	  for my $i (@{$self->{'layinfo'}->{'box'}}) {

	      if($x<=$i->{'xmax'}*$self->{'rx'} && $x>=$i->{'xmin'}*$self->{'rx'}
		 && $y<=$i->{'ymax'}*$self->{'ry'} && $y>=$i->{'ymin'}*$self->{'ry'}) {
		  $self->{'modifs'}=1;

		  debug " -> box $i\n";
		  $i->{'ticked'}=!$i->{'ticked'};

		  $self->get_window->show;
	      }
	  }
      }

  }
  return TRUE;
}

sub draw_box {
  my ($self,$context,$box,$fill)=@_;

  if($box->{'xy'}) {
    $context->new_path;
    $context->move_to($box->{'xy'}->[0]*$self->{'rx'},
		      $box->{'xy'}->[1]*$self->{'ry'});
    for my $i (1..3) {
      $context->line_to($box->{'xy'}->[$i*2]*$self->{'rx'},
			$box->{'xy'}->[$i*2+1]*$self->{'ry'});
    }
    $context->close_path;
    if($fill) { $context->fill; }
    else { $context->stroke; }
  } else {
    $context->new_path();
    $context->rectangle
      (
       $box->{'xmin'}*$self->{'rx'},
       $box->{'ymin'}*$self->{'ry'},
       ($box->{'xmax'}-$box->{'xmin'})*$self->{'rx'},
       ($box->{'ymax'}-$box->{'ymin'})*$self->{'ry'}
      );
    if($fill) { $context->fill; }
    else { $context->stroke; }
  }
}

sub allocate_drawing {
  my ($self,$evenement,@donnees)=@_;
  my $r=$self->get_allocation;

  if($self->{'i-src'}) {

    $self->{'tx'}=$r->{width};
    $self->{'ty'}=$self->{'yfactor'}*$r->{height};

    debug("Rendering target size: ".$self->{'tx'}."x".$self->{'ty'});

    my $sx=$self->{'tx'}/$self->{'i-src'}->get_width;
    my $sy=$self->{'ty'}/$self->{'i-src'}->get_height;

    if($sx<$sy) {
      $self->{'ty'}=int($self->{'i-src'}->get_height*$sx);
      $sy=$self->{'ty'}/$self->{'i-src'}->get_height;
    }
    if($sx>$sy) {
      $self->{'tx'}=int($self->{'i-src'}->get_width*$sy);
      $sx=$self->{'tx'}/$self->{'i-src'}->get_width;
    }

    $self->{'sx'}=$sx;
    $self->{'sy'}=$sy;

    $self->set_size_request(-1,$self->{'ty'})
      if($self->{'yfactor'}>1);
  } else {
    $self->{tx}=$r->{width};
    $self->{ty}=$r->{height};
  }

  0;
}

sub draw {
    my ($self,$context)=@_;

    $self->allocate_drawing() if(!$self->{'sx'} || !$self->{'sy'});

    return() if($self->{'tx'}<$self->{'min_render_size'}
		|| $self->{'ty'}<$self->{'min_render_size'});

    if($self->{background_color}) {
      debug("Background color");
      Gtk3::Gdk::cairo_set_source_rgba($context,$self->{background_color});
      $context->paint();
    }

    if($self->{text}) {
      Gtk3::Gdk::cairo_set_source_rgba($context,$self->{text_color});
      $context->set_font_size(20);
      my $ext=$context->text_extents($self->{text});
      my $r=$self->{'tx'}/$ext->{width};
      my $ry=$self->{'ty'}/$ext->{height};
      $r=$ry if($ry<$r);
      $context->set_font_size(20*$r);
      $ext=$context->text_extents($self->{text});
      $context->move_to(-$ext->{x_bearing}+int(($self->{tx}-$ext->{width})/2),
			-$ext->{y_bearing});
      $context->show_text($self->{text});
      $context->stroke();
    }

    if($self->{'i-src'}) {
      my $sx=$self->{'sx'};
      my $sy=$self->{'sy'};

      debug("Rendering with SX=$sx SY=$sy");

      my $i=Gtk3::Gdk::Pixbuf->new(GDK_COLORSPACE_RGB,1,8,$self->{'tx'},$self->{'ty'});

      $self->{'i-src'}->scale($i,0,0,$self->{'tx'},$self->{'ty'},0,0,
			      $sx,$sy,
			      GDK_INTERP_BILINEAR);

      Gtk3::Gdk::cairo_set_source_pixbuf($context,$i,0,0);
      $context->paint();

      debug "Done with rendering";
    }

    if(($self->{'layinfo'}->{'box'} || $self->{'layinfo'}->{'namefield'})
      && ($self->{'layinfo'}->{'page'}->{'width'})) {
	my $box;

	debug "Layout drawings...";

	$self->{'rx'}=$self->{'tx'}/$self->{'layinfo'}->{'page'}->{'width'};
	$self->{'ry'}=$self->{'ty'}/$self->{'layinfo'}->{'page'}->{'height'};

	# layout drawings

	if($self->{'marks'}) {
	    Gtk3::Gdk::cairo_set_source_rgba($context,$self->{'colormark'});

	    for $box (@{$self->{'layinfo'}->{'namefield'}}) {
		$self->draw_box($context,$box,'');
	    }

	    $box=$self->{'layinfo'}->{'mark'};

	    if($box) {
	      $context->new_path;
	      for my $i (0..3) {
		my $j=(($i+1) % 4);
		$context->move_to($box->[$i]->{'x'}*$self->{'rx'},
				  $box->[$i]->{'y'}*$self->{'ry'});
		$context->line_to($box->[$j]->{'x'}*$self->{'rx'},
				  $box->[$j]->{'y'}*$self->{'ry'});
	      }
	      $context->stroke;
	    }

	    for my $box (@{$self->{'layinfo'}->{'digit'}}) {
	      $self->draw_box($context,$box,'');
	    }

	}

	## boxes drawings

	if($self->{'onscan'}) {
	  Gtk3::Gdk::cairo_set_source_rgba($context,$self->{'drawings_color'});
	  for $box (grep { $_->{'ticked'} }
		    @{$self->{'layinfo'}->{'box'}}) {
	    $self->draw_box($context,$box,'');
	  }
	  Gtk3::Gdk::cairo_set_source_rgba($context,$self->{'unticked_color'});
	  for $box (grep { ! $_->{'ticked'} }
		    @{$self->{'layinfo'}->{'box'}}) {
	    $self->draw_box($context,$box,'');
	  }
	} else {
	  Gtk3::Gdk::cairo_set_source_rgba($context,$self->{'drawings_color'});
	  for $box (@{$self->{'layinfo'}->{'box'}}) {
	    $self->draw_box($context,$box,$box->{'ticked'});
	  }
	  Gtk3::Gdk::cairo_set_source_rgba($context,$self->{'question_color'});
	  for $box (@{$self->{'layinfo'}->{'questionbox'}}) {
	    $self->draw_box($context,$box,'');
	  }
	}
	Gtk3::Gdk::cairo_set_source_rgba($context,$self->{'scorezone_color'});
	for $box (@{$self->{'layinfo'}->{'scorezone'}}) {
	  $self->draw_box($context,$box,'');
	}

	debug "Done.";
    }
}

1;

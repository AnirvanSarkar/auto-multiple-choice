#
# Copyright (C) 2011-2012 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Export::List;

use File::Temp qw/ tempfile tempdir /;
use Gtk2;
use Cairo;

use AMC::Basic;
use AMC::Export;

@ISA=("AMC::Export");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    $self->{'out.encodage'}='utf-8';
    $self->{'out.decimal'}=",";
    $self->{'out.pagesize'}="a4";
    $self->{'out.ncols'}=2;
    $self->{'out.margin'}=30;
    $self->{'out.sep'}=10;
    $self->{'out.font'}="FreeSans 8";
    $self->{'out.nom'}="";
    $self->{'out.code'}="";

    $self->{'icol'}=-1;
    bless ($self, $class);
    return $self;
}

sub parse_num {
    my ($self,$n)=@_;
    if($self->{'out.decimal'} ne '.') {
	$n =~ s/\./$self->{'out.decimal'}/;
    }
    return($n);
}

sub dims {
    my ($self)=@_;

    if(lc($self->{'out.pagesize'}) eq 'a3') {
	$self->{'page_x'}=841.88976;
	$self->{'page_y'}=1190.5512;
    } elsif(lc($self->{'out.pagesize'}) eq 'letter') {
	$self->{'page_x'}=612;
	$self->{'page_y'}=792;
    } elsif(lc($self->{'out.pagesize'}) eq 'legal') {
	$self->{'page_x'}=612;
	$self->{'page_y'}=1008;
    } else { # a4
	$self->{'page_x'}=595.27559;
	$self->{'page_y'}=841.88976;
    }

    my $dispo=$self->{'page_x'}-2*$self->{'out.margin'}-($self->{'out.ncols'}-1)*$self->{'out.sep'};

    $self->{'space'}=2;
    $self->{'cs_mark'}=50;
    $self->{'cs_name'}=$dispo/$self->{'out.ncols'}-$self->{'cs_mark'};

    $self->{'y0'}=$self->{'out.margin'};
}

sub show_title {
    my ($self)=@_;

    if($self->{'out.nom'}) {
	my $l0=Pango::Cairo::create_layout($self->{'context'});
	$l0->set_font_description (Pango::FontDescription->from_string ($self->{'out.font'}));

	$l0->set_text($self->{'out.nom'});
	($text_x,$text_y)=$l0->get_pixel_size();
	if($self->{'out.rtl'}) {
	    $self->{'context'}->move_to($self->{'page_x'}-$text_x-$self->{'out.margin'},
					$self->{'out.margin'});
	} else {
	    $self->{'context'}->move_to($self->{'out.margin'},$self->{'out.margin'});
	}
	Pango::Cairo::show_layout($self->{'context'},$l0);
	$self->{'y0'}=$text_y+2*$self->{'out.margin'};
    }
}

sub dx_dir {
    my ($self,$droite)=@_;
    return($self->{ (!$droite != !$self->{'out.rtl'} ? 'cs_mark' : 'cs_name' ) });
}

sub debut_col {
    my ($self)=@_;

    $self->{'icol'}++;
    if($self->{'icol'}>=$self->{'out.ncols'}) {
	$self->{'icol'}=0 ;
	$self->{'context'}->show_page();
    }

    $self->show_title if($self->{'icol'}==0);

    $self->{'x'}=$self->{'out.margin'}+$self->{'cs_name'}+
	$self->{'icol'}*($self->{'cs_mark'}+$self->{'cs_name'}+$self->{'out.sep'});
    $self->{'x'}=$self->{'page_x'}-$self->{'x'} if($self->{'out.rtl'});
    $self->{'y'}=$self->{'y0'};

    $self->{'context'}->move_to($self->{'x'}-$self->dx_dir(0),$self->{'y'});
    $self->{'context'}->line_to($self->{'x'}+$self->dx_dir(1),$self->{'y'});
}

sub export {
    my ($self,$fichier)=@_;

    $self->pre_process();

    $self->dims();

    $self->{'surface'}=Cairo::PdfSurface->create($fichier,
					  $self->{'page_x'},
					  $self->{'page_y'});
    $self->{'context'} = Cairo::Context->create ($self->{'surface'});
    $self->{'layout'}=Pango::Cairo::create_layout($self->{'context'});
    $self->{'layout'}->set_font_description (Pango::FontDescription->from_string ($self->{'out.font'}));
    $self->{'context'}->set_line_width(.5);
    my $text_x;
    my $text_y;
    my $y0;

    $self->debut_col();

    for my $m (@{$self->{'marks'}}) {

	# strings to write in columns
	my $name=$m->{'student.name'};
	my $mark=$m->{'mark'};

	# prepares writting name
	$self->{'layout'}->set_text($name);
	($text_x,$text_y)=$self->{'layout'}->get_pixel_size();

	# remove end characters while string is too long
	while($name && $text_x > $self->{'cs_name'}-6*$self->{'space'}) {
	    $name =~s/.$//;
	    $self->{'layout'}->set_text($name);
	    ($text_x,$text_y)=$self->{'layout'}->get_pixel_size();
	}

	# go to next column if necessary
	if($self->{'y'}+2*$self->{'space'}+$text_y+$self->{'out.margin'}
	   > $self->{'page_y'}) {
	    $self->debut_col();
	}

	$y0=$self->{'y'};

	$self->{'y'}+=$self->{'space'};

	if($self->{'out.rtl'}) {
	    $self->{'context'}->move_to($self->{'x'}+$self->{'cs_name'}
					-3*$self->{'space'}-$text_x,
					$self->{'y'});
	} else {
	    $self->{'context'}->move_to($self->{'x'}-$text_x-3*$self->{'space'},
					$self->{'y'});
	}
	Pango::Cairo::show_layout($self->{'context'},$self->{'layout'});

	# writes grade

	$self->{'layout'}->set_text($self->parse_num($mark));
	($text_x,$text_y)=$self->{'layout'}->get_pixel_size();
	if($self->{'out.rtl'}) {
	    $self->{'context'}->move_to($self->{'x'}-($self->{'cs_mark'}+$text_x)/2,
					$self->{'y'});
	} else {
	    $self->{'context'}->move_to($self->{'x'}+($self->{'cs_mark'}-$text_x)/2,
					$self->{'y'});
	}
	Pango::Cairo::show_layout($self->{'context'},$self->{'layout'});

	$self->{'y'}+=$text_y+$self->{'space'};

	# lines

	$self->{'context'}->move_to($self->{'x'}-$self->dx_dir(0),$self->{'y'});
	$self->{'context'}->line_to($self->{'x'}+$self->dx_dir(1),$self->{'y'});
	for my $xx ($self->{'x'},
		    $self->{'x'}-$self->dx_dir(0),
		    $self->{'x'}+$self->dx_dir(1)) {
	    $self->{'context'}->move_to($xx,$self->{'y'});
	    $self->{'context'}->line_to($xx,$y0);
	}
	$self->{'context'}->stroke();
    }

    $self->{'context'}->show_page();

}

sub name {
# TRANSLATORS: List of students with their scores: one of the export formats.
  return(__("PDF list"));
}

sub options_from_config {
  my ($self,$options_project,$options_main,$options_default)=@_;
  return("nom"=>$options_project->{'nom_examen'},
	 "code"=>$options_project->{'code_examen'},
	 "decimal"=>$options_main->{'delimiteur_decimal'},
	 "pagesize"=>$options_project->{'export_pagesize'},
	 "ncols"=>$options_project->{'export_ncols'},
	);
}

sub options_default {
  return('export_ncols'=>2,
	 'export_pagesize'=>'a4');
}

sub needs_module {
  return();
}

sub build_config_gui {
  my ($self,$w,$cb)=@_;
  my $t=Gtk2::Table->new(2,2);
  my $widget;
  my $y=0;
  $t->attach(Gtk2::Label->new(__"Number of columns"),
	     0,1,$y,$y+1,["expand","fill"],[],0,0);
  $widget=Gtk2::SpinButton->new(Gtk2::Adjustment->new(1,1,5,1,1,0),0,0);
  $w->{'export_s_export_ncols'}=$widget;
  $t->attach($widget,1,2,$y,$y+1,["expand","fill"],[],0,0);
  $y++;
  $t->attach(Gtk2::Label->new(__"Paper size"),0,1,$y,$y+1,["expand","fill"],[],0,0);
  $widget=Gtk2::ComboBox->new_with_model();
  my $renderer = Gtk2::CellRendererText->new();
  $widget->pack_start($renderer, TRUE);
  $widget->add_attribute($renderer,'text',COMBO_TEXT);
  $cb->{'export_pagesize'}=cb_model("a3"=>"A3",
				    "a4"=>"A4",
				    "letter"=>"Letter",
				    "legal"=>"Legal");
  $w->{'export_c_export_pagesize'}=$widget;
  $t->attach($widget,1,2,$y,$y+1,["expand","fill"],[],0,0);
  $y++;

  $t->show_all;
  return($t);
}

sub weight {
  return(.5);
}

1;

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

package AMC::Export::List;

use File::Temp qw/ tempfile tempdir /;
use Gtk2;
use Cairo;

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
	$self->{'context'}->move_to($self->{'out.margin'},$self->{'out.margin'});
	Pango::Cairo::show_layout($self->{'context'},$l0);
	$self->{'y0'}=$text_y+2*$self->{'out.margin'};
    }
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
    $self->{'y'}=$self->{'y0'};

    $self->{'context'}->move_to($self->{'x'}-$self->{'cs_name'},$self->{'y'});
    $self->{'context'}->line_to($self->{'x'}+$self->{'cs_mark'},$self->{'y'});
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

    for my $etu (grep { ! /^(max|moyenne)$/ } (@{$self->{'copies'}})) {

	my $nom=$self->{'c'}->{$etu}->{'_NOM_'};
	my $note=$self->{'c'}->{$etu}->{'_NOTE_'};

	$self->{'layout'}->set_text($nom);
	($text_x,$text_y)=$self->{'layout'}->get_pixel_size();

	if($self->{'y'}+2*$self->{'space'}+$text_y+$self->{'out.margin'}
	   > $self->{'page_y'}) {
	    $self->debut_col();
	}
	
	$y0=$self->{'y'};

	$self->{'y'}+=$self->{'space'};

	$self->{'context'}->move_to($self->{'x'}-$text_x-3*$self->{'space'},
			  $self->{'y'});
	Pango::Cairo::show_layout($self->{'context'},$self->{'layout'});

	$self->{'layout'}->set_text($self->parse_num($note));
	($text_x,$text_y)=$self->{'layout'}->get_pixel_size();
	$self->{'context'}->move_to($self->{'x'}+($self->{'cs_mark'}-$text_x)/2,
			  $self->{'y'});
	Pango::Cairo::show_layout($self->{'context'},$self->{'layout'});

	$self->{'y'}+=$text_y+$self->{'space'};

	$self->{'context'}->move_to($self->{'x'}-$self->{'cs_name'},$self->{'y'});
	$self->{'context'}->line_to($self->{'x'}+$self->{'cs_mark'},$self->{'y'});
	for my $xx ($self->{'x'},
		    $self->{'x'}-$self->{'cs_name'},
		    $self->{'x'}+$self->{'cs_mark'}) {
	    $self->{'context'}->move_to($xx,$self->{'y'});
	    $self->{'context'}->line_to($xx,$y0);
	}
	$self->{'context'}->stroke();
    }

    $self->{'context'}->show_page();
    
}

1;
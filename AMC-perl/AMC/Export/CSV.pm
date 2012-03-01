#
# Copyright (C) 2009-2012 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Export::CSV;

use AMC::Basic;
use AMC::Export;

use Encode;

@ISA=("AMC::Export");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    $self->{'out.encodage'}='utf-8';
    $self->{'out.separateur'}=",";
    $self->{'out.decimal'}=",";
    $self->{'out.entoure'}="\"";
    $self->{'out.ticked'}="";
    $self->{'out.columns'}='sc,student.key,student.name';
    bless ($self, $class);
    return $self;
}

sub load {
  my ($self)=@_;
  $self->SUPER::load();
  $self->{'_capture'}=$self->{'_data'}->module('capture');
}

sub parse_num {
    my ($self,$n)=@_;
    if($self->{'out.decimal'} ne '.') {
	$n =~ s/\./$self->{'out.decimal'}/;
    }
    return($self->parse_string($n));
}

sub parse_string {
    my ($self,$s)=@_;
    if($self->{'out.entoure'}) {
	$s =~ s/$self->{'out.entoure'}/$self->{'out.entoure'}$self->{'out.entoure'}/g;
	$s=$self->{'out.entoure'}.$s.$self->{'out.entoure'};
    }
    return($s);
}

sub export {
    my ($self,$fichier)=@_;
    my $sep=$self->{'out.separateur'};

    $sep="\t" if($sep =~ /^tab$/i);

    $self->pre_process();

    open(OUT,">:encoding(".$self->{'out.encodage'}.")",$fichier);

    $self->{'_scoring'}->begin_read_transaction('XCSV');

    my $dt=$self->{'_scoring'}->variable('darkness_threshold');
    my $lk=$self->{'_assoc'}->variable('key_in_list');

    my @student_columns=split(/,+/,$self->{'out.columns'});

    my @columns=();

    for my $c (@student_columns) {
      if($c eq 'student.key') {
	push @columns,"A:".encode('utf-8',$lk);
      } elsif($c eq 'student.name') {
	push @columns,translate_column_title('nom');
      } elsif($c eq 'student.copy') {
	push @columns,translate_column_title('copie');
      } else {
	push @columns,encode('utf-8',$c);
      }
    }

    push @columns,map { translate_column_title($_); } ("note");

    my @questions=$self->{'_scoring'}->questions;
    my @codes=$self->{'_scoring'}->codes;

    if($self->{'out.ticked'}) {
      push @columns,map { ($_->{'title'},"TICKED:".$_->{'title'}) } @questions;
      $self->{'out.entoure'}="\"" if(!$self->{'out.entoure'});
    } else {
      push @columns,map { $_->{'title'} } @questions;
    }

    push @columns,@codes;

    print OUT join($sep,map  { $self->parse_string($_) } @columns)."\n";

    for my $m (@{$self->{'marks'}}) {
      my @sc=($m->{'student'},$m->{'copy'});

      @columns=();

      for my $c (@student_columns) {
	push @columns,$self->parse_string($m->{$c} ?
					  $m->{$c} :
					  $m->{'student.all'}->{$c});
      }

      push @columns,$self->parse_num($m->{'mark'});

      for my $q (@questions) {
	push @columns,$self->{'_scoring'}->question_score(@sc,$q->{'question'});
	if($self->{'out.ticked'}) {
	  if($self->{'out.ticked'} eq '01') {
	    push @columns,join(';',$self->{'_capture'}
			       ->ticked_list_0(@sc,$q->{'question'},$dt));
	  } elsif($self->{'out.ticked'} eq 'AB') {
	    my $t='';
	    my @tl=$self->{'_capture'}
	      ->ticked_list(@sc,$q->{'question'},$dt);
	    if($self->{'_scoring'}->multiple($m->{'student'},$q->{'question'})) {
	      if(shift @tl) {
		$t.='0';
	      }
	    }
	    for my $i (0..$#tl) {
	      $t.=chr(ord('A')+$i) if($tl[$i]);
	    }
	    push @columns,"\"$t\"";
	  } else {
	    push @columns,'"S?"';
	  }
	}
      }

      for my $c (@codes) {
	push @columns,$self->{'_scoring'}->student_code(@sc,$c);
      }

      print OUT join($sep,@columns)."\n";
    }

    close(OUT);
}

sub name {
  return('CSV');
}

sub options_from_config {
  my ($self,$options_project,$options_main,$options_default)=@_;
  my $enc=$options_project->{"encodage_csv"}
    || $options_main->{"defaut_encodage_csv"}
      || $options_main->{"encodage_csv"}
	|| $options_main->{"defaut_encodage_csv"}
	  || $options_default->{"encodage_csv"}
	    || "UTF-8";
  return("encodage"=>$enc,
	 "columns"=>$options_project->{'export_csv_columns'},
	 "decimal"=>$options_main->{'delimiteur_decimal'},
	 "separateur"=>$options_project->{'export_csv_separateur'},
	 "ticked"=>$options_project->{'export_csv_ticked'},
	);
}

sub options_default {
  return('export_csv_separateur'=>",",
	 'export_csv_ticked'=>'',
	 'export_csv_columns'=>'student.copy,student.key,student.name',
	);
}

sub needs_module {
  return();
}

sub build_config_gui {
  my ($self,$w,$cb)=@_;
  my $t=Gtk2::Table->new(3,2);
  my $widget;
  my $y=0;
  my $renderer;

  $t->attach(Gtk2::Label->new(__"Separator"),
	     0,1,$y,$y+1,["expand","fill"],[],0,0);
  $widget=Gtk2::ComboBox->new_with_model();
  $renderer = Gtk2::CellRendererText->new();
  $widget->pack_start($renderer, TRUE);
  $widget->add_attribute($renderer,'text',COMBO_TEXT);
  $cb->{'export_csv_separateur'}=cb_model("TAB"=>'<TAB>',
					  ";"=>";",
					  ","=>",");
  $w->{'export_c_export_csv_separateur'}=$widget;
  $t->attach($widget,1,2,$y,$y+1,["expand","fill"],[],0,0);
  $y++;

  $t->attach(Gtk2::Label->new(__"Ticked boxes"),0,1,$y,$y+1,["expand","fill"],[],0,0);
  $widget=Gtk2::ComboBox->new_with_model();
  $renderer = Gtk2::CellRendererText->new();
  $widget->pack_start($renderer, TRUE);
  $widget->add_attribute($renderer,'text',COMBO_TEXT);
  $cb->{'export_csv_ticked'}=cb_model(""=>__"No",
				      "01"=>(__"Yes:")." 0;0;1;0",
				      "AB"=>(__"Yes:")." AB",
				     );
  $w->{'export_c_export_csv_ticked'}=$widget;
  $t->attach($widget,1,2,$y,$y+1,["expand","fill"],[],0,0);
  $y++;

  $widget=Gtk2::Button->new_with_label(__"Choose columns");
  $widget->signal_connect(clicked => \&main::choose_columns_current);
  $t->attach($widget,0,2,$y,$y+1,["expand","fill"],[],0,0);
  $y++;

  $t->show_all;
  return($t);
}

sub weight {
  return(.9);
}

1;

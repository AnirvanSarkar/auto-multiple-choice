#
# Copyright (C) 2009-2011 Alexis Bienvenue <paamc@passoire.fr>
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

@ISA=("AMC::Export");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    $self->{'out.encodage'}='utf-8';
    $self->{'out.separateur'}=",";
    $self->{'out.decimal'}=",";
    $self->{'out.entoure'}="\"";
    $self->{'out.cochees'}="";
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

    my @columns=("A:$lk");

    push @columns,map { translate_column_title($_); } ("nom","note","copie");

    my @questions=$self->{'_scoring'}->questions;
    my @codes=$self->{'_scoring'}->codes;

    if($self->{'out.cochees'}) {
      push @columns,map { ($_->{'title'},"TICKED:".$_->{'title'}) } @questions;
      $self->{'out.entoure'}="\"" if(!$self->{'out.entoure'});
    } else {
      push @columns,map { $_->{'title'} } @questions;
    }

    push @columns,@codes;

    print OUT join($sep,map  { $self->parse_string($_) } @columns)."\n";

    for my $m (@{$self->{'marks'}}) {
      my @sc=($m->{'student'},$m->{'copy'});

      @columns=($self->parse_string($m->{'key'}),
		$self->parse_string($m->{'student.name'}),
		$self->parse_num($m->{'mark'}),
		$self->parse_string($m->{'sc'})
		);

      for my $q (@questions) {
	push @columns,$self->{'_scoring'}->question_score(@sc,$q->{'question'});
	if($self->{'out.cochees'}) {
	  push @columns,join(';',$self->{'_capture'}
			     ->ticked_list_0(@sc,$q->{'question'},$dt));
	}
      }

      for my $c (@codes) {
	push @columns,$self->{'_scoring'}->student_code(@sc,$c);
      }

      print OUT join($sep,@columns)."\n";
    }

    close(OUT);
}

1;

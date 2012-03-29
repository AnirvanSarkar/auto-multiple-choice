#
# Copyright (C) 2012 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Export::register::ods;

use AMC::Export::register;
use AMC::Basic;

@ISA=("AMC::Export::register");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    bless ($self, $class);
    return $self;
}

sub name {
  return('OpenOffice');
}

sub extension {
  return('.ods');
}

sub options_from_config {
  my ($self,$options_project,$options_main,$options_default)=@_;
  return("columns"=>$options_project->{'export_ods_columns'},
	 "nom"=>$options_project->{'nom_examen'},
	 "code"=>$options_project->{'code_examen'},
	 );
}

sub options_default {
  return('export_ods_columns'=>'student.copy,student.key,student.name',
	 );
}

sub needs_module {
  return('OpenOffice::OODoc');
}

sub build_config_gui {
  my ($self,$w,$cb)=@_;
  my $b=Gtk2::Button->new_with_label(__"Choose columns");
  $b->signal_connect(clicked => \&main::choose_columns_current);
  return($b);
}

sub weight {
  return(.2);
}

1;

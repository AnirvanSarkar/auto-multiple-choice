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

package AMC::Filter::register::plain;

use AMC::Filter::register;
use AMC::Basic;

@ISA=("AMC::Filter::register");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    bless ($self, $class);
    return $self;
}

sub name {
  return("Plain");
}

sub configure {
  my ($self,$options_project)=@_;
  $options_project->{'moteur_latex_b'}='xelatex';
  $options_project->{'_modifie'}=1;
}

sub file_patterns {
  return("*.txt","*.TXT");
}

sub needs_latex_package {
  return("xltxtra","multicol");
}

sub needs_font {
  return([{'type'=>'fontconfig',
	   'family'=>['Linux Libertine O']},
	 ]);
}

1;

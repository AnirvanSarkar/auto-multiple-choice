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

package AMC::Filter::register::latex;

use AMC::Filter::register;

@ISA=("AMC::Filter::register");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    bless ($self, $class);
    return $self;
}

sub name {
  return("LaTeX");
}

sub weight {
  return(0.1);
}

sub file_patterns {
  return("*.tex","*.TEX");
}

1;

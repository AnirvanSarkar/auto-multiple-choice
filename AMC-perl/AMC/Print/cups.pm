#
# Copyright (C) 2015 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Print::cups;

use AMC::Print;
use AMC::Basic;

use Module::Load;
use Module::Load::Conditional qw/check_install/;

@ISA=("AMC::Print");

sub nonnul {
    my $s=shift;
    $s =~ s/\000//g;
    return($s);
}

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);

  my @manque=();

  for my $m ("Net::CUPS","Net::CUPS::PPD") {
    if(check_install(module=>$m)) {
      load($m);
    } else {
      push @manque,$m;
    }
  }

  if(@manque) {
    die "Needs Net::CUPS and Net::CUPS::PPD perl modules for CUPS printing";
  } else {
    debug_pm_version("Net::CUPS");
    $self->{cups}=Net::CUPS->new();
  }

  $self->{method}='cups';
  return($self);
}

sub check_available {
  my @manque=();

  for my $m ("Net::CUPS","Net::CUPS::PPD") {
    if(!check_install(module=>$m)) {
      push @manque,$m;
    }
  }

  if(@manque) {
    return(sprintf(__("Perl module(s) missing: %s"),join(' ',@manque)));
  } else {
    return();
  }
}

sub weight {
  return(1.0);
}

sub printers_list {
  my ($self)=@_;
  return(map { {name=>$_->getName(),
		  description=>$_->getDescription()||$_->getName()} }
	 ($self->{cups}->getDestinations()));
}

sub default_printer {
  my ($self)=@_;
  return($self->{cups}->getDestination()->getName());
}

sub printer_selected_options {
  my ($self,$printer)=@_;
  my @o=();
  my $ppd=$self->{cups}->getPPD($printer);
  for my $k (split(/\s+/,$self->{useful_options})) {
    my $option=$ppd->getOption($k);
    if(%$option) {
      push @o,{name=>$k,
	       description=>nonnul($option->{'text'}),
	       default=>nonnul($option->{'defchoice'}),
	       values=>[map { {name=>nonnul($_->{choice}),
				 description=>nonnul($_->{text}) } }
			(@{$option->{choices}})],
	      }
    }
  }
  return(@o);
}

# PRINTING

sub select_printer {
  my ($self,$printer)=@_;
  $self->{dest}=$self->{cups}->getDestination($printer);
}

sub set_option {
  my ($self,$option,$value)=@_;
  $self->{dest}->addOption($option,$value);
}

sub print_file {
  my ($self,$filename,$label)=@_;
  $self->{dest}->printFile($filename,$label);
}

1;

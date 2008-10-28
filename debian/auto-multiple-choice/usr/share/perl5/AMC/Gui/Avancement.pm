#
# Copyright (C) 2008 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3 of
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

package AMC::Gui::Avancement;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw();
}

sub new {
    my ($niveau,%o)=(@_);
    my $self={'niveau'=>$niveau,
	      'debug'=>0,
	      'etat'=>[],
	  };
 
    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;
    print "===<".$self->{'niveau'}.">=z0\n" if($self->{'niveau'}>0);
    $|++ if($niveau>0);
    return($self);
}

sub init {
    my ($self)=(@_);
    $self->{'etat'}=[];
}

sub progres {
    my ($self,$suite)=(@_);
    print "===<".$self->{'niveau'}.">=+$suite\n" if($self->{'niveau'}>0);
}

sub progres_abs {
    my ($self,$suite)=(@_);
    print "===<".$self->{'niveau'}.">==$suite\n" if($self->{'niveau'}>0);
}

sub fin {
    my ($self,$suite)=(@_);
    $self->progres_abs(1);
}    

sub lit {
    my ($self,$s)=(@_);
    my $r=0;
    my $niv=0;
    if($s =~ /===<([0-9]+)>=([+=z])([0-9.]+)/) {
	my $type;
	my $suite;
	($niv,$type,$suite)=($1,$2,$3);
	$self->{'etat'}->[$niv]->[0]
	    =$self->{'etat'}->[$niv]->[1];
	if($type eq '+') {
	    $self->{'etat'}->[$niv]->[1] += $suite;
	} elsif($type eq 'z') {
	    $self->{'etat'}->[$niv]=[0,0];
	} else {
	    $self->{'etat'}->[$niv]->[1] = $suite; 
	}
	my $x=1;
	print "AV:pile" if($self->{'debug'});
	for my $i (1..$niv) {
	    print " [".join(',',@{$self->{'etat'}->[$i]})."]" if($self->{'debug'});
	    $r+=$x * $self->{'etat'}->[$i]->[0];
	    $x*=($self->{'etat'}->[$i]->[1]-$self->{'etat'}->[$i]->[0]);
	}
	print " -> $r\n" if($self->{'debug'});
	$r=0 if($r<0);
	$r=1 if($r>1);
    }
    return(wantarray ? ($r,$niv) : $r);
}

1;

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

package AMC::MEPList;

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

use AMC::Basic;
use XML::Simple;

sub new {
    my ($mep,%o)=(@_);

    my $self={'mep'=>$mep,
	      'id'=>'',
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;

    my @xmls;
    
    if(-d $mep) {
	#####
	# rechercher toutes les possibilites de mise en page :
	opendir(DIR, $mep) 
	    || die "Erreur a l'ouverture du repertoire $mep : $!";
	@xmls = map { "$mep/$_"; } 
	grep { /\.xml$/ && -f "$mep/$_" } readdir(DIR);
	closedir DIR;
    } else {
	@xmls=($mep);
    }

    my %mep_dispos=();
    
    for my $f (@xmls) {
	my $lay=XMLin($f,ForceArray => 1,KeepRoot => 1, KeyAttr=> [ 'id' ]);
	if($lay->{'mep'}) {
	    for my $laymep (keys %{$lay->{'mep'}}) {
		if($self->{'id'} eq '' ||
		   $laymep =~ /^\+$self->{'id'}\//) {
		    if($mep_dispos{$laymep}) {
			attention("ATTENTION : identifiant multiple : $laymep");
		    }
		    $mep_dispos{$laymep}={
			'filename'=>$f,
			map { $_=>$lay->{'mep'}->{$laymep}->{$_} } qw/page src/,
		    };
		}
	    }
	}
    }
    
    my @kmep=(keys %mep_dispos);
    
    $self->{'dispos'}=\%mep_dispos;
    $self->{'au-hasard'}=$kmep[0];
    $self->{'n'}=1+$#kmep;
    
    return($self);
}

sub nombre {
    my ($self)=(@_);
    
    return($self->{'n'});
}

sub attr {
    my ($self,$id,$a)=(@_);
    $id=$self->{'au-hasard'} if(!$id);
    return($self->{'dispos'}->{$id}->{$a});
}

sub filename {
    my ($self,$id)=(@_);
    return($self->attr($id,'filename'));
}

sub mep {
    my ($self,$id)=(@_);

    $id=$self->{'au-hasard'} if(!$id);
    
    if($self->{'dispos'}->{$id}->{'filename'}) {
	return(XMLin($self->{'dispos'}->{$id}->{'filename'},
		     ForceArray => 1,
		     KeyAttr=> [ 'id' ]));
    } else {
	return(undef);
    }
}

sub ids {
    my ($self)=(@_);

    return(sort { id_triable($a) cmp id_triable($b) }
	   (keys %{$self->{'dispos'}}));
}

sub pages_etudiant {
    my ($self,$etu)=@_;
    my @r=();
    for my $i ($self->ids()) {
	my ($e,$p)=get_ep($i);
	push @r,$self->attr($i,'page') if($e == $etu);
    }
    return(@r);
}

1;

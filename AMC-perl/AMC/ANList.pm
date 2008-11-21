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

package AMC::ANList;

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

use XML::Simple;
use AMC::Basic;

# perl -e 'use AMC::ANList; use Data::Dumper; print Dumper(AMC::ANList::new("points-cr","debug",1)->analyse());'

sub new {
    my ($cr,%o)=(@_);

    my $self={'cr'=>$cr,
	      'debug'=>0,
	      'action'=>'',
	      'timestamp'=>0,
	      'dispos'=>{},
	      'new_vide'=>'',
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;

    $self->maj() if(!$self->{'new_vide'});

    return($self);
}

sub maj {
    my ($self)=@_;

    my $an_dispos=$self->{'dispos'};
    my @ids_modifies=();
    my @xmls;
    
    if(-d $self->{'cr'}) {
	opendir(DIR, $self->{'cr'}) || die "can't opendir ".$self->{'cr'}.": $!";
	@xmls = grep { @st=stat($_); 
		       /\.xml$/ && -f $_ && $st[9]>$self->{'timestamp'} } 
	map { $self->{'cr'}."/$_" } readdir(DIR);
	closedir DIR;
    } else {
	@xmls=($self->{'cr'});
    }

  XMLF: for my $xf (@xmls) {
      my $x=XMLin("$xf",ForceArray => 1,KeepRoot=>1,KeyAttr=> [ 'id' ]);
      print "Fichier $xf...\n" if($self->{'debug'});

      next XMLF if(!$x->{'analyse'});

      my @ids=(keys %{$x->{'analyse'}});
    BID:for my $id (@ids) {
	print "ID=$id\n" if($self->{'debug'});

	$an_dispos->{$id}={} if(!$an_dispos->{$id});

	my $mm=$x->{'analyse'}->{$id}->{'manuel'};
	$mm=0 if(!defined($mm));
	
	if($an_dispos->{$id}->{'fichier'}) {
	    if($an_dispos->{$id}->{'manuel'} == $mm
	       && $an_dispos->{$id}->{'fichier'} ne $xf) {
		die "Plusieurs fichiers differents pour la page $id ("
		    .$an_dispos->{$id}->{'fichier'}.", "
		    .$xf.")";
	    }
	    next BID if($an_dispos->{$id}->{'manuel'} && ! $mm);
	}
	
	$an_dispos->{$id}={'fichier'=>"$xf",
			   'manuel'=>$mm,
			   'nometudiant'=>$x->{'analyse'}->{$id}->{'nometudiant'},
		      };
	
	push @ids_modifies,$id;

	my @st=stat($xf);
	$self->{'timestamp'}=$st[9] if($st[9]>$self->{'timestamp'});

	if($self->{'action'}) {
	    my @args=@{$self->{'action'}};
	    my $cmd=shift @args;
	    &$cmd($id,$x->{'analyse'}->{$id},@args);
	}
    }
  }

    my @kan=(keys %$an_dispos);
    
    $self->{'au-hasard'}=$kan[0];
    $self->{'n'}=1+$#kan;
    
    return(@ids_modifies);
}

sub nombre {
    my ($self)=(@_);
    
    return($self->{'n'});
}

sub attribut {
    my ($self,$id,$att)=(@_);

    $id=$self->{'au-hasard'} if(!$id);
    
    return($self->{'dispos'}->{$id}->{$att});
}

sub filename {
    my ($self,$id)=(@_);
    return $self->attribut($id,'fichier');
}

sub analyse {
    my ($self,$id)=(@_);

    $id=$self->{'au-hasard'} if(!$id);
    
    if($self->{'dispos'}->{$id}->{'fichier'}) {
	return(XMLin($self->{'dispos'}->{$id}->{'fichier'},
		    ForceArray => [ 'chiffre' ],
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

1;

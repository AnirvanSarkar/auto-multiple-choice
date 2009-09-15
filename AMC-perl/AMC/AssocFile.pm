#
# Copyright (C) 2009 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::AssocFile;

use IO::File;
use XML::Simple;
use Data::Dumper;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw();
}

my $VERSION=1;

my %type_ok=('auto'=>1,
	     'manuel'=>1);

sub new {
    my ($f,%o)=@_;
    my $self={'file'=>$f,
	      'a'=>{'copie'=>{},
		    'liste_key'=>'', # cle dans la liste de noms utilisee pour identifier les noms
		    'notes_id'=>'', # code d'identification auto
		    'version'=>$VERSION,
		},
	      'maj'=>0,
	      'encodage'=>'utf-8',
	      'debug'=>''};

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
	$self->{'a'}->{$_}=$o{$_} if(defined($self->{'a'}->{$_}));
    }

    bless $self;
    return($self);
}

sub load {
    my $self=shift;
    my $a='';
    
    if(-s $self->{'file'}) {
	my $i=IO::File->new($self->{'file'},"<:encoding(".$self->{'encodage'}.")");
	$a=XMLin($i,'ForceArray'=>1,'KeyAttr'=>['id']);
	if(ref($a->{'copie'}) ne 'HASH') {
	    $a->{'copie'}={};
	}
	$i->close();
    }

    my $ok=1;
    for (qw/version liste_key notes_id/) {
	if($self->{'a'}->{$_} && ($self->{'a'}->{$_} ne $a->{$_})) {
	    print "*** fichier d'associations incompatible : $_\n";
	    $ok=0;
	}
    }
    if($ok) {
	$self->{'a'}=$a;
	$self->{'maj'}=0;
    }
    return($ok);
}

sub save {
    my $self=shift;

    my $i=IO::File->new($self->{'file'},">:encoding(".$self->{'encodage'}.")");
    XMLout($self->{'a'},
	   'OutputFile'=>$i,'RootName'=>'association',
	   'XMLDecl'=>'<?xml version="1.0" encoding="'.$self->{'encodage'}.'" standalone="yes"?>',
	   'KeyAttr'=>['id']);
    $i->close();
}

sub print {
    my $self=shift;

    print Dumper($self->{'a'});
}

sub get {
    my ($self,$type,$copie)=@_;
    die "mauvais type : $type" if(!$type_ok{$type});
    return($self->{'a'}->{'copie'}->{$copie}->{$type});
}

sub effectif {
    my ($self,$copie)=@_;
    my $e=$self->{'a'}->{'copie'}->{$copie};
    my $v=($e->{'manuel'} ? $e->{'manuel'} : $e->{'auto'});
    return($v && ($v eq 'NONE') ? '' : $v );
}

sub maj { # actualisation des donnees induites
    my ($self)=@_;
    if(!$self->{'maj'}) {
	# liste des codes associes avec nb de sources
	$self->{'dest'}={};
	for($self->ids()) {
	    # print STDERR "$_ -> ".$self->effectif($_)."\n";
	    push @{$self->{'dest'}->{$self->effectif($_)}},$_;
	}

	$self->{'maj'}=1;
    }
}

sub inverse {
    my ($self,$id)=@_;
    $self->maj();
    if($self->{'dest'}->{$id}) {
	return(@{$self->{'dest'}->{$id}});
    } else {
	#print STDERR Dumper($self->{'dest'});
	return();
    }
}

sub etat { # 0: aucune assoc 1: une assoc valide 2: une assoc multiple
    my ($self,$copie)=@_;
    $self->maj();
    my $d=$self->effectif($copie);
    if($d) {
	return($self->{'dest'}->{$d} == 1 ? 1 : 2);
    } else {
	return(0);
    }
}

sub set {
    my ($self,$type,$copie,$valeur)=@_;
    die "mauvais type : $type" if(!$type_ok{$type});
    $self->{'a'}->{'copie'}->{$copie}->{$type}=$valeur;
    $self->{'maj'}=0;
}

sub ids {
    my ($self)=@_;

    return(keys %{$self->{'a'}->{'copie'}});
}

sub clear {
    my ($self,$type)=@_;
    die "mauvais type : $type" if(!$type_ok{$type});
    
    for my $i ($self->ids()) {
	delete($self->{'a'}->{'copie'}->{$i}->{$type});
	$self->{'maj'}=0;
    }
}

1;


__END__

perl -e 'use AMC::AssocFile;$a=AMC::AssocFile::new("/tmp/a.xml","liste_key"=>"etu","notes_id"=>"id");$a->set("manuel",100,12345);$a->set("auto",100,12346);$a->set("manuel",101,99);$a->print();$a->save();'
perl -e 'use AMC::AssocFile;$a=AMC::AssocFile::new("/tmp/a.xml");$a->load();$a->print();$a->clear("auto");$a->print();'

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
use Storable;

# perl -e 'use AMC::ANList; use Data::Dumper; print Dumper(AMC::ANList::new("points-cr","debug",1)->analyse());'

%an_defaut=('debug'=>0,
	    'action'=>'',
	    'timestamp'=>0,
	    'dispos'=>{},
	    'saved'=>'',
	    );

sub new {
    my ($cr,%o)=(@_);
    my $self;

    if($o{'saved'} && -f $o{'saved'}) {

	$self=load_an($o{'saved'});
	if(!$self) {
	    print "Load(ANList)->erreur\n";
	}
	
    } 

    if(!$self) {

	$self={};
	bless $self;
	
    }

    $self->{'cr'}=$cr;

    for (keys %an_defaut) {
	$self->{$_}=$an_defaut{$_} if(! defined($self->{$_}));
    }
    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    $self->maj();

    return($self);
}

sub maj {
    my ($self)=@_;

    my $an_dispos=$self->{'dispos'};
    my @ids_effaces=();
    my @ids_modifies=();
    my @xmls;

    # on enleve les entrees qui n'existent plus...

    for my $i (keys %$an_dispos) {
	if((! $an_dispos->{$i}->{'fichier'})
	   || (! -f $an_dispos->{$i}->{'fichier'})) {
	    print STDERR "AN : entree $i effacee\n";
	    push @ids_effaces,$i;
	    delete($an_dispos->{$i});
	}
    }

    # on detecte les nouveau fichiers...
    
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
	    if($an_dispos->{$id}->{'manuel'} && ! $mm) {
		$an_dispos->{$id}->{'fichier-scan'}=$xf,
		next BID;
	    }
	}
	
	my $f_scan='';
	$f_scan=$an_dispos->{$id}->{'fichier'} 
	if(! $an_dispos->{$id}->{'manuel'});

	$an_dispos->{$id}={'fichier'=>$xf,
			   'manuel'=>$mm,
			   'nometudiant'=>$x->{'analyse'}->{$id}->{'nometudiant'},
			   'fichier-scan'=>$f_scan,
		      };
	
	push @ids_modifies,$id;

	my @st=stat($xf);
	$self->{'timestamp'}=$st[9] if($st[9]>$self->{'timestamp'});

	if($self->{'action'}) {
	    my @args=@{$self->{'action'}};
	    my $cmd=shift @args;
	    &$cmd($id,$x->{'analyse'}->{$id},@args) if(ref($cmd) eq 'CODE');
	}
    }
  }

    my @kan=(keys %$an_dispos);
    
    $self->{'au-hasard'}=$kan[0];
    $self->{'n'}=1+$#kan;

    $self->save() if($#ids_modifies>=0 || $#ids_effaces>=0);
    
    return(@ids_modifies);
}

sub nombre {
    my ($self)=(@_);
    
    return($self->{'n'});
}

sub attribut {
    my ($self,$id,$att)=(@_);

    $id=$self->{'au-hasard'} if(!$id);
    
    # pour ne pas creer artificiellement l'entree $id :
    return(defined($self->{'dispos'}->{$id}) ?
	   $self->{'dispos'}->{$id}->{$att} : undef);
}

sub filename {
    my ($self,$id)=(@_);
    return $self->attribut($id,'fichier');
}

sub analyse {
    my ($self,$id,%oo)=(@_);

    my $key='fichier';
    if($oo{'scan'}) {
	$key='fichier-scan' 
	    if(-f $self->{'dispos'}->{$id}->{'fichier-scan'});
    }

    $id=$self->{'au-hasard'} if(!$id);
    
    if(-f $self->{'dispos'}->{$id}->{$key}) {
	return(XMLin($self->{'dispos'}->{$id}->{$key},
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

sub save {
    my ($self,$file)=@_;
    if(!$file) {
	$file=$self->{'saved'};
    }
    return() if(!$file);
    store(\$self,$file);
}

sub load_an {
    my ($file)=@_;
    my $d;
    eval{$d=retrieve($file)};
    return($d ? $$d : undef);
}

1;

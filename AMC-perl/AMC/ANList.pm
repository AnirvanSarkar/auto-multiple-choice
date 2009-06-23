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

my $VERSION=2;

# perl -e 'use AMC::ANList; use Data::Dumper; print Dumper(AMC::ANList::new("points-cr","debug",1)->analyse());'

# perl -e 'use XML::Simple;use Data::Dumper;  print Dumper(XMLin("",ForceArray => ["analyse","chiffre","case","id"],KeepRoot=>1,KeyAttr=> ["id"]));' |less

%an_defaut=('debug'=>0,
	    'action'=>'',
	    'timestamp'=>0,
	    'dispos'=>{},
	    'saved'=>'',
	    'version'=>$VERSION,
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

    $self->maj() if(!$o{'brut'});

    return($self);
}

sub maj {
    my ($self,%oo)=@_;

    my $an_dispos=$self->{'dispos'};
    my @ids_effaces=();
    my @ids_modifies=();
    my @xmls;

    my %a_retraiter=();

    # on enleve les entrees qui n'existent plus...

    for my $i (keys %$an_dispos) {
	if((! $an_dispos->{$i}->{'fichier'})
	   || (! -f $an_dispos->{$i}->{'fichier'})
	   || ($an_dispos->{$i}->{'fichier-scan'} && ! -f $an_dispos->{$i}->{'fichier-scan'})
	   ) {
	    $a_retraiter{$an_dispos->{$i}->{'fichier'}}=1
		if($an_dispos->{$i}->{'fichier'});
	    $a_retraiter{$an_dispos->{$i}->{'fichier-scan'}}=1
		if($an_dispos->{$i}->{'fichier-scan'});
	    print STDERR "AN : entree $i a retraiter\n";
	    push @ids_effaces,$i;
	    delete($an_dispos->{$i});
	}
    }

    # on detecte les nouveau fichiers...
    
    if(-d $self->{'cr'}) {
	opendir(DIR, $self->{'cr'}) || die "can't opendir ".$self->{'cr'}.": $!";
	@xmls = grep { @st=stat($_); 
		       /\.xml$/ && -f $_ 
			   && ($st[9]>$self->{'timestamp'} 
			       || $a_retraiter{$_} )} 
	map { $self->{'cr'}."/$_" } readdir(DIR);
	closedir DIR;
    } else {
	@xmls=($self->{'cr'});
    }

  XMLF: for my $xf (@xmls) {
      &{$oo{'progres'}}() if($oo{'progres'});
      my $x=XMLin("$xf",
		  ForceArray => ["analyse","chiffre","case","id"],
		  KeepRoot=>1,
		  KeyAttr=> [ 'id' ]);
      print "Fichier $xf...\n" if($self->{'debug'});

      next XMLF if(!$x->{'analyse'});

      my @ids=(keys %{$x->{'analyse'}});
    BID:for my $id (@ids) {
	print "ID=$id\n" if($self->{'debug'});

	$an_dispos->{$id}={'manuel'=>0} if(!$an_dispos->{$id});

	my $mm=$x->{'analyse'}->{$id}->{'manuel'};
	$mm=0 if(!defined($mm));
	
	# un autre fichier donnait deja des infos pour cet ID
	if($an_dispos->{$id}->{'fichier'}) {
	    if($an_dispos->{$id}->{'manuel'} == $mm
	       && $an_dispos->{$id}->{'fichier'} ne $xf) {
		# avec la meme valeur de <manuel> : ca doit etre une erreur
		die "Plusieurs fichiers differents pour la page $id ("
		    .$an_dispos->{$id}->{'fichier'}.", "
		    .$xf.")";
	    }
	}
	

	if($mm) { # manuel
	    $an_dispos->{$id}->{'fichier'}=$xf;
	    $an_dispos->{$id}->{'manuel'}=1;
	} else { # auto
	    $an_dispos->{$id}->{'fichier-scan'}=$xf;
	    $an_dispos->{$id}->{'fichier'}=$xf if(!$an_dispos->{$id}->{'fichier'});
	    $an_dispos->{$id}->{'r'}=[map { $x->{'analyse'}->{$id}->{'case'}->{$_}->{'r'} } (keys %{$x->{'analyse'}->{$id}->{'case'}})] if($x->{'analyse'}->{$id}->{'case'});
	}

	$an_dispos->{$id}->{'nometudiant'}=$x->{'analyse'}->{$id}->{'nometudiant'};
	if($x->{'analyse'}->{$id}->{'transformation'}) {
	    $an_dispos->{$id}->{'mse'}=$x->{'analyse'}->{$id}->{'transformation'}->{'mse'};
	}

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

sub mse_string {
    my ($self,$id,$seuil_mse,$couleur)=(@_);
    my $man=$self->attribut($id,'manuel');
    my $mse=$self->attribut($id,'mse');
    my $st=(defined($mse)? 
	    sprintf($man ? "(%.01f)" : "%.01f",$mse) : "---");
    return(wantarray ?
	   ($st,defined($mse) && $mse>$seuil_mse ? $couleur:undef)
	   : $st);
}

sub sensibilite {
    my ($self,$id,$seuil)=(@_);
    my $r=$self->attribut($id,'r');
    my $deltamin=1;
    if($r) {
	for my $c (@$r) {
	    my $d=abs($seuil-$c);
	    $deltamin=$d if($d<$deltamin);
	}
	return($deltamin<$seuil ? 10*($seuil-$deltamin)/$seuil : 0);
    } else {
	return(undef);
    }
}

sub sensibilite_string {
    my ($self,$id,$seuil,$seuil_sens,$couleur)=(@_);
    my $man=$self->attribut($id,'manuel');
    my $s=$self->sensibilite($id,$seuil);
    my $st=(defined($s) ? 
	    sprintf($man ? "(%.01f)" : "%.01f",$s) : "---");
    return(wantarray ?
	   ($st,defined($s) && $s>$seuil_sens ? $couleur:undef)
	   : $st);
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
	    if($self->{'dispos'}->{$id}->{'fichier-scan'} 
	       && -f $self->{'dispos'}->{$id}->{'fichier-scan'});
    }

    $id=$self->{'au-hasard'} if(!$id);
    
    if($self->{'dispos'}->{$id}->{$key} 
       && -f $self->{'dispos'}->{$id}->{$key}) {
	return(XMLin($self->{'dispos'}->{$id}->{$key},
		    ForceArray => [ 'analyse','chiffre','case','id' ],
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
    if($d) {
	my $v=$$d->{'version'};
	$v=0 if(!defined($v));
	if($v < $VERSION ) {
	    print STDERR "Version de fichier ANList perimee : $v < $VERSION\n";
	    $d='';
	}
    }
    return($d ? $$d : undef);
}

1;

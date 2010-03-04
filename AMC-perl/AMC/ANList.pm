#
# Copyright (C) 2008-2010 Alexis Bienvenue <paamc@passoire.fr>
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

use XML::Simple;
use AMC::Basic;
use Storable;

my $VERSION=4;

%an_defaut=('action'=>'',
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
	    debug "Load(ANList)->error\n";
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
	   || (! -s $self->{'cr'}."/".$an_dispos->{$i}->{'fichier'})
	   || ($an_dispos->{$i}->{'fichier-scan'} && 
	       ! -f $self->{'cr'}."/".$an_dispos->{$i}->{'fichier-scan'})
	   ) {
	    if($an_dispos->{$i}->{'fichier'}) {
		$a_retraiter{$an_dispos->{$i}->{'fichier'}}=1;
		debug "File ".$an_dispos->{$i}->{'fichier'}. " to be updated";
	    }
	    if($an_dispos->{$i}->{'fichier-scan'}) {
		$a_retraiter{$an_dispos->{$i}->{'fichier-scan'}}=1;
		debug "File ".$an_dispos->{$i}->{'fichier-scan'}. " to be updated";
	    }
		
	    debug "AN : entree $i effacee\n";
	    push @ids_effaces,$i;
	    delete($an_dispos->{$i});
	}
    }

    # on detecte les nouveau fichiers...
    
    if(-d $self->{'cr'}) {

	debug "Timestamp : ".$self->{'timestamp'};

	opendir(DIR, $self->{'cr'}) || die "can't opendir ".$self->{'cr'}.": $!";
	@xmls = grep { @st=stat($self->{'cr'}."/".$_); 
		       debug $st[9]." : ".$_;
		       /\.xml$/ && -s $self->{'cr'}."/".$_ 
			   && ($st[9]>$self->{'timestamp'} 
			       || $a_retraiter{$_} )} 
	readdir(DIR);
	closedir DIR;
    } else {
	@xmls=($self->{'cr'});
    }

  XMLF: for my $xf (@xmls) {
      &{$oo{'progres'}}() if($oo{'progres'});

      debug "Looking at $xf for ANList...";

      my $x=XMLin($self->{'cr'}."/".$xf,
		  ForceArray => ["analyse","chiffre","case","id"],
		  KeepRoot=>1,
		  KeyAttr=> [ 'id' ]);

      next XMLF if(!$x->{'analyse'});

      my @ids=(keys %{$x->{'analyse'}});
    BID:for my $id (@ids) {
	debug "ID=$id";

	$an_dispos->{$id}={'manuel'=>0} if(!$an_dispos->{$id});

	my $mm=$x->{'analyse'}->{$id}->{'manuel'};
	$mm=0 if(!defined($mm));
	
	# un autre fichier donnait deja des infos pour cet ID
	if($an_dispos->{$id}->{'fichier'}) {
	    if($an_dispos->{$id}->{'manuel'} == $mm
	       && $an_dispos->{$id}->{'fichier'} ne $xf) {
		# avec la meme valeur de <manuel> : ca doit etre une erreur
		die "Different files for page $id ("
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

	$an_dispos->{$id}->{'src'}=$x->{'analyse'}->{$id}->{'src'};

	push @ids_modifies,$id;

	my @st=stat($self->{'cr'}."/".$xf);
	$self->{'timestamp'}=$st[9] if($st[9]>$self->{'timestamp'});

	if($self->{'action'}) {
	    my @args=@{$self->{'action'}};
	    my $cmd=shift @args;
	    &$cmd($id,$x->{'analyse'}->{$id},@args) if(ref($cmd) eq 'CODE');
	}
    }
  }

    debug "New timestamp : ".$self->{'timestamp'};

    my @kan=(keys %$an_dispos);
    
    $self->{'au-hasard'}=$kan[0];
    $self->{'n'}=1+$#kan;

    $self->save() if($#ids_modifies>=0 || $#ids_effaces>=0);
    
    push @ids_modifies,@ids_effaces if($oo{'effaces'});

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
    if(defined($self->{'dispos'}->{$id})) {
	my $v=$self->{'dispos'}->{$id}->{$att};
	$v=$self->{'cr'}."/".$v 
	    if($att eq 'fichier' || $att eq 'fichier-scan');
	return($v);
    } else {
	return(undef);
    }
}

sub existe {
    my ($self,$id)=(@_);
    return(defined($self->{'dispos'}->{$id}) &&
	   keys(%{$self->{'dispos'}->{$id}}));
}

sub mse_string {
    my ($self,$id,$seuil_mse,$couleur)=(@_);
    my $man=$self->attribut($id,'manuel');
    my $mse=$self->attribut($id,'mse');
    my $st=(defined($mse)? 
	    sprintf($man ? "(%.01f)" : "%.01f",$mse) : "---");
    return(wantarray ?
	   ($st,defined($mse) && $mse>$seuil_mse && (!$man) ? $couleur:undef)
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
	   ($st,defined($s) && $s>$seuil_sens && (!$man) ? $couleur:undef)
	   : $st);
}

sub filename {
    my ($self,$id)=(@_);
    return $self->attribut($id,'fichier');
}

sub couleur {
    my ($self,$id)=(@_);
    my $id_coul=undef;
    if($self->attribut($id,'fichier')) {
	$id_coul=($self->attribut($id,'manuel') ?
		  'lightgreen' : 'lightblue');
    }
    return($id_coul);
}

sub analyse {
    my ($self,$id,%oo)=(@_);

    $id=$self->{'au-hasard'} if(!$id);

    return(undef) if(!$self->existe($id));
    
    my $key='fichier';
    if($oo{'scan'}) {
	$key='fichier-scan' 
	    if($self->{'dispos'}->{$id}->{'fichier-scan'} 
	       && -f $self->{'cr'}."/".$self->{'dispos'}->{$id}->{'fichier-scan'});
    }

    if($self->{'dispos'}->{$id}->{$key} 
       && -f $self->{'cr'}."/".$self->{'dispos'}->{$id}->{$key}) {
	return(XMLin($self->{'cr'}."/".$self->{'dispos'}->{$id}->{$key},
		     ForceArray => [ 'analyse','chiffre','case','id' ],
		     KeyAttr=> [ 'id' ]));
    } else {
	return(undef);
    }
}

sub ids {
    my ($self)=(@_);

    return(sort { id_triable($a) cmp id_triable($b) }
	   grep { $self->existe($_) }
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
	    debug "Old ANList version: $v < $VERSION";
	    $d='';
	}
    }
    return($d ? $$d : undef);
}

1;

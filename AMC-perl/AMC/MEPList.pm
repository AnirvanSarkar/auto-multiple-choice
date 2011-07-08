#
# Copyright (C) 2008-2010 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::MEPList;

use AMC::Basic;
use XML::Simple;
use Storable;

my $VERSION=3;

my %mep_defaut=('id'=>'',
		'saved'=>'',
		'timestamp'=>0,
		'version'=>$VERSION,
		);

sub new {
    my ($mep,%o)=(@_);
    my $self='';
    my $renew=1;

    if($o{'saved'} && -f $o{'saved'}) {

	$self=load_mep($o{'saved'});
	if($self) {
	    $renew=0;
	} else {
	    debug "Load(MEPList)->error\n";
	}
	
    }

    if(!$self) {
	
	$self={};
	bless $self;

    }

    $self->{'mep'}=$mep if($mep && -d $mep);
    
    for (keys %mep_defaut) {
	$self->{$_}=$mep_defaut{$_} if(! defined($self->{$_}));
    }
    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }
    
    $self->maj() if(!$o{'brut'});

    return($self);
}

sub maj {
    my ($self,%oo)=@_;
    my @ie=();

    # enleve les fichiers qui n'existent plus...
    
    for my $i (keys %{$self->{'dispos'}}) {
	if((! $self->{'dispos'}->{$i}->{'filename'})
	   || (! -s $self->{'mep'}."/".$self->{'dispos'}->{$i}->{'filename'})) {
	    debug "MEP : removed entry $i (file $self->{'dispos'}->{$i}->{'filename'} in $self->{'mep'})\n";
	    push @ie,$i;
	    delete($self->{'dispos'}->{$i});
	}
    }
    
    # va voir ceux qui sont apparu...

    my @xmls=();

    if(-d $self->{'mep'}) {
	opendir(DIR, $self->{'mep'}) || die "can't opendir ".$self->{'mep'}.": $!";
	@xmls = grep { @st=stat($self->{'mep'}."/".$_); 
		       /\.xml$/ && -s $self->{'mep'}."/".$_ 
			   && $st[9]>$self->{'timestamp'} } 
	readdir(DIR);
	closedir DIR;
    }

    # va analyser chacun de ces fichiers ...

    for my $f (@xmls) {
	&{$oo{'progres'}}() if($oo{'progres'});
	
	my $lay=XMLin($self->{'mep'}."/".$f,
		      ForceArray => 1,KeepRoot => 1, KeyAttr=> [ 'id' ]);

	my @st=stat($self->{'mep'}."/".$f);
	$self->{'timestamp'}=$st[9] if($st[9]>$self->{'timestamp'});

	if($lay->{'mep'}) {
	    for my $laymep (keys %{$lay->{'mep'}}) {
		if($self->{'id'} eq '' ||
		   $laymep =~ /^\+$self->{'id'}\//) {
		    if($self->{'dispos'}->{$laymep}) {
			# deja en stock :
			if($self->{'dispos'}->{$laymep}->{'filename'} eq $f) {
			    # cas (1) meme fichier, sans doute mis a jour
			    debug "MEP update: $laymep";
			} else {
			    # cas (2) autre fichier...
			    attention("WARNING: multiple ID $laymep");
			}
		    }
		    $self->{'dispos'}->{$laymep}={
			'filename'=>$f,
			'case'=>($lay->{'mep'}->{$laymep}->{'case'} ? 1:0),
			'nom'=>($lay->{'mep'}->{$laymep}->{'nom'} ? 1:0),
			map { $_=>$lay->{'mep'}->{$laymep}->{$_} } qw/page src/,
		    };
		    push @ie,$laymep;
		}
	    }
	}
    }
    
    my @kmep=(keys %{$self->{'dispos'}});
    
    $self->{'au-hasard'}=$kmep[0];
    $self->{'n'}=1+$#kmep;


    $self->save() if($#ie>=0);
}

sub save {
    my ($self,$file)=@_;
    if(!$file) {
	$file=$self->{'saved'};
    }
    return() if(!$file);
    store(\$self,$file);
}

sub load_mep {
    my ($file)=@_;
    my $d;
    eval{$d=retrieve($file)};
    if($d) {
	my $v=$$d->{'version'};
	$v=0 if(!defined($v));
	if($v < $VERSION ) {
	    debug "Old MEPList version: $v < $VERSION";
	    $d='';
	}
    }
    return($d ? $$d : undef);
}

sub nombre {
    my ($self)=(@_);
    
    return($self->{'n'});
}

sub attr {
    my ($self,$id,$a)=(@_);
    $id=$self->{'au-hasard'} if(!$id);
    return(undef) if(!defined($self->{'dispos'}->{$id}));
    my $v=$self->{'dispos'}->{$id}->{$a};
    $v=$self->{'mep'}."/".$v if($a eq 'filename');
    return($v);
}

sub filename {
    my ($self,$id)=(@_);
    return($self->attr($id,'filename'));
}

sub mep {
    my ($self,$id)=(@_);

    $id=$self->{'au-hasard'} if(!$id);
    return(undef) if(!defined($self->{'dispos'}->{$id}));
    
    if($self->{'dispos'}->{$id}->{'filename'}
       && -f $self->{'mep'}."/".$self->{'dispos'}->{$id}->{'filename'}) {
	return(XMLin($self->{'mep'}."/".$self->{'dispos'}->{$id}->{'filename'},
		     ForceArray => 1,
		     KeyAttr=> [ 'id' ]));
    } else {
	return(undef);
    }
}

# renvoie la liste triee des identifiants de page
sub ids {
    my ($self)=(@_);

    return(sort { id_triable($a) cmp id_triable($b) }
	   (keys %{$self->{'dispos'}}));
}

# renvoie la liste des numeros d'etudiants
sub etus {
    my ($self)=(@_);
    my %r=();
    for my $i (keys %{$self->{'dispos'}}) {
	my ($e,$p)=get_ep($i);;
	$r{$e}=1;
    }
    return(sort { $a <=> $b } (keys %r));
}

# renvoie les pages correspondantes au numero d'etudiant fourni
# options :
# * 'case'=>1 si on ne veut que les pages avec des cases a cocher
# * 'nom'=>1 si on ne veut que les pages avec le nom
# * 'contenu'=>1 si on ne veut que les pages soit avec des cases
#                a cocher, soit avec le nom a ecrire
# * 'id'=>1 si on veut les pages sous la forme de l'ID de page plutot
#           que sous la forme d'un numero de page du document
# * 'ip'=>1 si on veut a la fois ID & numero de page de document
sub pages_etudiant {
    my ($self,$etu,%oo)=@_;
    my @r=();
    for my $i ($self->ids()) {
	my ($e,$p)=get_ep($i);
	my $ok=1;
	$ok=0 if($oo{'contenu'} 
		 && (!$self->attr($i,'case')) 
		 && (!$self->attr($i,'nom')));
	$ok=0 if($oo{'case'} 
		 && (!$self->attr($i,'case')));
	$ok=0 if($oo{'nom'} 
		 && (!$self->attr($i,'nom')));
	push @r,($oo{'id'} ? $i : $self->attr($i,'page')) 
	    if($e == $etu && $ok);
    }
    return(@r);
}

# meme chose mais pour tous les etudiants a la fois
sub pages_etudiants {
    my ($self,%oo)=@_;
    my %r=();
    for my $i ($self->ids()) {
	my ($e,$p)=get_ep($i);
	my $ok=1;
	$ok=0 if($oo{'contenu'} 
		 && (!$self->attr($i,'case')) 
		 && (!$self->attr($i,'nom')));
	$ok=0 if($oo{'case'} 
		 && (!$self->attr($i,'case')));
	$ok=0 if($oo{'nom'} 
		 && (!$self->attr($i,'nom')));
	if($ok) {
	    if($oo{'ip'}) {
		push @{$r{$e}},{'id'=>$i,'page'=>$self->attr($i,'page')};
	    } else {
		push @{$r{$e}},($oo{'id'} ? $i : $self->attr($i,'page'));
	    }
	}
    }
    return(%r);
}

# renvoie les copies etudiants avec defauts
sub etudiants_defauts {
    my ($self)=@_;
    my %r=();
    my %np=($self->pages_etudiants('nom'=>1));
    my %nc=($self->pages_etudiants('case'=>1));
    for my $etu ($self->etus()) {
	if($etu>0) {
	    push @{$r{'NO_BOX'}},$etu if($#{$nc{$etu}}==-1);
	    push @{$r{'NO_NAME'}},$etu if($#{$np{$etu}}==-1);
	    push @{$r{'SEVERAL_NAMES'}},$etu if($#{$np{$etu}}>0);
	}
    }
    return(%r);
}

sub stats {
    my ($self,$an_list)=@_;

    debug "Computing stats (number of sheets)...";

    my %pages_etu=$self->pages_etudiants('case'=>1,'id'=>1);
    my %r=('complet'=>0,'incomplet'=>0,'manque'=>0,
	   'incomplet_id'=>[],'manque_id'=>[]);
    my %an=map { $_=>1 } ($an_list->ids());
    for my $e ($self->etus()) {
	my $manque=0;
	my $present=0;
	my @m_id=();
	for my $i (@{$pages_etu{$e}}) {
	    if($an{$i}) {
		$present++;
	    } else {
		$manque++;
		push @m_id,$i;
	    }
	}
	if($present>0) {
	    if($manque>0) {
		push @{$r{'manque_id'}},@m_id;
		push @{$r{'incomplet_id'}},$e;
		$r{'manque'}+=$manque;
		$r{'incomplet'}++;
	    } else {
		$r{'complet'}++;
	    }
	}
    }

    debug "OK";

    return(%r);
}

1;


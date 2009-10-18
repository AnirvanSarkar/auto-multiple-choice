#
# Copyright (C) 2008-2009 Alexis Bienvenue <paamc@passoire.fr>
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

use AMC::Basic;
use XML::Simple;
use Storable;

my $VERSION=2;

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
	    debug "Load(MEPList)->erreur\n";
	}
	
    }

    if(!$self) {
	
	$self={};
	bless $self;

    }
    
    $self->{'mep'}=$mep;
    
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
	   || (! -s $self->{'dispos'}->{$i}->{'filename'})) {
	    debug "MEP : entree $i effacee\n";
	    push @ie,$i;
	    delete($self->{'dispos'}->{$i});
	}
    }
    
    # va voir ceux qui sont apparu...

    my @xmls=();

    if(-d $self->{'mep'}) {
	opendir(DIR, $self->{'mep'}) || die "can't opendir ".$self->{'mep'}.": $!";
	@xmls = grep { @st=stat($_); 
		       /\.xml$/ && -s $_ && $st[9]>$self->{'timestamp'} } 
	map { $self->{'mep'}."/$_" } readdir(DIR);
	closedir DIR;
    }

    # va analyser chacun de ces fichiers ...

    for my $f (@xmls) {
	&{$oo{'progres'}}() if($oo{'progres'});
	
	my $lay=XMLin($f,ForceArray => 1,KeepRoot => 1, KeyAttr=> [ 'id' ]);

	my @st=stat($f);
	$self->{'timestamp'}=$st[9] if($st[9]>$self->{'timestamp'});

	if($lay->{'mep'}) {
	    for my $laymep (keys %{$lay->{'mep'}}) {
		if($self->{'id'} eq '' ||
		   $laymep =~ /^\+$self->{'id'}\//) {
		    if($self->{'dispos'}->{$laymep}) {
			# deja en stock :
			if($self->{'dispos'}->{$laymep}->{'filename'} eq $f) {
			    # cas (1) meme fichier, sans doute mis a jour
			    debug "MEP maj : $laymep";
			} else {
			    # cas (2) autre fichier...
			    attention("ATTENTION : identifiant multiple : $laymep");
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
	    debug "Version de fichier MEPList perimee : $v < $VERSION";
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
    return($self->{'dispos'}->{$id}->{$a});
}

sub filename {
    my ($self,$id)=(@_);
    return($self->attr($id,'filename'));
}

sub mep {
    my ($self,$id)=(@_);

    $id=$self->{'au-hasard'} if(!$id);
    return(undef) if(!defined($self->{'dispos'}->{$id}));
    
    if($self->{'dispos'}->{$id}->{'filename'}) {
	return(XMLin($self->{'dispos'}->{$id}->{'filename'},
		     ForceArray => 1,
		     KeyAttr=> [ 'id' ]));
    } else {
	return(undef);
    }
}

# renvoie la liats des identifiants de page
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
# * 'contenu'=>1 si on ne veut que les pages soit avec des cases
#                a cocher, soit avec le nom a ecrire
# * 'id'=>1 si on veut les pages sous la forme de l' ID de page plutot
#           que sous la forme d'un numero de page du document
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
	push @{$r{$e}},($oo{'id'} ? $i : $self->attr($i,'page')) 
	    if($ok);
    }
    return(%r);
}

sub stats {
    my ($self,$an_list)=@_;

    debug "Calcul des stats (nombre de copies saisies)...";

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

__END__


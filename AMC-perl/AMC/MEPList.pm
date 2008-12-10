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
use XML::Dumper;

my %mep_defaut=('id'=>'',
		'saved'=>'',
		'timestamp'=>0,
		);

sub new {
    my ($mep,%o)=(@_);
    my $self;
    my $renew=1;

    if($o{'saved'} && -f $o{'saved'}) {

	$self=load($o{'saved'});
	$renew=0;
	
    } else {
	
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
    
    $self->maj();
    if($renew) {
	$self->from_files();
	$self->save();
    }
    return($self);
}

sub maj {
    my ($self)=@_;
    my @ie=();

    # enleve les fichiers qui n'existent plus...
    
    for my $i (keys %{$self->{'dispos'}}) {
	if((! $self->{'dispos'}->{$i}->{'filename'})
	   || (! -f $self->{'dispos'}->{$i}->{'filename'})) {
	    print STDERR "MEP : entree $i effacee\n";
	    push @ie,$i;
	    delete($self->{'dispos'}->{$i});
	}
    }
    
    # va voir ceux qui sont apparu...

    my @xmls=();

    if(-d $self->{'mep'}) {
	opendir(DIR, $self->{'mep'}) || die "can't opendir ".$self->{'mep'}.": $!";
	@xmls = grep { @st=stat($_); 
		       /\.xml$/ && -f $_ && $st[9]>$self->{'timestamp'} } 
	map { $self->{'mep'}."/$_" } readdir(DIR);
	closedir DIR;

	push @ie,$self->from_files(@xmls) if($#xmls>=0);
    }


    $self->save() if($#ie>=0);
}

sub from_files {
    my ($self,@xmls)=@_;
    my @r=();

    if($#xmls<0) {

	if(-d $self->{'mep'}) {
	    #####
	    # rechercher toutes les possibilites de mise en page :
	    opendir(DIR, $self->{'mep'}) 
		|| die "Erreur a l'ouverture du repertoire ".$self->{'mep'}." : $!";
	    @xmls = map { $self->{'mep'}."/$_"; } 
	    grep { /\.xml$/ && -f $self->{'mep'}."/$_" } readdir(DIR);
	    closedir DIR;
	} else {
	    @xmls=($self->{'mep'});
	}

	$self->{'dispos'}={};

    }
    
    for my $f (@xmls) {
	my $lay=XMLin($f,ForceArray => 1,KeepRoot => 1, KeyAttr=> [ 'id' ]);

	my @st=stat($f);
	$self->{'timestamp'}=$st[9] if($st[9]>$self->{'timestamp'});

	if($lay->{'mep'}) {
	    for my $laymep (keys %{$lay->{'mep'}}) {
		if($self->{'id'} eq '' ||
		   $laymep =~ /^\+$self->{'id'}\//) {
		    if($self->{'dispos'}->{$laymep}) {
			attention("ATTENTION : identifiant multiple : $laymep");
		    }
		    $self->{'dispos'}->{$laymep}={
			'filename'=>$f,
			map { $_=>$lay->{'mep'}->{$laymep}->{$_} } qw/page src/,
		    };
		    push @r,$laymep;
		}
	    }
	}
    }
    
    my @kmep=(keys %{$self->{'dispos'}});
    
    $self->{'au-hasard'}=$kmep[0];
    $self->{'n'}=1+$#kmep;

    return(@r);
}

sub save {
    my ($self,$file)=@_;
    if(!$file) {
	$file=$self->{'saved'};
    }
    return() if(!$file);
    pl2xml($self,$file);
}

sub load {
    my ($file)=@_;
    return(xml2pl($file));
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

sub etus {
    my ($self)=(@_);
    my %r=();
    for my $i (keys %{$self->{'dispos'}}) {
	my ($e,$p)=get_ep($i);;
	$r{$e}=1;
    }
    return(keys %r);
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

__END__

perl -e 'use AMC::MEPList;$m=AMC::MEPList::new("/home/alexis/Projets-QCM/essai/mep");$m->save("/tmp/a.gz");'
perl -e 'use AMC::MEPList;$m=AMC::MEPList::new("/tmp/a.gz","saved"=>1);print join(", ",$m->ids())."\n";'


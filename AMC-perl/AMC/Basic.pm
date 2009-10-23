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

package AMC::Basic;

use File::Temp;
use File::Spec;
use IO::File;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    @ISA         = qw(Exporter);
    @EXPORT      = qw( &id_triable &file2id &get_ep &get_qr &file_triable &sort_id &sort_string &sort_num &attention &model_id_to_iter &commande_accessible &magick_module &debug &set_debug &get_debug &debug_file);
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw();
}

# peut-on acceder a cette commande par exec ?
sub commande_accessible {
    my $c=shift;
    $c =~ s/(?<=[^\s])\s.*//;
    $c =~ s/^\s+//;
    if($c =~ /^\//) {
	return (-x $c);
    } else {
	$ok='';
	for (split(/:/,$ENV{'PATH'})) {
	    $ok=1 if(-x "$_/$c");
	}
	return($ok);
    }
}

my $gm_ok=commande_accessible('gm');

sub magick_module {
    my ($m)=@_;
    if($gm_ok) {
	return('gm',$m);
    } else {
	return($m);
    }
}

sub id_triable {
    my $id=shift;
    if($id =~ /\+([0-9]+)\/([0-9]+)\/([0-9]+)\+/) {
	return(sprintf("%50d-%30d-%40d",$1,$2,$3));
    } else {
	return($id);
    }
}

sub file2id {
    my $f=shift;
    if($f =~ /^[a-z]*-?([0-9]+)-([0-9]+)-([0-9]+)/) {
	return(sprintf("+%d/%d/%d+",$1,$2,$3));
    } else {
	return($f);
    }
}

sub get_qr {
    my $k=shift;
    if($k =~ /([0-9]+)\.([0-9]+)/) {
	return($1,$2);
    } else {
	die "Format de cle inconnu : $k";
    }
}

sub get_ep {
    my $id=shift;
    if($id =~ /^\+([0-9]+)\/([0-9]+)\/([0-9]+)\+$/) {
	return($1,$2);
    } else {
	die "Format d'ID inconnu";
    }
}

sub file_triable {
    my $f=shift;
    if($f =~ /^[a-z]*-?([0-9]+)-([0-9]+)-([0-9]+)/) {
	return(sprintf("%50d-%30d-%40d",$1,$2,$3));
    } else {
	return($f);
    }
}

sub sort_num {
    my ($liststore, $itera, $iterb, $sortkey) = @_;
    my $a = $liststore->get ($itera, $sortkey);
    my $b = $liststore->get ($iterb, $sortkey);
    $a='' if(!defined($a));
    $b='' if(!defined($b));
    my $para=$a =~ s/^\((.*)\)$/$1/;
    my $parb=$b =~ s/^\((.*)\)$/$1/;
    $a=0 if($a !~ /^-?[0-9.]+$/);
    $b=0 if($b !~ /^-?[0-9.]+$/);
    return($parb <=> $para || $a <=> $b);
}

sub sort_string {
    my ($liststore, $itera, $iterb, $sortkey) = @_;
    my $a = $liststore->get ($itera, $sortkey);
    my $b = $liststore->get ($iterb, $sortkey);
    $a='' if(!defined($a));
    $b='' if(!defined($b));
    return($a cmp $b);
}

sub sort_id {
    my ($liststore, $itera, $iterb, $sortkey) = @_;
    my $a = $liststore->get ($itera, $sortkey);
    my $b = $liststore->get ($iterb, $sortkey);
    $a='' if(!defined($a));
    $b='' if(!defined($b));
    return id_triable($a) cmp id_triable($b);
}

sub attention {
    my @l=();
    my $lm=0;
    for my $u (@_) { push  @l,split(/\n/,$u); }
    for my $u (@l) { $lm=length($u) if(length($u)>$lm); }
    print "\n";
    print "*" x ($lm+4)."\n";
    for my $u (@l) {
	print "* ".$u.(" " x ($lm-length($u)))." *\n";
    }
    print "*" x ($lm+4)."\n";
    print "\n";
}

sub bon_id {

    #print join(" --- ",@_),"\n";

    my ($l,$path,$iter,$data)=@_;

    my ($col,$v,$result)=@$data;

    #print "BON [=$v] ? ".$l->get($iter,$col)."\n";

    if($l->get($iter,$col) eq $v) {
	$$result=$iter->copy;
	return(1);
    } else {
	return(0);
    }
}

sub model_id_to_iter {
    my ($cl,$a,$val)=@_;
    my $result=undef;
    $cl->foreach(\&bon_id,[$a,$val,\$result]);
    return($result);
}

# aide au debogage

my $amc_debug='';
my $amc_debug_fh='';
my $amc_debug_filename='';

sub set_debug_file {
    if(!$amc_debug_fh) {
	$amc_debug_fh = new File::Temp(TEMPLATE =>'AMC-DEBUG-XXXXXXXX',
				       SUFFIX => '.log',
				       UNLINK=>0,
				       DIR=>File::Spec->tmpdir);
	$amc_debug_filename=$amc_debug_fh->filename;
	$amc_debug_fh->autoflush(1);
	open(STDERR,">&",$amc_debug_fh);
    }
}

sub debug_file {
    return($amc_debug ? $amc_debug_filename : '');
}

sub set_debug {
    my ($debug)=@_;
    if($debug =~ /\// && -f $debug) {
	# c'est un nom de fichier
	$amc_debug_fh=new IO::File;
	$amc_debug_fh->open(">>$debug");
	$amc_debug_fh->autoflush(1);
	$amc_debug_filename=$debug;
	$debug=1;
	open(STDERR,">&",$amc_debug_fh);
    }
    $amc_debug=$debug;
    set_debug_file() if($amc_debug && !$amc_debug_fh);
}

sub get_debug {
    return($amc_debug);
}

sub debug {
    my @s=@_;
    return if(!$amc_debug);
    for my $l (@s) {
	$l=$l."\n" if($l !~ /\n$/);
	if($amc_debug_fh) {
	    print $amc_debug_fh $l;
	} else {
	    print $l;
	}
    }
}

1;

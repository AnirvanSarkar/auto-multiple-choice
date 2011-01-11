#! /usr/bin/perl
#
# Copyright (C) 2009-2010 Alexis Bienvenue <paamc@passoire.fr>
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

use Getopt::Long;
use XML::Simple;
use AMC::Basic;
use AMC::AssocFile;
use AMC::NamesFile;
use Data::Dumper;

my $notes_file='';
my $notes_id='';
my $liste_file='';
my $liste_key='';
my $assoc_file='';
my $assoc_enc='utf-8';
my $liste_enc='utf-8';
my $debug='';

GetOptions("notes=s"=>\$notes_file,
	   "notes-id=s"=>\$notes_id,
	   "liste=s"=>\$liste_file,
	   "liste-key=s"=>\$liste_key,
	   "assoc=s"=>\$assoc_file,
	   "encodage-interne=s"=>\$assoc_enc,
	   "encodage-liste=s"=>\$liste_enc,
	   "debug=s"=>\$debug,
	   );

set_debug($debug);

die "Needs notes-id" if(!$notes_id);
die "Needs liste-key" if(!$liste_key);
die "Needs notes_file" if(! -s $notes_file);
die "Needs liste_file" if(! -s $liste_file);
die "Needs assoc_file" if(!$assoc_file);

my $as=AMC::AssocFile::new($assoc_file,
			   'encodage'=>$assoc_enc,
			   'liste_key'=>$liste_key,
			   'notes_id'=>$notes_id,
			   );
$as->load();

my %bon_code;

debug "------------------------------------";

debug "Automatic association $liste_file [$liste_enc] / $liste_key";

# lecture liste des etudiants (codes disponibles)

my $liste_e=AMC::NamesFile::new($liste_file,
				'encodage'=>$liste_enc);

for my $ii (0..($liste_e->taille()-1)) {
    $bon_code{$liste_e->data_n($ii,$liste_key)}=1;
}

debug "Student list keys : ".join(',',keys %bon_code);

# lecture notes (et codes reconnus une fois exactement)

my $notes=eval { XMLin($notes_file,
		       'ForceArray'=>1,
		       'KeyAttr'=>['id'],
		       ) };

die "Bad syntax in students list file" if(!$notes);

#print Dumper($notes) if($debug);

for my $i (@{$notes->{'code'}->{$notes_id}->{'valeur'}}) {
    if($i->{'nombre'} != 1) {
	debug "Removing ".$i->{'content'}." : ".$i->{'nombre'}." times";
	$bon_code{$i->{'content'}}='';
    }
}

# calcul...

$as->clear("auto");

for my $id (keys %{$notes->{'copie'}}) {
    my $k=$notes->{'copie'}->{$id}->{'code'}->{$notes_id}->{'content'};
    if($bon_code{$k}) {
	debug "Sheet $id -> $k";
	$as->set("auto",$id,$k);
    }
}

# ecriture

$as->save();



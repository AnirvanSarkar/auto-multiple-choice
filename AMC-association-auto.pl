#! /usr/bin/perl
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

use Getopt::Long;
use XML::Simple;
use AMC::AssocFile;
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
	   "debug!"=>\$debug,
	   );

die "Manque notes-id" if(!$notes_id);
die "Manque liste-key" if(!$liste_key);
die "Manque notes_file" if(! -s $notes_file);
die "Manque liste_file" if(! -s $liste_file);
die "Manque assoc_file" if(!$assoc_file);

my $as=AMC::AssocFile::new($assoc_file,
			   'encodage'=>$assoc_enc,
			   'liste_key'=>$liste_key,
			   'notes_id'=>$notes_id,
			   );
$as->load();

my %bon_code;

# lecture liste des etudiants (codes disponibles)

my $ii=0;

open(FL,"<:encoding(".$liste_enc.")",$liste_file);
 LIG: while(<FL>) {
     chomp;
     s/\#.*//;
     next LIG if(/^\s*$/);
     if($ii) {
	 my @v=split(/:/,$_);
	 $bon_code{$v[$ii-1]}=1;
     } else {
	 my $i=0;
	 for my $h (split(/:/,$_)) {
	     $i++;
	     if($h eq $liste_key) {
		 $ii=$i;
	     }
	 }
     }
 }
close(FL);

print "Codes liste etudiants : ".join(',',keys %bon_code)."\n" if($debug);

# lecture notes (et codes reconnus une fois exactement)

my $notes=eval { XMLin($notes_file,
		       'ForceArray'=>1,
		       'KeyAttr'=>['id'],
		       ) };

die "Probleme syntaxe fichier notes" if(!$notes);

#print Dumper($notes) if($debug);

for my $i (@{$notes->{'code'}->{$notes_id}->{'valeur'}}) {
    if($i->{'nombre'} != 1) {
	print "Retire ".$i->{'content'}." : ".$i->{'nombre'}." fois\n" if($debug);
	$bon_code{$i->{'content'}}='';
    }
}

# calcul...

$as->clear("auto");

for my $id (keys %{$notes->{'copie'}}) {
    my $k=$notes->{'copie'}->{$id}->{'code'}->{$notes_id}->{'content'};
    if($bon_code{$k}) {
	print "Copie $id -> $k\n" if($debug);
	$as->set("auto",$id,$k);
    }
}

# ecriture

$as->save();



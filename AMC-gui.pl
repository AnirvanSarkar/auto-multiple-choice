#! /usr/bin/perl -w
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

use Getopt::Long;

use Gtk2 -init;
use Gtk2::GladeXML;
use XML::Simple;
use IO::File;
use IO::Select;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp;
use File::Copy;
use Time::localtime;
use Encode;
use I18N::Langinfo qw(langinfo CODESET);

use AMC::Basic;
use AMC::MEPList;
use AMC::ANList;
use AMC::Gui::Avancement;
use AMC::Gui::Manuel;
use AMC::Gui::Association;
use AMC::Gui::Commande;

use Data::Dumper;

use constant {
    DOC_TITRE => 0,
    DOC_MAJ => 1,

    MEP_PAGE => 0,
    MEP_ID => 1,
    MEP_MAJ => 2,

    DIAG_ID => 0,
    DIAG_MAJ => 1,
    DIAG_EQM => 2,
    DIAG_EQM_BACK => 3,
    DIAG_DELTA => 4,
    DIAG_DELTA_BACK => 5,

    INCONNU_SCAN => 0,
    INCONNU_ID => 1,

    PROJ_NOM => 0,
    PROJ_ICO => 1,

    CORREC_ID => 0,
    CORREC_MAJ => 1,
    CORREC_FILE => 2,

    COMBO_ID => 1,
    COMBO_TEXT => 0,
};

my $debug=0;

GetOptions("debug!"=>\$debug,
	   );

print "DEBUG MODE\n" if($debug);

my $avance=AMC::Gui::Avancement::new(0);

($e_volume,$e_vdirectories,undef) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
}

my $mep_list;
my $an_list;

my $glade_xml=__FILE__;
$glade_xml =~ s/\.p[ml]$/.glade/i;

my $o_file=Glib::get_home_dir().'/.AMC.xml';

my %w=();
my %o_defaut=('pdf_viewer'=>'evince',
	      'img_viewer'=>'eog',
	      'dat_viewer'=>'oocalc',
	      'xml_viewer'=>'gedit',
	      'tex_editor'=>'gedit',
	      'dir_opener'=>'nautilus --no-desktop file://%d',
	      'rep_projets'=>Glib::get_home_dir().'/Projets-QCM',
	      'rep_modeles'=>'/usr/share/doc/auto-multiple-choice/exemples',
	      'seuil_eqm'=>3.0,
	      'seuil_sens'=>8.0,
	      'saisie_dpi'=>75,
	      'delimiteur_decimal'=>',',
	      'encodage_texte'=>'UTF-8');

my %projet_defaut=('texsrc'=>'',
		   'mep'=>'mep',
		   'cr'=>'cr',
		   'listeetudiants'=>'',
		   'notes'=>'notes.dat',
		   'seuil'=>0.1,
		   'maj_bareme'=>1,
		   'annote_copies'=>0,
		   'fichbareme'=>'bareme.xml',
		   'docs'=>['sujet.pdf','corrige.pdf','calage.pdf'],
		   
		   'modele_regroupement'=>'',

		   'note_max'=>20,
		   'note_grain'=>"0,5",
		   'note_arrondi'=>'inf',
	    
		   'modifie'=>1,
		   );

# lecture options ...

my %o=();

if(-r $o_file) {
    %o=%{XMLin($o_file,SuppressEmpty => '')};
}

for my $k (keys %o_defaut) {
    if(! exists($o{$k})) {
	$o{$k}=$o_defaut{$k};
	print "Nouveau parametre global : $k\n";
    }
    $o{'modifie'}=0;
}

###

my %projet=();

sub id2file {
    my ($id,$prefix,$extension)=(@_);
    $id =~ s/\+//g;
    $id =~ s/\//-/g;
    return(localise($projet{'cr'})."/$prefix-$id.$extension");
}

sub localise {
    my $f=shift;
    if(defined($f)) {
	return($f =~ /^\// ? $f : $o{'rep_projets'}."/".$projet{'nom'}."/$f");
    } else {
	return('');
    }
}

sub is_local {
    my $f=shift;
    if(defined($f)) {
	return($f !~ /^\// || $f =~ /^$o{'rep_projets'}\//);
    } else {
	return('');
    }
}

sub fich_options {
    my $nom=shift;
    return $o{'rep_projets'}."/$nom/options.xml";
}

$gui=Gtk2::GladeXML->new($glade_xml,'main_window');

for(qw/onglets_projet preparation_etats documents_tree source_latex main_window mep_tree import_latex edition_latex
    onglet_notation onglet_saisie
    log_general commande avancement
    liste diag_tree inconnu_tree
    maj_bareme annote_copies correc_tree regroupement_corriges/) {
    $w{$_}=$gui->get_widget($_);
}

$w{'commande'}->hide();

### modele documents

$doc_store = Gtk2::ListStore->new ('Glib::String', 
				   'Glib::String');

my @doc_ligne=($doc_store->append,$doc_store->append,$doc_store->append);

$doc_store->set($doc_ligne[0],DOC_TITRE,'sujet',DOC_MAJ,'');
$doc_store->set($doc_ligne[1],DOC_TITRE,'corrigé',DOC_MAJ,'');
$doc_store->set($doc_ligne[2],DOC_TITRE,'calage',DOC_MAJ,'');
$w{'documents_tree'}->set_model($doc_store);

my $renderer;
my $column;

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("document",
						     $renderer,
						     text=> DOC_TITRE);
$w{'documents_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("état",
						     $renderer,
						     text=> DOC_MAJ);
$w{'documents_tree'}->append_column ($column);

### modele MEP

$mep_store = Gtk2::ListStore->new ('Glib::String',
				   'Glib::String', 
				   'Glib::String');

$w{'mep_tree'}->set_model($mep_store);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("page",
						     $renderer,
						     text=> MEP_PAGE);
$w{'mep_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("ID",
						     $renderer,
						     text=> MEP_ID);
$w{'mep_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("MAJ",
						     $renderer,
						     text=> MEP_MAJ);
$w{'mep_tree'}->append_column ($column);

### modele CORREC

$correc_store = Gtk2::ListStore->new ('Glib::String',
				      'Glib::String', 
				      'Glib::String', 
				      );

$w{'correc_tree'}->set_model($correc_store);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("ID",
						     $renderer,
						     text=> CORREC_ID);
$w{'correc_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("MAJ",
						     $renderer,
						     text=> CORREC_MAJ);
$w{'correc_tree'}->append_column ($column);

### modele DIAGNOSTIQUE SAISIE

$diag_store = Gtk2::ListStore->new ('Glib::String',
				    'Glib::String', 
				    'Glib::String', 
				    'Glib::String', 
				    'Glib::String', 
				    'Glib::String');

$w{'diag_tree'}->set_model($diag_store);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("identifiant",
						     $renderer,
						     text=> DIAG_ID);
$column->set_sort_column_id(DIAG_ID);
$w{'diag_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("mise à jour",
						     $renderer,
						     text=> DIAG_MAJ);
$w{'diag_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("EQM",
						     $renderer,
						     'text'=> DIAG_EQM,
						     'background'=> DIAG_EQM_BACK);
$column->set_sort_column_id(DIAG_EQM);
$w{'diag_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("sensibilité",
						     $renderer,
						     'text'=> DIAG_DELTA,
						     'background'=> DIAG_DELTA_BACK);
$column->set_sort_column_id(DIAG_DELTA);
$w{'diag_tree'}->append_column ($column);

### modeles combobox

sub cb_model {
    my %texte=(@_);
    my $cs=Gtk2::ListStore->new ('Glib::String','Glib::String');
    for my $k (keys %texte) {
	$cs->set($cs->append,
		 COMBO_ID,$k,
		 COMBO_TEXT,$texte{$k});
    }
    return($cs);
}

my %cb_stores=(
	       'delimiteur_decimal'=>cb_model(','=>', (virgule)',
					      '.'=>'. (point)'),
	       'note_arrondi'=>cb_model('inf'=>'inférieur',
					'normal'=>'normal',
					'sup'=>'supérieur'),
	       );

## tri pour nombres

sub sort_num {
    my ($liststore, $itera, $iterb, $sortkey) = @_;
    my $a = $liststore->get ($itera, $sortkey);
    my $b = $liststore->get ($iterb, $sortkey);
    $a=0 if($a !~ /^-?[0-9.]+$/);
    $b=0 if($b !~ /^-?[0-9.]+$/);
    return $a <=> $b;
}

$diag_store->set_sort_func(DIAG_EQM,\&sort_num,DIAG_EQM);
$diag_store->set_sort_func(DIAG_DELTA,\&sort_num,DIAG_DELTA);

## tri pour IDS

$diag_store->set_sort_func(DIAG_ID,\&sort_id,DIAG_ID);

## menu contextuel sur liste diagnostique -> visualisation zoom/page

$w{'diag_tree'}->signal_connect('button_release_event' =>
    sub {
	my ($self, $event) = @_;
	return FALSE unless $event->button == 3;
	my ($path, $column, $cell_x, $cell_y) = 
	    $w{'diag_tree'}->get_path_at_pos ($event->x, $event->y);
	if ($path) {
	    #my $row = $path->to_string();
	    #print "X=$cell_x Y=$cell_y ROW=$row\n";
	    
	    my $menu = Gtk2::Menu->new;
	    my $c=0;
	    foreach (qw/page zoom/) {
		my $id=$diag_store->get($diag_store->get_iter($path),
					DIAG_ID);
		my $f=id2file($id,$_,'jpg');
		if(-f $f) {
		    $c++;
		    my $item = Gtk2::MenuItem->new ($_);
		    $menu->append ($item);
		    $item->show;
		    $item->signal_connect (activate => sub {
			my (undef, $sortkey) = @_;
			print "Visualisation $f...\n";
			if(fork()!=0) {
			    exec($o{'img_viewer'},$f);
			}
		    }, $_);
		}
	    }
	    $menu->popup (undef, undef, undef, undef,
			  $event->button, $event->time) if($c>0);
	    return TRUE; # stop propagation!
	    
	}
    });

### modele inconnus

$inconnu_store = Gtk2::ListStore->new ('Glib::String','Glib::String');

$w{'inconnu_tree'}->set_model($inconnu_store);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("scan",
						     $renderer,
						     text=> INCONNU_SCAN);
$w{'inconnu_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("ID",
						     $renderer,
						     text=> INCONNU_ID);
$w{'inconnu_tree'}->append_column ($column);


# peut-on acceder a cette commande par exec ?
sub commande_accessible {
    my $c=shift;
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

# toutes les commandes prevues sont-elles accessibles ? Si non, on
# avertit l'utilisateur

sub test_commandes {
    my @pasbon=();
    for my $c (grep { /_(viewer|editor|opener)$/ } keys(%o)) {
	my $nc=$o{$c};
	$nc =~ s/\s.*// if($c =~ /_opener$/);
	push @pasbon,$nc if(!commande_accessible($nc));
    }
    if(@pasbon) {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'warning', # message type
					       'ok', # which set of buttons?
					       "Certaines commandes prévues pour l'ouverture de documents ne sont pas accessibles : ".join("",@pasbon).". Vérifiez que les commandes sont les bonnes et que les programmes correspondants sont bien installés. Vous pouvez aussi modifier les commandes à utiliser en sélectionnant Préférences dans le menu Édition.");
	$dialog->run;
	$dialog->destroy;
    }
}

### Appel à des commandes externes -- log, annulation

my %les_commandes=();
my $cmd_id=0;

sub commande {
    my (@opts)=@_;
    $cmd_id++;

    my $c=AMC::Gui::Commande::new('avancement'=>$w{'avancement'},
				  'log'=>$w{'log_general'},
				  'finw'=>sub {
				      my $c=shift;
				      $w{'onglets_projet'}->set_sensitive(1);
				      $w{'commande'}->hide();
				      delete $les_commandes{$c->{'_cmdid'}};
				  },
				  @opts);

    $c->{'_cmdid'}=$cmd_id;
    $les_commandes{$cmd_id}=$c;

    $w{'onglets_projet'}->set_sensitive(0);
    $w{'commande'}->show();

    $c->open();
}
    
sub commande_annule {
    for (keys %les_commandes) { $les_commandes{$_}->quitte(); }
}

### Actions des menus

my $proj_store;

sub projet_nouveau {
    projet_charge('',1);
}

sub projet_charge {
    my (undef,$cree)=(@_);
    my @projs;
    
    mkdir($o{'rep_projets'}) if($cree && ! -d $o{'rep_projets'});
    
    if(-d $o{'rep_projets'}) {
	opendir(DIR, $o{'rep_projets'}) 
	    || die "Erreur a l'ouverture du repertoire ".$o{'rep_projets'}." : $!";
	my @f=map { decode("utf-8",$_); } readdir(DIR);
	#print "F:".join(',',map { $_.":".(-d $o{'rep_projets'}."/".$_) } @f).".\n";
	@projs = grep { ! /^\./ && -d $o{'rep_projets'}."/".$_ } @f;
	closedir DIR;
	#print "[".$o{'rep_projets'}."] P:".join(',',@projs).".\n";
    }

    if($#projs>=0 || $cree) {
	
	my $gp=Gtk2::GladeXML->new($glade_xml,'choix_projet');
	$gp->signal_autoconnect_from_package('main');

	for(qw/choix_projet choix_projets_liste
	    projet_bouton_ouverture projet_bouton_creation
	    projet_nom projet_nouveau/) {
	    $w{$_}=$gp->get_widget($_);
	}

	if($cree) {
	    $w{'projet_nouveau'}->show();
	    $w{'projet_bouton_creation'}->show();
	    $w{'projet_bouton_ouverture'}->hide();
	}
	
	$proj_store = Gtk2::ListStore->new ('Glib::String',
					    'Gtk2::Gdk::Pixbuf');
	
	$w{'choix_projets_liste'}->set_model($proj_store);
	
	$w{'choix_projets_liste'}->set_text_column(PROJ_NOM);
	$w{'choix_projets_liste'}->set_pixbuf_column(PROJ_ICO);
	
	my $pb=$w{'main_window'}->render_icon ('gtk-open', 'menu');
	
	for (@projs) {
	    #print "Projet : $_.\n";
	    $proj_store->set($proj_store->append,
			     PROJ_NOM,$_,
			     PROJ_ICO,$pb); 
	}
	
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'info', # message type
					       'ok', # which set of buttons?
					       "Vous n'avez aucun projet de QCM dans le répertoire %s !",$o{'rep_projets'});
	$dialog->run;
	$dialog->destroy;
	
    }
}

sub projet_charge_ok {
    my $sel=$w{'choix_projets_liste'}->get_selected_items();
    my $proj;

    if($sel) {
	$proj=$proj_store->get($proj_store->get_iter($sel),PROJ_NOM);
    }

    $w{'choix_projet'}->destroy();

    projet_ouvre($proj) if($proj);
}

sub projet_charge_nouveau {
    my $proj=$w{'projet_nom'}->get_text();
    $w{'choix_projet'}->destroy();

    projet_ouvre($proj,1);
    projet_sauve();
}

sub projet_charge_non {
    $w{'choix_projet'}->destroy();
}

sub projet_sauve {
    print "Sauvegarde du projet...\n";
    my $of=fich_options($projet{'nom'});
    if(open(OPTS,">:encoding(utf-8)",$of)) {
	print OPTS XMLout(\%projet,
			  "XMLDecl"=>'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
			  "RootName"=>'projetAMC','NoAttr'=>1)."\n";
	close OPTS;
	$projet{'modifie'}=0;
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'error', # message type
					       'ok', # which set of buttons?
					       "Erreur à l'ecriture du fichier d'options %s : %s",$of,$!);
	$dialog->run;
	$dialog->destroy;      
    }
}

### Actions des boutons de la partie DOCUMENTS

sub doc_active {
    my $sel=$w{'documents_tree'}->get_selection()->get_selected_rows()->get_indices();
    #print "Active $sel...\n";
    my $f=localise($projet{'docs'}->[$sel]);
    print "Visualisation $f...\n";
    if(fork()!=0) {
	exec($o{'pdf_viewer'},$f);
    }
}

sub mep_active {
    my $sel=$w{'mep_tree'}->get_selection()->get_selected_rows()->get_indices();
    my $id=($mep_list->ids())[$sel];
    print "Active MEP $sel : ID=$id...\n";
    my $f=$mep_list->filename($id);
    print "Visualisation $f...\n";
    if(fork()!=0) {
	exec($o{'xml_viewer'},$f);
    }
}

sub fichiers_mep {
    my $md=localise($projet{'mep'});
    opendir(MDIR, $md) || die "can't opendir $md: $!";
    my @meps = map { "$md/$_" } grep { /^mep.*xml$/ && -f "$md/$_" } readdir(MDIR);
    closedir MDIR;
    return(@meps);
}

sub doc_maj {
    my $sur=0;
    if($an_list->nombre()>0) {
	my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
					       'destroy-with-parent',
					       'warning', # message type
					       'ok-cancel', # which set of buttons?
					       "L'analyse de certaines copies a déjà été effectuée sur la base des documents de travail actuels. Vous avez donc vraisemblablement déjà effectué l'examen sur la base de ces documents. Si vous modifiez les documents de travail, vous ne serez plus en mesure d'analyser les copies que vous avez déjà distribué ! Souhaitez-vous tout de même continuer ? Cliquez sur Valider pour effacer les anciennes mises en page et mettre à jour les documents de travail, ou sur Annuler pour annuler cette opération. <b>Pour permettre l'utilisation d'un sujet déjà imprimé, annulez !</b>");
	my $reponse=$dialog->run;
	$dialog->destroy;      
	
	if($reponse eq 'cancel') {
	    return(0);
	} 

	$sur=1;
    }
	
    # deja des MEP fabriquees ?
    my @meps=fichiers_mep();
    if(@meps) {
	if(!$sur) {
	    my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
							       'destroy-with-parent',
							       'question', # message type
							       'ok-cancel', # which set of buttons?
							       "Certaines mises en page on déjà été calculées pour les documents actuels. En refabriquant les documents de travail, les mises en page deviendront obsolètes et seront donc effacées. Souhaitez-vous tout de même continuer ? Cliquez sur Valider pour effacer les anciennes mises en page et mettre à jour les documents de travail, ou sur Annuler pour annuler cette opération. <b>Pour permettre l'utilisation d'un sujet déjà imprimé, annulez !</b>");
	    my $reponse=$dialog->run;
	    $dialog->destroy;      
	    
	    if($reponse eq 'cancel') {
		return(0);
	    } 
	}
	
	unlink @meps;
	detecte_mep();
    }   

    #
    commande('commande'=>[with_prog("AMC-prepare.pl"),
			  "--mode","s",
			  localise($projet{'texsrc'}),
			  "--prefix",localise(''),
			  ],
	     'signal'=>2,
	     'texte'=>'Mise à jour des documents...',
	     'progres'=>-0.01,
	     'fin'=>sub { detecte_documents(); });
}

sub calcule_mep {
    # on efface les anciennes MEP
    my @meps=fichiers_mep();
    unlink @meps;
    # on recalcule...
    commande('commande'=>[with_prog("AMC-prepare.pl"),
			  "--calage",localise($projet{'docs'}->[2]),
			  "--progression",1,
			  "--mode","m",
			  localise($projet{'texsrc'}),
			  "--mep",localise($projet{'mep'}),
			  ],
	     'texte'=>'Calcul des mises en page...',
	     'progres'=>1,'fin'=>sub { detecte_mep(); });
}

### Actions des boutons de la partie SAISIE

sub saisie_manuelle {
    my $gm=AMC::Gui::Manuel::new('cr-dir'=>localise($projet{'cr'}),
				 'mep-dir'=>localise($projet{'mep'}),
				 'liste'=>$projet{'listeetudiants'},
				 'sujet'=>localise($projet{'docs'}->[0]),
				 'etud'=>'',
				 'dpi'=>$o{'saisie_dpi'},
				 'debug'=>$debug,
				 'seuil'=>$projet{'seuil'},
				 'global'=>0,
				 'en_quittant'=>\&detecte_analyse,
				 );
}

sub saisie_automatique {
    my $gsa=Gtk2::GladeXML->new($glade_xml,'saisie_auto');
    $gsa->signal_autoconnect_from_package('main');
    for(qw/saisie_auto/) {
	$w{$_}=$gsa->get_widget($_);
    }
}

sub saisie_auto_annule {
    $w{'saisie_auto'}->destroy();
}

sub saisie_auto_ok {
    my @f=$w{'saisie_auto'}->get_filenames();
    print "Scans : ".join(',',@f)."\n";
    $w{'saisie_auto'}->destroy();

    # pour eviter tout probleme du a une longueur excessive de la
    # ligne de commande, fabrication fichier temporaire avec la liste
    # des fichiers...

    my $fh=File::Temp->new(TEMPLATE => "liste-XXXXXX",
			   TMPDIR => 1,
			   UNLINK=> 1);
    print $fh join("\n",@f)."\n";
    $fh->seek( 0, SEEK_END );

    # appel AMC-analyse avec cette liste

    commande('commande'=>[with_prog("AMC-analyse.pl"),
			  "--binaire",
			  "--progression",1,
			  "--mep",localise($projet{'mep'}),
			  "--cr",localise($projet{'cr'}),
			  "--liste-fichiers",$fh,
			  ],
	     'signal'=>2,
	     'texte'=>'Saisie automatique...',
	     'progres'=>1,
	     'niveau1'=>sub { detecte_analyse('interne'=>1); },
	     'o'=>{'fh'=>$fh},
	     'fin'=>sub {
		 my $c=shift;
		 my @err=$c->erreurs();

		 close($c->{'o'}->{'fh'});

		 my @fe=();
		 for(@err) {
		     if(/ERREUR\(([^\)]+)\)\(([^\)]+)\)/) {
			 push @fe,[$1,$2];
		     }
		 }
		 detecte_analyse('erreurs'=>\@fe);
	     }
	     );
    
}

sub valide_liste {
    $projet{'listeetudiants'}=$w{'liste'}->get_filename();
    $projet{'modifie'}=1; print "* valide_liste\n" if($debug);
}

### Actions des boutons de la partie NOTATION

sub associe {
    if(-f $projet{'listeetudiants'}) {
	my $ga=AMC::Gui::Association::new('cr'=>localise($projet{'cr'}),
					  'liste'=>$projet{'listeetudiants'},
					  'global'=>0,
					  'encoding'=>$o{'encodage_texte'},
					  );
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'info', # message type
					       'ok', # which set of buttons?
					       "Avant d'associer les noms aux copies, il faut indiquer un fichier de liste des étudiants dans l'onglet « Saisie ».");
	$dialog->run;
	$dialog->destroy;
	
    }
}

sub valide_cb {
    my ($var,$cb)=@_;
    my $cbc=$cb->get_active();
    if($cbc xor $$var) {
	$$var=$cbc;
	$projet{'modifie'}=1;
	print "* valide_cb\n" if($debug);
    }
}

sub valide_options_correction {
    my ($ww,$o)=@_;
    my $name=$ww->get_name();
    print "Valide OC depuis $name\n" if($debug);
    valide_cb(\$projet{$name},$w{$name});
}

sub valide_options_notation {
    reprend_pref('notation',\%projet);
}

sub voir_notes {
    if(-f localise($projet{'notes'})) {
	if(fork()!=0) {
	    exec($o{'dat_viewer'},localise($projet{'notes'}));
	}
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'info', # message type
					       'ok', # which set of buttons?
					       "Les copies ne sont pas encore corrigées : veuillez d'abord utiliser le bouton « Corriger ».");
	$dialog->run;
	$dialog->destroy;
	
    }
}

sub noter {
    if($projet{'maj_bareme'}) {
	commande('commande'=>[with_prog("AMC-prepare.pl"),
			      "--mode","b",
			      "--bareme",localise($projet{'fichbareme'}),
			      localise($projet{'texsrc'}),
			      ],
		 'texte'=>'Lecture du bareme...',
		 'progres'=>-0.01);
    }
    commande('commande'=>[with_prog("AMC-note.pl"),
			  "--cr",localise($projet{'cr'}),
			  "--bareme",localise($projet{'fichbareme'}),
			  "-o",localise($projet{'notes'}),
			  ($projet{'annote_copies'} ? "--copies" : "--no-copies"),
			  "--seuil",$projet{'seuil'},
			  
			  "--grain",$projet{'note_grain'},
			  "--arrondi",$projet{'note_arrondi'},
			  "--notemax",$projet{'note_max'},
			  
			  "--delimiteur",$o{'delimiteur_decimal'},
			  ],
	     'signal'=>2,
	     'texte'=>'Calcul des notes...',
	     'progres'=>-0.01,
	     'fin'=>sub {
		 voir_notes();
		 detecte_correc() if($projet{'annote_copies'});
	     },
	     );
}

sub visualise_correc {
    my $sel=$w{'correc_tree'}->get_selection()->get_selected_rows();
    #print "Correc $sel $correc_store\n";
    my $f=$correc_store->get($correc_store->get_iter($sel),CORREC_FILE);
    print "Visualisation $f...\n";
    if(fork()!=0) {
	exec($o{'img_viewer'},$f);
    }
}

sub regroupement {

    valide_options_notation();

    commande('commande'=>[with_prog("AMC-regroupe.pl"),
			  "--cr",localise($projet{'cr'}),
			  "--progression",1,
			  "--modele",$projet{'modele_regroupement'},
			  ],
	     'texte'=>'Regroupement des pages corrigées par étudiant...',
	     'progres'=>1,
	     );
}

sub regarde_regroupements {
    my $f=localise($projet{'cr'})."/corrections/pdf";
    print STDERR "Je vais voir $f\n";
    my $seq=0;
    my @c=map { $seq+=s/[%]d/$f/g;$_; } split(/\s+/,$o{'dir_opener'});
    push @c,$f if(!$seq);
    # nautilus attend des arguments dans l'encodage specifie par LANG & co.
    @c=map { encode(langinfo(CODESET),$_); } @c;

    if(fork()!=0) {
	exec(@c);
    }
}

###

sub activate_apropos {
    my $gap=Gtk2::GladeXML->new($glade_xml,'apropos');
    $gap->signal_autoconnect_from_package('main');
    for(qw/apropos/) {
	$w{$_}=$gap->get_widget($_);
    }
}

sub close_apropos {
    $w{'apropos'}->destroy();
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

# transmet les preferences vers les widgets correspondants
sub transmet_pref {
    my ($gap,$prefixe,$h)=@_;

    for my $t (keys %$h) {
	my $wp=$gap->get_widget($prefixe.'_x_'.$t);
	if($wp) {
	    $w{$prefixe.'_x_'.$t}=$wp;
	    $wp->set_text($h->{$t});
	}
	$wp=$gap->get_widget($prefixe.'_f_'.$t);
	if($wp) {
	    $w{$prefixe.'_f_'.$t}=$wp;
	    if($wp->get_action =~ /-folder$/i) {
		$wp->set_current_folder($h->{$t});
	    } else {
		$wp->set_filename($h->{$t});
	    }
	}
	$wp=$gap->get_widget($prefixe.'_c_'.$t);
	if($wp) {
	    $w{$prefixe.'_c_'.$t}=$wp;
	    if($cb_stores{$t}) {
		$wp->set_model($cb_stores{$t});
		my $i=model_id_to_iter($wp->get_model,COMBO_ID,$h->{$t});
		if($i) {
		    #print "[$t] trouve $i\n";
		    #print " -> ".$cb_stores{$t}->get($i,COMBO_TEXT)."\n";
		    $wp->set_active_iter($i);
		}
	    } else {
		$wp->set_active($h->{$t});
	    }
	}
    }
}

# met a jour les preferences depuis les widgets correspondants
sub reprend_pref {
    my ($prefixe,$h)=@_;

    for my $t (keys %$h) {
	my $n;
	my $wp=$w{$prefixe.'_x_'.$t};
	if($wp) {
	    $n=$wp->get_text();
	    $h->{'modifie'}=1 if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_f_'.$t};
	if($wp) {
	    if($wp->get_action =~ /-folder$/i) {
		$n=$wp->get_current_folder();
	    } else {
		$n=$wp->get_filename();
	    }
	    $h->{'modifie'}=1 if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_c_'.$t};
	if($wp) {
	    if($wp->get_model) {
		$n=$wp->get_model->get($wp->get_active_iter,COMBO_ID);
		#print "[$t] valeur=$n\n";
	    } else {
		$n=$wp->get_active();
	    }
	    $h->{'modifie'}=1 if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
    }
    
}

sub edit_preferences {
    my $gap=Gtk2::GladeXML->new($glade_xml,'edit_preferences');
    $gap->signal_autoconnect_from_package('main');
    for(qw/edit_preferences pref_projet_tous pref_projet_annonce/) {
	$w{$_}=$gap->get_widget($_);
    }
    for my $t (grep { /^pref(_projet)?_[xfc]_/ } (keys %w)) {
	delete $w{$t};
    }
    transmet_pref($gap,'pref',\%o);
    transmet_pref($gap,'pref_projet',\%projet) if($projet{'nom'});

    # projet ouvert -> ne pas changer localisation
    if($projet{'nom'}) {
	$w{'pref_f_rep_projets'}->set_sensitive(0);
	$w{'pref_projet_annonce'}->set_label('<i>Préférences du projet « <b>'.$projet{'nom'}.'</b> »</i>');
    } else {
	$w{'pref_projet_tous'}->set_sensitive(0);
	$w{'pref_projet_annonce'}->set_label('<i>Préférences du projet</i>');
    }
}

sub accepte_preferences {
    reprend_pref('pref',\%o);
    reprend_pref('pref_projet',\%projet) if($projet{'nom'});
    $w{'edit_preferences'}->destroy();

    print "Sauvegarde des preferences generales...\n";

    if(open(OPTS,">$o_file")) {
	print OPTS XMLout(\%o,"RootName"=>'AMC','NoAttr'=>1)."\n";
	close OPTS;
	$o{'modifie'}=0;
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'error', # message type
					       'ok', # which set of buttons?
					       "Erreur à l'ecriture du fichier d'options %s : %s",$o_file,$!);
	$dialog->run;
	$dialog->destroy;      
    }

    test_commandes();
}

sub annule_preferences {
    print "Annule\n";
    $w{'edit_preferences'}->destroy();
}

sub file_maj {
    my $f=shift;
    if(-f $f) {
	if(-r $f) {
	    my @s=stat($f);
	    my $t=localtime($s[9]);
	    return(sprintf("%02d/%02d/%04d %02d:%02d",
			   $t->mday,$t->mon+1,$t->year+1900,$t->hour,$t->min));
	} else {
	    return('illisible');
	}
    } else {
	return('inexistant');
    }
}

sub detecte_documents {
    for my $i (0..2) {
	my $r='';
	my $f=localise($projet{'docs'}->[$i]);
	$doc_store->set($doc_ligne[$i],DOC_MAJ,file_maj($f));
    }
}

sub detecte_mep {
    $w{'commande'}->show();
    $w{'avancement'}->set_text("Recherche des mises en page détectées...");
    $w{'avancement'}->set_fraction(0);
    Gtk2->main_iteration while ( Gtk2->events_pending );

    $mep_list=AMC::MEPList::new(localise($projet{'mep'}));
    $mep_store->clear();

    $w{'onglet_saisie'}->set_sensitive($mep_list->nombre()>0);

    my $ii=0;
    for my $i ($mep_list->ids()) {
	my $iter=$mep_store->append;
	$mep_store->set($iter,MEP_ID,$i,MEP_PAGE,$mep_list->attr($i,'page'),MEP_MAJ,file_maj($mep_list->filename($i)));

	$ii++;
	$w{'avancement'}->set_fraction($ii/$mep_list->nombre());
	Gtk2->main_iteration while ( Gtk2->events_pending );
    }

    $w{'avancement'}->set_text('');
    $w{'avancement'}->set_fraction(0);
    $w{'commande'}->hide();
    Gtk2->main_iteration while ( Gtk2->events_pending );
}

sub detecte_correc {
    my $cordir=localise("cr/corrections/jpg");
    $correc_store->clear();
    my @corr=();

    if(opendir(DIR, $cordir)) {
	@corr = sort { file_triable($a) cmp file_triable($b) } 
	grep { /\.jpg$/ && -f "$cordir/$_" } readdir(DIR);
	closedir DIR;
	
	for my $f (@corr) {
	    my $iter=$correc_store->append;
	    $correc_store->set($iter,CORREC_FILE,"$cordir/$f",
			       CORREC_MAJ,file_maj("$cordir/$f"),
			       CORREC_ID,file2id($f));
	}
    }

    $w{'regroupement_corriges'}->set_sensitive($#corr>=0);
}

sub detecte_analyse {
    my (%oo)=(@_);

    $w{'commande'}->show();
    my $av_text=$w{'avancement'}->get_text();
    $w{'avancement'}->set_text("Recherche des analyses effectuées...");
    $w{'avancement'}->set_fraction(0) if(!$oo{'interne'});
    Gtk2->main_iteration while ( Gtk2->events_pending );

    my @ids_m=$an_list->maj();

    print "IDS_M : ".join(' ',@ids_m)."\n";

    $w{'onglet_notation'}->set_sensitive($an_list->nombre()>0);
    detecte_correc() if($an_list->nombre()>0);

    my $ii=0;

    for my $i (@ids_m) {
	# deja dans la liste ? sinon on rajoute...
	my $iter=model_id_to_iter($diag_store,DIAG_ID,$i);
	$iter=$diag_store->append if(!$iter);

	my $a=$an_list->analyse($i);

	my $deltamin=1;
	for my $c (keys %{$a->{'case'}}) {
	    my $d=abs($projet{'seuil'}-$a->{'case'}->{$c}->{'r'});
	    $deltamin=$d if($d<$deltamin);
	}

	my $eqm=$a->{'transformation'}->{'mse'};
	my $sens=10*($projet{'seuil'}-$deltamin)/$projet{'seuil'};
	my $man=$a->{'manuel'};

	$diag_store->set($iter,
			 DIAG_ID,$i,
			 DIAG_EQM,($man ? "---" : sprintf("%.01f",$eqm)),
			 DIAG_EQM_BACK,(!$man && $eqm>$o{'seuil_eqm'} ? 'red' : undef),
			 DIAG_MAJ,file_maj($an_list->filename($i)),
			 DIAG_DELTA,($man ? "---" : sprintf("%.01f",$sens)),
			 DIAG_DELTA_BACK,(!$man && $sens>$o{'seuil_sens'} ? 'red' : undef),
			 );

	$ii++;
	$w{'avancement'}->set_fraction($ii/(1+$#ids_m)) if(!$oo{'interne'});
	Gtk2->main_iteration while ( Gtk2->events_pending );
    }

    # erreurs lors du traitement automatique des scans :

    $inconnu_store->clear();
    
    if($oo{'erreurs'}) {
	for my $f (@{$oo{'erreurs'}}) {
	    my $iter=$inconnu_store->append;
	    $inconnu_store->set($iter,
				INCONNU_SCAN,$f->[0],
				INCONNU_ID,$f->[1]);
	}
    }

    # ID manquants :

    for my $i ($mep_list->ids()) {
	if(! $an_list->filename($i)) {
	    my $iter=$inconnu_store->append;
	    $inconnu_store->set($iter,
				INCONNU_SCAN,'absent',
				INCONNU_ID,$i);
	}
    }
    

    $w{'avancement'}->set_text($av_text);
    $w{'avancement'}->set_fraction(0) if(!$oo{'interne'});
    $w{'commande'}->hide() if(!$oo{'interne'});
    Gtk2->main_iteration while ( Gtk2->events_pending );
}

sub set_source_tex {
    if($projet{'texsrc'}) {
	$w{'source_latex'}->set_filename(localise($projet{'texsrc'}));
    } else {
	$w{'source_latex'}->set_filename('');
	$w{'source_latex'}->set_current_folder($o{'rep_modeles'});
    }
    valide_source_tex('',1);
}

sub valide_source_tex {
    shift;
    my ($direct)=(@_);
    if(!$direct) {
	$projet{'texsrc'}=$w{'source_latex'}->get_filename();
	print "Source LaTeX : ".$projet{'texsrc'}."\n";
    }
    $projet{'modifie'}=1; print "* valide_source_tex\n" if($debug);
    $w{'preparation_etats'}->set_sensitive(-f localise($projet{'texsrc'}));

    if(is_local($projet{'texsrc'})) {
	$w{'import_latex'}->hide();
	$w{'edition_latex'}->show();
    } else {
	$w{'import_latex'}->show();
	$w{'edition_latex'}->hide();
    }

    detecte_documents();
}

sub importe_source {
    my ($fxa,$fxb,$fb) = splitpath(localise($projet{'texsrc'}));
    my $dest=localise($fb);

    if(-f $dest) {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'error', # message type
					       'yes-no', # which set of buttons?
					       "Le fichier %s existe déjà dans le répertoire projet : voulez-vous écraser son ancien contenu ? Cliquez sur oui pour remplacer le fichier pré-existant par celui que vous venez de sélectionner, ou sur non pour annuler l'import du fichier source.",$fb);
	my $reponse=$dialog->run;
	$dialog->destroy;      

	if($reponse eq 'no') {
	    return(0);
	} 
    }

    if(copy(localise($projet{'texsrc'}),$dest)) {
	$projet{'texsrc'}=$fb;
	set_source_tex();
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'error', # message type
					       'ok', # which set of buttons?
					       "Erreur durant la copie du fichier source : %s",$!);
	$dialog->run;
	$dialog->destroy;      
    }
}

sub edite_source {
    my $f=localise($projet{'texsrc'});
    print "Edition $f...\n";
    if(fork()!=0) {
	exec($o{'tex_editor'},$f);
    }
}

sub valide_projet {
    set_source_tex();
    $w{'liste'}->set_filename($projet{'listeetudiants'});
    detecte_mep();

    $an_list=AMC::ANList::new(localise($projet{'cr'}),'new_vide'=>1);
    detecte_analyse();

    print "Options correction : MB".$projet{'maj_bareme'}."\n" if($debug);
    $w{'maj_bareme'}->set_active($projet{'maj_bareme'});
    print "Options correction : AC".$projet{'annote_copies'}."\n" if($debug);
    $w{'annote_copies'}->set_active($projet{'annote_copies'});

    transmet_pref($gui,'notation',\%projet);

    my $t=$w{'main_window'}->get_title();
    $t.= ' - projet '.$projet{'nom'} 
        if(!($t =~ s/-.*/- projet $projet{'nom'}/));
    $w{'main_window'}->set_title($t);
}

sub projet_ouvre {
    my ($proj,$deja)=(@_);

    if($proj) {
	
	quitte_projet();

	if(!$deja) {
	    print "Ouverture du projet $proj...\n";
	    
	    %projet=%{XMLin(fich_options($proj),SuppressEmpty => '')};
	}
	
	$projet{'nom'}=$proj;

	for my $sous ('',qw:cr cr/corrections cr/corrections/jpg cr/corrections/pdf mep scans:) {
	    my $rep=$o{'rep_projets'}."/$proj/$sous";
	    if(! -x $rep) {
		print "Creation du repertoire $rep...\n";
		mkdir($rep);
	    }
	}
    
	for my $k (keys %projet_defaut) {
	    if(! exists($projet{$k})) {
		$projet{$k}=$projet_defaut{$k};
		print "Nouveau parametre : $k\n";
	    }
	}

	#print Dumper(\%projet)."\n";
	$w{'onglets_projet'}->set_sensitive(1);

	valide_projet();

	$projet{'modifie'}='';
    }
}

sub quitte_projet {
    if($projet{'nom'}) {
	
	valide_options_notation();
	
	if($projet{'modifie'}) {
	    my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
						   'destroy-with-parent',
						   'question', # message type
						   'yes-no', # which set of buttons?
						   sprintf("Vous n'avez pas sauvegardé les options du projet <i>%s</i>, qui ont pourtant été modifiées : voulez-vous le faire avant de le quitter ?",$projet{'nom'}));
	    my $reponse=$dialog->run;
	    $dialog->destroy;      
	    
	    if($reponse eq 'yes') {
		projet_sauve();
	    } 
	}
    }
}

sub quitter {

    quitte_projet();

    Gtk2->main_quit;
    
}

$gui->signal_autoconnect_from_package('main');


###

projet_ouvre($ARGV[0]);

test_commandes();

Gtk2->main();

1;

__END__

=head1 AMC-gui.pl

Interface graphique de gestion de projet de QCM automatique

=head1 SYNOPSIS

  AMC-gui.pl [projet]

=head1 OPTIONS

B<AMC-gui.pl> a un unique paramètre optionnel : le nom du projet à ouvrir
au lancement.

=head1 AUTEUR

Alexis Bienvenue <paamc@passoire.fr>

=cut


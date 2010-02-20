#! /usr/bin/perl -w
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

use Getopt::Long;

use Gtk2 -init;
use Gtk2::GladeXML;
use XML::Simple;
use IO::File;
use IO::Select;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use File::Copy;
use Time::localtime;
use Encode;
use I18N::Langinfo qw(langinfo CODESET);

use Net::CUPS;
use Net::CUPS::PPD;

use AMC::Basic;
use AMC::MEPList;
use AMC::ANList;
use AMC::Gui::Manuel;
use AMC::Gui::Association;
use AMC::Gui::Commande;
use AMC::Gui::Notes;

use Data::Dumper;

use constant {
    DOC_TITRE => 0,
    DOC_MAJ => 1,

    MEP_PAGE => 0,
    MEP_ID => 1,
    MEP_MAJ => 2,

    DIAG_ID => 0,
    DIAG_ID_BACK => 1,
    DIAG_MAJ => 2,
    DIAG_EQM => 3,
    DIAG_EQM_BACK => 4,
    DIAG_DELTA => 5,
    DIAG_DELTA_BACK => 6,

    INCONNU_SCAN => 0,
    INCONNU_ID => 1,

    PROJ_NOM => 0,
    PROJ_ICO => 1,

    CORREC_ID => 0,
    CORREC_MAJ => 1,
    CORREC_FILE => 2,

    COMBO_ID => 1,
    COMBO_TEXT => 0,

    COPIE_N => 0,

    LISTE_TXT =>0,
};

my $debug=0;
my $debug_file='';

my $profile='';

GetOptions("debug!"=>\$debug,
	   "debug-file=s"=>\$debug_file,
	   "profile=s"=>\$profile,
	   );

if($debug_file) {
    my $t=localtime();
    my $date=sprintf("%02d/%02d/%04d %02d:%02d",
		     $t->mday,$t->mon+1,$t->year+1900,$t->hour,$t->min);
    open(DBG,">>",$debug_file);
    print DBG "\n\n".('#' x 40)."\n# DEBUG - $date\n".('#' x 40)."\n\n";
    close(DBG);
    $debug=$debug_file;
}

if($debug) {
    set_debug($debug);
    debug "DEBUG MODE";
    print "DEBUG ==> ".AMC::Basic::debug_file()."\n";
}

($e_volume,$e_vdirectories,undef) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
}

my $glade_xml=__FILE__;
$glade_xml =~ s/\.p[ml]$/.glade/i;

my $home_dir=Glib::get_home_dir();

my $o_file='';
my $o_dir=$home_dir.'/.AMC.d';
my $state_file="$o_dir/state.xml";

#chomp(my $encodage_systeme=eval { `locale charmap` });
my $encodage_systeme=langinfo(CODESET());
$encodage_systeme='UTF-8' if(!$encodage_systeme);

sub hex_color {
    my $s=shift;
    return(Gtk2::Gdk::Color->parse($s)->to_string());
}

my %w=();
my %o_defaut=('pdf_viewer'=>['commande',
			     'evince','acroread','gpdf','xpdf',
			     ],
	      'img_viewer'=>['commande',
			     'eog','ristretto',
			     ],
	      'csv_viewer'=>['commande',
			     'gnumeric','kspread','oocalc',
			     ],
	      'ods_viewer'=>['commande',
			     'oocalc',
			     ],
	      'xml_viewer'=>['commande',
			     'gedit','kedit','mousepad',
			     ],
	      'tex_editor'=>['commande',
			     'texmaker','kile','emacs','gedit','mousepad',
			     ],
	      'html_browser'=>['commande',
			       'sensible-browser %u','firefox %u','galeon %u','konqueror %u','dillo %u',
			       ],
	      'dir_opener'=>['commande',
			     'nautilus --no-desktop file://%d',
			     'Thunar %d',
			     'konqueror file://%d',
			     ],
	      'print_command_pdf'=>['commande',
				    'cupsdoprint %f','lpr %f',
				    ],
	      'rep_projets'=>$home_dir.'/Projets-QCM',
	      'rep_modeles'=>'/usr/share/doc/auto-multiple-choice/exemples',
	      'seuil_eqm'=>3.0,
	      'seuil_sens'=>8.0,
	      'saisie_dpi'=>150,
	      'n_procs'=>0,
	      'delimiteur_decimal'=>',',
	      'defaut_encodage_liste'=>'UTF-8',
	      'encodage_interne'=>'UTF-8',
	      'defaut_encodage_csv'=>'UTF-8',
	      'encodage_latex'=>'',
	      'defaut_moteur_latex_b'=>'pdflatex',
	      'defaut_seuil'=>0.15,
	      'taille_max_correction'=>'1000x1500',
	      'qualite_correction'=>'150',
	      'conserve_taille'=>1,
	      'methode_impression'=>'CUPS',
	      'imprimante'=>'',
	      'options_impression'=>{'sides'=>'two-sided-long-edge',
				     'number-up'=>1,
				     'repertoire'=>'/tmp',
				     },
	      'manuel_image_type'=>'xpm',
	      'assoc_ncols'=>4,
	      'tolerance_marque_inf'=>0.2,
	      'tolerance_marque_sup'=>0.2,
	      'moteur_mep'=>'auto',

	      'symboles_trait'=>2,
	      'symboles_indicatives'=>'',
	      'symbole_0_0_type'=>'none',
	      'symbole_0_0_color'=>hex_color('black'),
	      'symbole_0_1_type'=>'circle',
	      'symbole_0_1_color'=>hex_color('red'),
	      'symbole_1_0_type'=>'mark',
	      'symbole_1_0_color'=>hex_color('red'),
	      'symbole_1_1_type'=>'mark',
	      'symbole_1_1_color'=>hex_color('blue'),
	      
	      'annote_ps_nl'=>60,
	      'annote_ecart'=>5.5,
	      );

my %projet_defaut=('texsrc'=>'',
		   'mep'=>'mep',
		   'cr'=>'cr',
		   'listeetudiants'=>'',
		   'notes'=>'notes.xml',
		   'seuil'=>'',
		   'encodage_csv'=>'',
		   'encodage_liste'=>'',
		   'maj_bareme'=>1,
		   'fichbareme'=>'bareme.xml',
		   'docs'=>['sujet.pdf','corrige.pdf','calage.pdf'],
		   
		   'modele_regroupement'=>'',
		   'regroupement_compose'=>'',

		   'note_max'=>20,
		   'note_grain'=>"0,5",
		   'note_arrondi'=>'inf',

		   'liste_key'=>'',
		   'association'=>'association.xml',
		   'assoc_code'=>'',

		   'moteur_latex_b'=>'',


		   'nom_examen'=>'',
		   'code_examen'=>'',

		   'nombre_copies'=>0,
	    
		   '_modifie'=>1,
		   
		   'format_export'=>'CSV',
		   'export_csv_separateur'=>",",

		   'annote_position'=>'marge',
		   );

my $mep_saved='mep.storable';
my $an_saved='an.storable';

my %o=();
my %state=();

# toutes les commandes prevues sont-elles accessibles ? Si non, on
# avertit l'utilisateur

sub test_commandes {
    my @pasbon=();
    for my $c (grep { /_(viewer|editor|opener)$/ } keys(%o)) {
	my $nc=$o{$c};
	$nc =~ s/\s.*//;
	push @pasbon,$nc if(!commande_accessible($nc));
    }
    if(@pasbon) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'warning','ok',
			      "Certaines commandes prévues pour l'ouverture de documents ne sont pas accessibles : ".join(", ",map { "<b>$_</b>"; } @pasbon).". Vérifiez que les commandes sont les bonnes et que les programmes correspondants sont bien installés. Vous pouvez aussi modifier les commandes à utiliser en sélectionnant <i>Préférences</i> dans le menu <i>Édition</i>.");
	$dialog->run;
	$dialog->destroy;
    }
}

if(! -d $o_dir) {
    mkdir($o_dir) or die "Impossible de creer $o_dir : $!";

    # changement organisation des fichiers config generale (<=0.254)

    if(-f $home_dir.'/.AMC.xml') {
	debug "Deplacement de l'ancien fichier de config generale";
	move($home_dir.'/.AMC.xml',$o_dir."/cf.default.xml");
    }
}

# lecture/ecriture des fichiers de preferences

sub pref_xx_lit {
    my ($fichier)=@_;
    if((! -f $fichier) || -z $fichier) {
	return();
    } else {
	return(%{XMLin($fichier,SuppressEmpty => '')});
    }
}

sub pref_xx_ecrit {
    my ($data,$key,$fichier)=@_;
    if(open my $fh,">:encoding(utf-8)",$fichier) {
	XMLout($data,
	       "XMLDecl"=>'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
	       "RootName"=>$key,'NoAttr'=>1,
	       "OutputFile" => $fh,
	       );
	close $fh;
	return(0);
    } else {
	return(1);
    }
}

# lecture etat...

sub sauve_state {
    if($state{'_modifie'}) {
	debug "Sauvegarde de l'etat...";
	
	if(pref_xx_ecrit(\%state,'AMCState',$state_file)) {
	    my $dialog = Gtk2::MessageDialog
		->new($w{'main_window'},
		      'destroy-with-parent',
		      'error','ok',
		      "Erreur à l'ecriture du fichier d'état %s : %s",$state_file,$!);
	    $dialog->run;
	    $dialog->destroy;      
	} else {
	    $state{'_modifie'}=0;
	}
    }
}

if(-r $state_file) {
    %state=pref_xx_lit($state_file);
}

$state{'_modifie'}=0;

if(!$state{'profile'}) {
    $state{'profile'}='default';
    $state{'_modifie'}=1;
}

if($profile && $profile ne $state{'profile'}) {
    $state{'profile'}=$profile;
    $state{'_modifie'}=1;
}

sauve_state();

debug "Profile : $state{'profile'}";

$o_file=$o_dir."/cf.".$state{'profile'}.".xml";

# lecture options ...

if(-r $o_file) {
    %o=pref_xx_lit($o_file);
}

for my $k (keys %o_defaut) {
    if(! exists($o{$k})) {
	if(ref($o_defaut{$k}) eq 'ARRAY') {
	    my ($type,@valeurs)=@{$o_defaut{$k}};
	    if($type eq 'commande') {
	      UC: for my $c (@valeurs) {
		  if(commande_accessible($c)) {
		      $o{$k}=$c;
		      last UC;
		  }
	      }
		$o{$k}=$valeurs[0] if(!$o{$k});
	    } else {
		debug "ERR: Type d'option inconnu : $type";
	    }
	} elsif(ref($o_defaut{$k}) eq 'HASH') {
	    $o{$k}={%{$o_defaut{$k}}};
	} else {
	    $o{$k}=$o_defaut{$k};
	    $o{$k}=$encodage_systeme if($k =~ /^encodage_/ && !$o{$k});
	}
	debug "Nouveau parametre global : $k = $o{$k}" if($o{$k});
    } else {
	if(ref($o_defaut{$k}) eq 'HASH') {
	    for my $kk (keys %{$o_defaut{$k}}) {
		if(! exists($o{$k}->{$kk})) {
		    $o{$k}->{$kk}=$o_defaut{$k}->{$kk};
		    debug "Nouveau sous-parametre global : $k/$kk = $o{$k}->{$kk}";
		}
	    }
	}
    }

}

$o{'_modifie'}=0;

# options passees en defaut_ entre version 0.226 et version 0.227

for(qw/encodage_liste encodage_csv/) {
    if($o{"$_"} && ! $o{"defaut_$_"}) {
	$o{"defaut_$_"}=$o{"$_"};
	$o{'_modifie'}=1;
    }
}

# XML::Writer utilise dans Association.pm n'accepte rien d'autre...
if($o{'encodage_interne'} ne 'UTF-8') {
    $o{'encodage_interne'}='UTF-8';
    $o{'_modifie'}=1;
}

# creation du repertoire si besoin (sinon la conf peut etre
# perturbee lors de Edition/Parametres)

mkdir($o{'rep_projets'}) if(-d $o{'rep_projets'});
    
###

my %projet=();

sub bon_encodage {
    my ($type)=@_;
    return($projet{'options'}->{"encodage_$type"}
	   || $o{"defaut_encodage_$type"}
	   || $o{"encodage_$type"}
	   || $o_defaut{"defaut_encodage_$type"}
	   || $o_defaut{"encodage_$type"}
	   || "UTF-8");
}

sub absolu {
    my $f=shift;
    return($f) if(!defined($f));
    return(proj2abs({'%PROJET'=>$o{'rep_projets'}."/".$projet{'nom'},
		     '%PROJETS'=>$o{'rep_projets'},
		     '%HOME',$home_dir,
		     ''=>'%PROJET',
		 },
		    $f));
}

sub relatif {
    my $f=shift;
    return($f) if(!defined($f));
    return(abs2proj({'%PROJET'=>$o{'rep_projets'}."/".$projet{'nom'},
		     '%PROJETS'=>$o{'rep_projets'},
		     '%HOME',$home_dir,
		     ''=>'%PROJET',
		 },$f));
}

sub id2file {
    my ($id,$prefix,$extension)=(@_);
    $id =~ s/\+//g;
    $id =~ s/\//-/g;
    return(absolu($projet{'options'}->{'cr'})."/$prefix-$id.$extension");
}

sub is_local {
    my ($f,$proj)=@_;
    my $prefix=$o{'rep_projets'}."/";
    $prefix .= $projet{'nom'}."/" if($proj);
    if(defined($f)) {
	return($f !~ /^[\/%]/ 
	       || $f =~ /^$prefix/
	       || $f =~ /[\%]PROJET\//);
    } else {
	return('');
    }
}

sub fich_options {
    my $nom=shift;
    return $o{'rep_projets'}."/$nom/options.xml";
}

sub moteur_latex {
    my $m=$projet{'options'}->{'moteur_latex_b'};
    $m=$o{'defaut_moteur_latex_b'} if(!$m);
    $m=$o_defaut{'defaut_moteur_latex_b'} if(!$m);
    return($m);
}

$gui=Gtk2::GladeXML->new($glade_xml,'main_window');

for(qw/onglets_projet preparation_etats documents_tree main_window mep_tree edition_latex
    onglet_notation onglet_saisie
    log_general commande avancement
    menu_debug menu_outils
    liste diag_tree inconnu_tree diag_result
    maj_bareme correc_tree correction_result regroupement_corriges
    options_CSV options_ods
    /) {
    $w{$_}=$gui->get_widget($_);
}

$w{'commande'}->hide();

sub debug_set {
    $debug=$w{'menu_debug'}->get_active;
    debug "DEBUG MODE : OFF" if(!$debug);
    set_debug($debug);
    debug "DEBUG MODE : ON" if($debug);
    if($debug) {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'info','ok',
		  "Passage en mode débogage. Les informations de débogage de cette session seront disponibles dans le fichier ".AMC::Basic::debug_file());
	$dialog->run;
	$dialog->destroy;
    }
}

$w{'menu_debug'}->set_active($debug);

###

sub dialogue_apprentissage {
    my ($key,@oo)=@_;
    if(!$state{'apprentissage'}->{$key}) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'info',
			      'ok',
			      @oo);

	my $garde=Gtk2::CheckButton->new("Conserver ce message la prochaine fois");
	$garde->set_active(0);
	$garde->can_focus(0);

	$dialog->get_content_area()->add($garde);
	$dialog->show_all();
	
	$dialog->run;

	if(!$garde->get_active()) {
	    debug "Apprentissage : $key";
	    $state{'apprentissage'}->{$key}=1;
	    $state{'_modifie'}=1;
	    sauve_state();
	}

	$dialog->destroy;
	
    }
}

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

### COPIES

$copies_store = Gtk2::ListStore->new ('Glib::String');


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
				    'Glib::String', 
				    'Glib::String');

$w{'diag_tree'}->set_model($diag_store);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("identifiant",
						     $renderer,
						     text=> DIAG_ID,
						     'background'=> DIAG_ID_BACK);
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
    my @texte=(@_);
    my $cs=Gtk2::ListStore->new ('Glib::String','Glib::String');
    my $k;
    my $t;
    while(($k,$t)=splice(@texte,0,2)) {
	$cs->set($cs->append,
		 COMBO_ID,$k,
		 COMBO_TEXT,$t);
    }
    return($cs);
}

# rajouter a partir de Encode::Supported
my $encodages=[{qw/inputenc latin1 iso ISO-8859-1/,'txt'=>'ISO-8859-1 (Europe occidentale)'},
	       {qw/inputenc latin2 iso ISO-8859-2/,'txt'=>'ISO-8859-2 (Europe centrale)'},
	       {qw/inputenc latin3 iso ISO-8859-3/,'txt'=>'ISO-8859-3 (Europe du sud)'},
	       {qw/inputenc latin4 iso ISO-8859-4/,'txt'=>'ISO-8859-4 (Europe du Nord)'},
	       {qw/inputenc latin5 iso ISO-8859-5/,'txt'=>'ISO-8859-5 (Cyrillique)'},
	       {qw/inputenc latin9 iso ISO-8859-9/,'txt'=>'ISO-8859-9 (Turc)'},
	       {qw/inputenc latin10 iso ISO-8859-10/,'txt'=>'ISO-8859-10 (Nordique)'},
	       {qw/inputenc utf8 iso UTF-8/,'txt'=>'UTF-8 (Unicode)'},
	       {qw/inputenc cp1252 iso cp1252/,'txt'=>'Windows-1252',
		alias=>['Windows-1252','Windows']},
	       {qw/inputenc applemac iso MacRoman/,'txt'=>'Macintosh Europe occidentale'},
	       {qw/inputenc macce iso MacCentralEurRoman/,'txt'=>'Macintosh Europe centrale'},
	       ];

sub get_enc {
    my ($txt)=@_;
    for my $e (@$encodages) {
	return($e) if($e->{'inputenc'} =~ /^$txt$/i ||
		      $e->{'iso'} =~ /^$txt$/i);
	if($e->{'alias'}) {
	    for my $a (@{$e->{'alias'}}) {
		return($e) if($a =~ /^$txt$/i);
	    }
	}
    }
    return('');
}

my $cb_model_vide=cb_model(''=>'(aucun)');

my %cb_stores=(
	       'delimiteur_decimal'=>cb_model(',',', (virgule)',
					      '.','. (point)'),
	       'note_arrondi'=>cb_model('inf','inférieur',
					'normal','normal',
					'sup','supérieur'),
	       'methode_impression'=>cb_model('CUPS','CUPS',
					      'commande','par une commande',
					      'file'=>'dans des fichiers'),
	       'sides'=>cb_model('one-sided','Non',
				 'two-sided-long-edge','Grand côté',
				 'two-sided-short-edge','Petit côté'),
	       'encodage_latex'=>cb_model(map { $_->{'iso'}=>$_->{'txt'} }
					  (@$encodages)),
	       'manuel_image_type'=>cb_model('ppm'=>'(aucun)',
					     'xpm'=>'XPM',
					     'gif'=>'GIF'),
	       'liste_key'=>$cb_model_vide,
	       'assoc_code'=>$cb_model_vide,
	       'format_export'=>cb_model('CSV'=>'CSV',
					 'ods'=>'OpenOffice'),
	       'export_csv_separateur'=>cb_model("TAB"=>'<TAB>',
						 ";"=>";",
						 ","=>","),
	       'moteur_mep'=>cb_model("auto"=>'découplé automatique',
				      "poppler"=>'direct'),
	       'annote_position'=>cb_model("none"=>'(aucune)',
					   "marge"=>'Dans la marge',
					   "case"=>'A côté des cases',
					   ),
	       );

my $symbole_type_cb=cb_model("none"=>"rien",
			     "circle"=>"cercle",
			     "mark"=>"croix",
			     "box"=>"carré",
			     );

for my $k (qw/0_0 0_1 1_0 1_1/) {
    $cb_stores{"symbole_".$k."_type"}=$symbole_type_cb;
}

my %extension_fichier=();

$diag_store->set_sort_func(DIAG_EQM,\&sort_num,DIAG_EQM);
$diag_store->set_sort_func(DIAG_DELTA,\&sort_num,DIAG_DELTA);

### export

sub maj_export {
    my $old_format=$projet{'options'}->{'format_export'};
    reprend_pref('export',$projet{'options'});

    debug "Format : ".$projet{'options'}->{'format_export'};

    for(qw/CSV ods/) {
	if($projet{'options'}->{'format_export'} eq $_) {
	    $w{'options_'.$_}->show;
	} else {
	    $w{'options_'.$_}->hide;
	}
    }
}

sub exporte {
    my $format=$projet{'options'}->{'format_export'};
    my @options=();
    my $ext=$extension_fichier{$format};
    if(!$ext) {
	$ext=lc($format);
    }
    my $output=absolu('export-notes.'.$ext);

    if($format eq 'CSV') {
	push @options,
	"--option-out","encodage=".bon_encodage('csv'),
	"--option-out","decimal=".$o{'delimiteur_decimal'},
	"--option-out","separateur=".$projet{'options'}->{'export_csv_separateur'};
    }
    if($format eq 'ods') {
	push @options,
	"--option-out","nom=".$projet{'options'}->{'nom_examen'},
	"--option-out","code=".$projet{'options'}->{'code_examen'};
    }
    
    commande('commande'=>[with_prog("AMC-export.pl"),
			  "--debug",debug_file(),
			  "--module",$format,
			  "--fich-notes",absolu($projet{'options'}->{'notes'}),
			  "--fich-assoc",absolu($projet{'options'}->{'association'}),
			  "--fich-noms",absolu($projet{'options'}->{'listeetudiants'}),
			  "--noms-encodage",bon_encodage('liste'),
			  "--output",$output,
			  @options
			  ],
	     'texte'=>'Export des notes...',
	     'progres.id'=>'export',
	     'progres.pulse'=>0.01,
	     'fin'=>sub {
		 if(-f $output) {
		     commande_parallele($o{$ext.'_viewer'},$output);
		 } else {
		     my $dialog = Gtk2::MessageDialog
			 ->new($w{'main_window'},
			       'destroy-with-parent',
			       'warning','ok',
			       "L'export des notes dans le fichier $output n'a sans doute pas fonctionné, car ce dernier fichier est inexistant...");
		     $dialog->run;
		     $dialog->destroy;
		 }
	     }
	     );
}

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
			debug "Visualisation $f...";
			commande_parallele($o{'img_viewer'},$f);
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

sub commande_parallele {
    my (@c)=(@_);
    if(commande_accessible($c[0])) {
	my $pid=fork();
	if($pid==0) {
	    debug "Commande // [$$] : ".join(" ",@c);
	    exec(@c) ||
		debug "Exec $$ defectueux";
	    exit(0);
	}
    } else {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      "La commande suivante n'a pas pu être exécutée : <b>$c[0]</b>. Peut-être est-ce dû à une mauvaise configuration ?");
	$dialog->run;
	$dialog->destroy;
	
    }
}

### Actions des menus

my $proj_store;

sub projet_nouveau {
    projet_charge('',1);
}

sub projet_charge {
    my (undef,$cree)=(@_);
    my @projs;
    
    mkdir($o{'rep_projets'}) if(-d $o{'rep_projets'});
    
    # construit la liste des projets existants

    if(-d $o{'rep_projets'}) {
	opendir(DIR, $o{'rep_projets'}) 
	    || die "Erreur a l'ouverture du repertoire ".$o{'rep_projets'}." : $!";
	my @f=map { decode("utf-8",$_); } readdir(DIR);
	debug "F:".join(',',map { $_.":".(-d $o{'rep_projets'}."/".$_) } @f);

	@projs = grep { ! /^\./ && -d $o{'rep_projets'}."/".$_ } @f;
	closedir DIR;
	debug "[".$o{'rep_projets'}."] P:".join(',',@projs);
    }

    if($#projs>=0 || $cree) {

	# fenetre pour demander le nom du projet
	
	my $gp=Gtk2::GladeXML->new($glade_xml,'choix_projet');
	$gp->signal_autoconnect_from_package('main');

	for(qw/choix_projet deja_la choix_projets_liste
	    projet_bouton_ouverture projet_bouton_creation
	    projet_nom projet_nouveau_syntaxe projet_nouveau/) {
	    $w{$_}=$gp->get_widget($_);
	}

	if($cree) {
	    $w{'projet_nouveau'}->show();
	    $w{'projet_bouton_creation'}->show();
	    $w{'projet_bouton_ouverture'}->hide();

	    $w{'deja_la'}->set_text("Projets déjà existants :");

	    $w{'choix_projet'}->set_focus($w{'projet_nom'});

	    $w{'projet_nom_style'} = $w{'projet_nom'}->get_modifier_style->copy;	}

	# mise a jour liste des projets dans la fenetre
	
	$proj_store = Gtk2::ListStore->new ('Glib::String',
					    'Gtk2::Gdk::Pixbuf');
	
	$w{'choix_projets_liste'}->set_model($proj_store);
	
	$w{'choix_projets_liste'}->set_text_column(PROJ_NOM);
	$w{'choix_projets_liste'}->set_pixbuf_column(PROJ_ICO);
	
	my $pb=$w{'main_window'}->render_icon ('gtk-open', 'menu');
	
	for (sort { $a cmp $b } @projs) {
	    $proj_store->set($proj_store->append,
			     PROJ_NOM,$_,
			     PROJ_ICO,$pb); 
	}

	# attendons l'action de l'utilisateur (fonctions projet_charge_*)...

    } else {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'info','ok',
		  "Vous n'avez aucun projet de QCM dans le répertoire %s !",$o{'rep_projets'});
	$dialog->run;
	$dialog->destroy;
	
    }
}

sub projet_charge_ok {

    # ouverture projet deja existant

    my $sel=$w{'choix_projets_liste'}->get_selected_items();
    my $proj;

    if($sel) {
	$proj=$proj_store->get($proj_store->get_iter($sel),PROJ_NOM);
    }

    $w{'choix_projet'}->destroy();

    projet_ouvre($proj) if($proj);
}

sub projet_nom_verif {
    my $nom=$w{'projet_nom'}->get_text();
    if($nom =~ s/[^a-zA-Z0-9._+:-]//g) {
	$w{'projet_nom'}->set_text($nom);
	$w{'projet_nouveau_syntaxe'}->show();

	for(qw/normal active/) {
	    $w{'projet_nom'}->modify_base($_,Gtk2::Gdk::Color->parse('#FFC0C0'));
	}
	Glib::Timeout->add (500, sub {
	    $w{'projet_nom'}->modify_style($w{'projet_nom_style'});
	    return 0;
	});
    }
}

sub projet_charge_nouveau {

    # creation nouveau projet

    my $proj=$w{'projet_nom'}->get_text();
    $w{'choix_projet'}->destroy();

    # existe deja ?

    if(-e $o{'rep_projets'}."/$proj") {

	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      sprintf("Le nom <b>%s</b> est déjà utilisé dans le répertoire des projets. Pour créer un nouveau projet, il faut choisir un autre nom.",$proj));
	$dialog->run;
	$dialog->destroy;      
	

    } else {

	if(projet_ouvre($proj,1)) {
	    projet_sauve();
	}

    }
}

sub projet_charge_non {
    $w{'choix_projet'}->destroy();
}

sub projet_sauve {
    debug "Sauvegarde du projet...";
    my $of=fich_options($projet{'nom'});
    my $po={%{$projet{'options'}}};

    for(qw/listeetudiants/) {
	$po->{$_}=relatif($po->{$_});
    }
    
    if(pref_xx_ecrit($po,'projetAMC',$of)) {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'error','ok',
		  "Erreur à l'ecriture du fichier d'options %s : %s",$of,$!);
	$dialog->run;
	$dialog->destroy;      
    } else {
	$projet{'options'}->{'_modifie'}=0;
    }
}

### Actions des boutons de la partie DOCUMENTS

sub doc_active {
    my $sel=$w{'documents_tree'}->get_selection()->get_selected_rows()->get_indices();
    #print "Active $sel...\n";
    my $f=absolu($projet{'options'}->{'docs'}->[$sel]);
    debug "Visualisation $f...";
    commande_parallele($o{'pdf_viewer'},$f);
}

sub mep_active {
    my $sel=$w{'mep_tree'}->get_selection()->get_selected_rows()->get_indices();
    my $id=($projet{'_mep_list'}->ids())[$sel];
    debug "Active MEP $sel : ID=$id...";
    my $f=$projet{'_mep_list'}->filename($id);
    debug "Visualisation $f...";
    commande_parallele($o{'xml_viewer'},$f);
}

sub fichiers_mep {
    my $md=absolu($projet{'options'}->{'mep'});
    opendir(MDIR, $md) || die "can't opendir $md: $!";
    my @meps = map { "$md/$_" } grep { /^mep.*xml$/ && -f "$md/$_" } readdir(MDIR);
    closedir MDIR;
    return(@meps);
}

sub mini {($_[0]<$_[1] ? $_[0] : $_[1])}

sub doc_maj {
    my $sur=0;
    if($projet{'_an_list'}->nombre()>0) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'warning','ok-cancel',
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
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'question','ok-cancel',
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
			  "--with",moteur_latex(),
			  "--debug",debug_file(),
			  "--out-sujet",absolu($projet{'options'}->{'docs'}->[0]),
			  "--out-corrige",absolu($projet{'options'}->{'docs'}->[1]),
			  "--out-calage",absolu($projet{'options'}->{'docs'}->[2]),
			  "--mode","s",
			  "--n-copies",$projet{'options'}->{'nombre_copies'},
			  absolu($projet{'options'}->{'texsrc'}),
			  "--prefix",absolu('%PROJET/'),
			  ],
	     'signal'=>2,
	     'texte'=>'Mise à jour des documents...',
	     'progres.id'=>'MAJ',
	     'progres.pulse'=>0.01,
	     'fin'=>sub { 
		 my $c=shift;
		 my @err=$c->erreurs();
		 if(@err) {
		     my $dialog = Gtk2::MessageDialog
			 ->new_with_markup($w{'main_window'},
					   'destroy-with-parent',
					   'error','ok',
					   "La compilation de votre source LaTeX a occasionné des erreurs. Vous devez corriger votre LaTeX pour obtenir une mise à jour des documents. Utilisez votre éditeur LaTeX ou la commande latex pour un diagnostic précis des erreurs.\n\n".join("\n",@err[0..mini(9,$#err)]).($#err>9 ? "\n\n<i>(Seules les dix premières erreurs ont été retranscrites)</i>": "") );
		     $dialog->run;
		     $dialog->destroy;
		 } else {
		     # verif que tout y est

		     my $ok=1;
		     for(0..2) {
			 $ok=0 if(! -f absolu($projet{'options'}->{'docs'}->[$_]));
		     }
		     dialogue_apprentissage('MAJ_DOCS_OK',
					    "Les documents de travail ont bien été générés. Vous pouvez y jeter un oeuil grâce à un double-clic sur les lignes de la liste correspondante. Si tout vous parraît correct, l'étape suivante est la détection des mises en page...") if($ok);
		 }

		 my $ap=($c->variable('ensemble') ? 'case' : 'marge');
		 $projet{'options'}->{'_modifie'}=1 
		     if($projet{'options'}->{'annote_position'} ne $ap);
		 $projet{'options'}->{'annote_position'}=$ap;

		 if($c->variable('ensemble') && $projet{'options'}->{'seuil'}<0.4) {
		     my $dialog = Gtk2::MessageDialog
			 ->new_with_markup($w{'main_window'},
					   'destroy-with-parent',
					   'question','yes-no',
					   sprintf("Votre sujet propose une feuille de réponses séparée. Dans ce cas, des lettres sont inscrites dans les cases à cocher. Pour une bonne détection des cases à cocher, il faut donc demander aux étudiants de remplir totalement les cases voulues, et aussi fixer le paramètre \"seuil de noirceur\" du projet à une valeur de l'ordre de 0.5. Pour l'instant, la valeur de ce paramètre est %.02f. Voulez-vous changer cette valeur en 0.5 ?",$projet{'options'}->{'seuil'}) );
		     my $reponse=$dialog->run;
		     $dialog->destroy;
		     if($reponse) {
			 $projet{'options'}->{'seuil'}=0.5;
			 $projet{'options'}->{'_modifie'}=1;
		     }
		 }
		 detecte_documents(); 
	     });
    
}

my $cups;
my $g_imprime;

sub nonnul {
    my $s=shift;
    $s =~ s/\000//g;
    return($s);
}

sub autre_imprimante {
    my $i=$w{'imprimante'}->get_model->get($w{'imprimante'}->get_active_iter,COMBO_ID);
    debug "Choix imprimante $i";
    my $ppd=$cups->getPPD($i);

    my %alias=();
    my %trouve=();

    debug "Recherche agrafage...";

  CHOIX: for my $i (qw/StapleLocation/) {
      my $oi=$ppd->getOption($i);
      
      $alias{$i}='agrafe';
      
      if(%$oi) {
	  $k=nonnul($oi->{'keyword'});
	  debug "$i -> KEYWORD $k";
	  my $ok=$o{'options_impression'}->{$k};
	  my @possibilites=(map { (nonnul($_->{'choice'}),
				   nonnul($_->{'text'})) }
			    (@{$oi->{'choices'}}));
	  my %ph=(@possibilites);
	  $cb_stores{'agrafe'}=cb_model(@possibilites);
	  $o{'options_impression'}->{$k}=nonnul($oi->{'defchoice'})
	      if(!$ok || !$ph{$ok});

	  $alias{$k}='agrafe';
	  $trouve{'agrafe'}=$k;

	  last CHOIX;
      } else {
	  $o{'options_impression'}->{$k}='';
      }
  }
    if(!$trouve{'agrafe'}) {
	debug "Agrafage impossible";

	$cb_stores{'agrafe'}=cb_model(''=>'(impossible)');
	$w{'imp_c_agrafe'}->set_model($cb_stores{'agrafe'});
    }

    transmet_pref($g_imprime,'imp',$o{'options_impression'},
		  \%alias);
}

sub sujet_impressions {

    if(! -f absolu($projet{'options'}->{'docs'}->[0])) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      "Vous n'avez pas de sujet à imprimer : veuillez vérifier votre source LaTeX et mettre à jour les documents de travail.");
	$dialog->run;
	$dialog->destroy;
	
	return();
    }

    if($projet{'_mep_list'}->nombre==0) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      "Aucune copie n'a été détectée sur le document de calage. Peut-être avez-vous oublié de calculer les mises en page ?");
	$dialog->run;
	$dialog->destroy;
	
	return();
    }

    debug "Choix des impressions...";

    $g_imprime=Gtk2::GladeXML->new($glade_xml,'choix_pages_impression');
    $g_imprime->signal_autoconnect_from_package('main');
    for(qw/choix_pages_impression arbre_choix_copies bloc_imprimante imprimante imp_c_agrafe bloc_fichier/) {
	$w{$_}=$g_imprime->get_widget($_);
    }

    if($o{'methode_impression'} eq 'CUPS') {
	$w{'bloc_imprimante'}->show();

	$cups=Net::CUPS->new();

	# les imprimantes :

	my @printers = $cups->getDestinations();
	debug "Imprimantes : ".join(' ',map { $_->getName() } @printers);
	my $p_model=cb_model(map { ($_->getName(),$_->getDescription() || $_->getName()) } @printers);
	$w{'imprimante'}->set_model($p_model);
	if(! $o{'imprimante'}) {
	    $o{'imprimante'}=$cups->getDestination()->getName();
	}
	my $i=model_id_to_iter($p_model,COMBO_ID,$o{'imprimante'});
	if($i) {
	    $w{'imprimante'}->set_active_iter($i);
	}

	# transmission

	transmet_pref($g_imprime,'imp',$o{'options_impression'});
    }

    if($o{'methode_impression'} eq 'file') {
	$w{'bloc_imprimante'}->hide();
	$w{'bloc_fichier'}->show();

	transmet_pref($g_imprime,'impf',$o{'options_impression'});
    }

    $copies_store->clear();
    for my $c ($projet{'_mep_list'}->etus()) {
	$copies_store->set($copies_store->append(),COPIE_N,$c);
    }

    $w{'arbre_choix_copies'}->set_model($copies_store);

    my $renderer=Gtk2::CellRendererText->new;
    my $column = Gtk2::TreeViewColumn->new_with_attributes ("copies",
							    $renderer,
							    text=> COPIE_N );
    $w{'arbre_choix_copies'}->append_column ($column);

    $w{'arbre_choix_copies'}->get_selection->set_mode("multiple");

}

sub sujet_impressions_cancel {
    
    if(get_debug()) {
	reprend_pref('imp',$o{'options_impression'});
	debug(Dumper($o{'options_impression'}));
    }

    $w{'choix_pages_impression'}->destroy;
}

sub sujet_impressions_ok {
    my $os='none';
    my @e=();

    for my $i ($w{'arbre_choix_copies'}->get_selection()->get_selected_rows() ) {
	push @e,$copies_store->get($copies_store->get_iter($i),COPIE_N);
    }

    if($o{'methode_impression'} eq 'CUPS') {
	my $i=$w{'imprimante'}->get_model->get($w{'imprimante'}->get_active_iter,COMBO_ID);
	if($i ne $o{'imprimante'}) {
	    $o{'imprimante'}=$i;
	    $o{'_modifie'}=1;
	}

	reprend_pref('imp',$o{'options_impression'});

	if($o{'options_impression'}->{'_modifie'}) {
	    $o{'_modifie'}=1;
	    delete $o{'options_impression'}->{'_modifie'};
	}

	$os=join(',',map { $_."=".$o{'options_impression'}->{$_} } 
		 grep { $o{'options_impression'}->{$_} }
		 (keys %{$o{'options_impression'}}) );

	debug("Options d'impression : $os");
    }

    if($o{'methode_impression'} eq 'file') {
	reprend_pref('impf',$o{'options_impression'});
	
	if($o{'options_impression'}->{'_modifie'}) {
	    $o{'_modifie'}=1;
	    delete $o{'options_impression'}->{'_modifie'};
	}

	if(!$o{'options_impression'}->{'repertoire'}) {
	    debug "Impression fichier : pas de destionation...";
	    $o{'options_impression'}->{'repertoire'}='';
	} else {
	    mkdir($o{'options_impression'}->{'repertoire'})
		if(! -e $o{'options_impression'}->{'repertoire'});
	}
    }

    $w{'choix_pages_impression'}->destroy;
    
    debug "Impression : ".join(",",@e);

    my $fh=File::Temp->new(TEMPLATE => "nums-XXXXXX",
			   TMPDIR => 1,
			   UNLINK=> 1);
    print $fh join("\n",@e)."\n";
    $fh->seek( 0, SEEK_END );

    commande('commande'=>[with_prog("AMC-imprime.pl"),
			  "--methode",$o{'methode_impression'},
			  "--imprimante",$o{'imprimante'},
			  "--options",$os,
			  "--output",$o{'options_impression'}->{'repertoire'}."/copie-%e.pdf",
			  "--print-command",$o{'print_command_pdf'},
			  "--sujet",absolu($projet{'options'}->{'docs'}->[0]),
			  "--mep",absolu($projet{'options'}->{'mep'}),
			  "--progression-id",'impression',
			  "--progression",1,
			  "--debug",debug_file(),
			  "--fich-numeros",$fh->filename,
			  ],
	     'signal'=>2,
	     'texte'=>'Impression copie par copie...',
	     'progres.id'=>'impression',
	     'o'=>{'fh'=>$fh},
	     'fin'=>sub {
		 my $c=shift;
		 close($c->{'o'}->{'fh'});
	     },

	     );
}

sub calcule_mep {
    # on efface les anciennes MEP
    my @meps=fichiers_mep();
    unlink @meps;
    # on recalcule...
    commande('commande'=>[with_prog("AMC-prepare.pl"),
			  "--with",moteur_latex(),
			  "--raster",$o{'moteur_mep'},
			  "--debug",debug_file(),
			  "--calage",absolu($projet{'options'}->{'docs'}->[2]),
			  "--progression-id",'MEP',
			  "--progression",1,
			  "--n-procs",$o{'n_procs'},
			  "--mode","m",
			  absolu($projet{'options'}->{'texsrc'}),
			  "--mep",absolu($projet{'options'}->{'mep'}),
			  ],
	     'texte'=>'Calcul des mises en page...',
	     'progres.id'=>'MEP',
	     'fin'=>sub { 
		 detecte_mep();
		 if($projet{'_mep_list'}->nombre()<1) {
		     # avertissement...
		     my $dialog = Gtk2::MessageDialog
			 ->new_with_markup($w{'main_window'},
					   'destroy-with-parent',
					   'error', # message type
					   'ok', # which set of buttons?
					   "Aucune mise en page n'a été fabriquée. <b>Ne faites pas passer l'examen</b> avant d'avoir réglé le problème, sinon vous ne pourrez pas utiliser AMC pour la correction.");
		     $dialog->run;
		     $dialog->destroy;
		     
		 } else {
		     dialogue_apprentissage('MAJ_MEP_OK',
					    "Les mises en page sont maintenant détectées. Vous pouvez vérifier que tout est correct en ouvrant la fenêtre de saisie manuelle (dans l' onglet <i>Saisie</i>) et en navigant dans les pages du sujet pour vérifier que les cases à cocher sont bien marquées en rouge à la bonne position (mais attention à ne pas cliquer dans ces cases). Vous pouvez ensuite passer à l'impression des copies et faire passer l'examen.");
		 }
	     });
}

### Actions des boutons de la partie SAISIE

sub saisie_manuelle {
    if($projet{'_mep_list'}->nombre()>0) {
	my $gm=AMC::Gui::Manuel::new('cr-dir'=>absolu($projet{'options'}->{'cr'}),
				     'mep-dir'=>absolu($projet{'options'}->{'mep'}),
				     'mep-data'=>$projet{'_mep_list'},
				     'an-data'=>$projet{'_an_list'},
				     'liste'=>absolu($projet{'options'}->{'listeetudiants'}),
				     'sujet'=>absolu($projet{'options'}->{'docs'}->[0]),
				     'etud'=>'',
				     'dpi'=>$o{'saisie_dpi'},
				     'seuil'=>$projet{'options'}->{'seuil'},
				     'seuil_sens'=>$o{'seuil_sens'},
				     'seuil_eqm'=>$o{'seuil_eqm'},
				     'global'=>0,
				     'encodage_interne'=>$o{'encodage_interne'},
				     'encodage_liste'=>bon_encodage('liste'),
				     'image_type'=>$o{'manuel_image_type'},
				     'retient_m'=>1,
				     'en_quittant'=>\&detecte_analyse,
				     );
    } else {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      "Aucune mise en page n'est disponible pour ce projet. Veuillez utiliser le bouton <i>calculer les mises en page</i> de l'onglet <i>préparation</i> avant la saisie manuelle.");
	$dialog->run;
	$dialog->destroy;      
    }
}

sub saisie_automatique {
    my $gsa=Gtk2::GladeXML->new($glade_xml,'saisie_auto');
    $gsa->signal_autoconnect_from_package('main');
    for(qw/saisie_auto copie_scans/) {
	$w{$_}=$gsa->get_widget($_);
    }
}

sub saisie_auto_annule {
    $w{'saisie_auto'}->destroy();
}

sub saisie_auto_ok {
    my @f=$w{'saisie_auto'}->get_filenames();
    my $copie=$w{'copie_scans'}->get_active();
    debug "Scans : ".join(',',@f);
    $w{'saisie_auto'}->destroy();

    # copie eventuelle dans le repertoire projet

    if($copie) {
	my @fl=();
	my $c=0;
	for my $fich (@f) {
	    my ($fxa,$fxb,$fb) = splitpath($fich);
	    my $dest=absolu("scans/".$fb);
	    if(copy($fich,$dest)) {
		push @fl,$dest; 
		$c++;
	    } else {
		push @fl,$fich;
	    }
	}
	debug "Copie des fichiers scan : ".$c."/".(1+$#f);
	@f=@fl;
    }

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
			  "--debug",debug_file(),
			  "--binaire",
			  "--seuil-coche",$projet{'options'}->{'seuil'},
			  "--tol-marque",$o{'tolerance_marque_inf'}.','.$o{'tolerance_marque_sup'},
			  "--progression-id",'analyse',
			  "--progression",1,
			  "--n-procs",$o{'n_procs'},
			  "--mep",absolu($projet{'options'}->{'mep'}),
			  "--mep-saved",absolu($mep_saved),
			  "--projet",absolu('%PROJET/'),
			  "--cr",absolu($projet{'options'}->{'cr'}),
			  "--liste-fichiers",$fh->filename,
			  ],
	     'signal'=>2,
	     'texte'=>'Saisie automatique...',
	     'progres.id'=>'analyse',
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
		 detecte_analyse('erreurs'=>\@fe,'apprend'=>1);
	     }
	     );
    
}

sub valide_liste {
    my (%oo)=@_;
    debug "* valide_liste";

    my $fl=$w{'liste'}->get_filename();

    my $l=AMC::NamesFile::new($fl,
			      'encodage'=>bon_encodage('liste'),
			      );
    my ($err,$errlig)=$l->errors();

    if($err) {
	if(!$oo{'noinfo'}) {
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'error','ok',
				  "Le fichier choisi ne convient pas : $err erreurs détectées, la première en ligne $errlig.");
	    $dialog->run;
	    $dialog->destroy;
	}
	$cb_stores{'liste_key'}=$cb_model_vide;
    } else {
	# ok
	if(!$oo{'nomodif'}) {
	    $projet{'options'}->{'listeetudiants'}=relatif($fl);
	    $projet{'options'}->{'_modifie'}=1;
	}
	# transmission liste des en-tetes
	my @keys=$l->keys;
	debug "cles primaires : ".join(",",@keys);
	$cb_stores{'liste_key'}=cb_model('','(aucun)',
					 map { ($_,$_) } 
					 sort { $a cmp $b } (@keys));
    }
    transmet_pref($gui,'pref_assoc',$projet{'options'},{},{'liste_key'=>1});
}

### Actions des boutons de la partie NOTATION

sub associe {
    if(-f absolu($projet{'options'}->{'listeetudiants'})) {
	my $ga=AMC::Gui::Association::new('cr'=>absolu($projet{'options'}->{'cr'}),
					  'liste'=>absolu($projet{'options'}->{'listeetudiants'}),
					  'liste_key'=>$projet{'options'}->{'liste_key'},
					  'fichier-liens'=>absolu($projet{'options'}->{'association'}),
					  'global'=>0,
					  'assoc-ncols'=>$o{'assoc_ncols'},
					  'encodage_liste'=>bon_encodage('liste'),
					  'encodage_interne'=>$o{'encodage_interne'},
					  );
	if($ga->{'erreur'}) {
	    my $dialog = Gtk2::MessageDialog
		->new($w{'main_window'},
		      'destroy-with-parent',
		      'error','ok',
		      $ga->{'erreur'});
	    $dialog->run;
	    $dialog->destroy;
	}
    } else {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'info','ok',
		  "Avant d'associer les noms aux copies, il faut indiquer un fichier de liste des étudiants dans l'onglet « Saisie ».");
	$dialog->run;
	$dialog->destroy;
	
    }
}

sub associe_auto {
    if(! -s absolu($projet{'options'}->{'listeetudiants'})) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      "Il faut tout d'abord choisir un fichier contenant la liste des étudiants");
	$dialog->run;
	$dialog->destroy;
    } elsif(!$projet{'options'}->{'liste_key'}) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      "Aucun identifiant n'a été choisi parmi les titres de colonnes du fichier contenant la liste des étudiants. Il faut en choisir un avant de pouvoir effectuer une association automatique.");
	$dialog->run;
	$dialog->destroy;
    } elsif(! $projet{'options'}->{'assoc_code'}) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      "Aucun code n'a été choisi parmi les codes (éventuellement fabriqués avec la commande LaTeX \\AMCcode) disponibles. Il faut en choisir un avant de pouvoir effectuer une association automatique.");
	$dialog->run;
	$dialog->destroy;
    } else {
	commande('commande'=>[with_prog("AMC-association-auto.pl"),
			      "--notes",absolu($projet{'options'}->{'notes'}),
			      "--notes-id",$projet{'options'}->{'assoc_code'},
			      "--liste",absolu($projet{'options'}->{'listeetudiants'}),
			      "--liste-key",$projet{'options'}->{'liste_key'},
			      "--encodage-liste",bon_encodage('liste'),
			      "--assoc",absolu($projet{'options'}->{'association'}),
			      "--encodage-interne",$o{'encodage_interne'},
			      "--debug",debug_file(),
			      ],
		 'texte'=>'Association automatique...',
		 'fin'=>sub {
		     assoc_resultat();
		 },
		 );
    }
}

sub assoc_resultat {
}

sub valide_cb {
    my ($var,$cb)=@_;
    my $cbc=$cb->get_active();
    if($cbc xor $$var) {
	$$var=$cbc;
	$projet{'options'}->{'_modifie'}=1;
	debug "* valide_cb";
    }
}

sub valide_options_correction {
    my ($ww,$o)=@_;
    my $name=$ww->get_name();
    debug "Valide OC depuis $name";
    valide_cb(\$projet{'options'}->{$name},$w{$name});
}

sub valide_options_notation {
    reprend_pref('notation',$projet{'options'});
}

sub valide_options_association {
    reprend_pref('pref_assoc',$projet{'options'});
}

sub valide_options_preparation {
    reprend_pref('pref_prep',$projet{'options'});
}

sub voir_notes {
    if(-f absolu($projet{'options'}->{'notes'})) {
	my $n=AMC::Gui::Notes::new('fichier'=>absolu($projet{'options'}->{'notes'}));
    } else {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'info','ok',
		  "Les copies ne sont pas encore corrigées : veuillez d'abord utiliser le bouton « Corriger ».");
	$dialog->run;
	$dialog->destroy;
	
    }
}

sub noter {
    if($projet{'options'}->{'maj_bareme'}) {
	commande('commande'=>[with_prog("AMC-prepare.pl"),
			      "--n-copies",$projet{'options'}->{'nombre_copies'},
			      "--with",moteur_latex(),
			      "--debug",debug_file(),
			      "--progression-id",'bareme',
			      "--progression",1,
			      "--mode","b",
			      "--bareme",absolu($projet{'options'}->{'fichbareme'}),
			      absolu($projet{'options'}->{'texsrc'}),
			      ],
		 'texte'=>'Analyse du bareme...',
		 'fin'=>\&noter_calcul,
		 'progres.id'=>'bareme');
    } else {
	noter_calcul();
    }
}

sub noter_calcul {
    commande('commande'=>[with_prog("AMC-note.pl"),
			  "--debug",debug_file(),
			  "--cr",absolu($projet{'options'}->{'cr'}),
			  "--an-saved",absolu($an_saved),
			  "--bareme",absolu($projet{'options'}->{'fichbareme'}),
			  "-o",absolu($projet{'options'}->{'notes'}),
			  "--seuil",$projet{'options'}->{'seuil'},
			  
			  "--grain",$projet{'options'}->{'note_grain'},
			  "--arrondi",$projet{'options'}->{'note_arrondi'},
			  "--notemax",$projet{'options'}->{'note_max'},
			  
			  "--encodage-interne",$o{'encodage_interne'},
			  "--progression-id",'notation',
			  "--progression",1,
			  ],
	     'signal'=>2,
	     'texte'=>'Calcul des notes...',
	     'progres.id'=>'notation',
	     'fin'=>sub {
		 noter_resultat();
	     },
	     );
}

sub noter_resultat {
    my $moy;
    my @codes=();
    if(-s absolu($projet{'options'}->{'notes'})) {
	debug "* lecture notes";
	my $notes=eval { XMLin(absolu($projet{'options'}->{'notes'}),
			       'ForceArray'=>1,
			       'KeyAttr'=>['id'],
			       ) };
	if($notes) {
	    # recuperation de la moyenne
	    $moy=sprintf("%.02f",$notes->{'moyenne'}->[0]);
	    $w{'correction_result'}->set_markup("<span foreground=\"darkgreen\">Moyenne : $moy</span>");
	    # recuperation des codes disponibles
	    @codes=(keys %{$notes->{'code'}});
	} else {
	    $w{'correction_result'}->set_markup("<span foreground=\"red\">Notes illisibles</span>");
	}
	debug "Codes : ".join(',',@codes);
    } else {
	$w{'correction_result'}->set_markup("<span foreground=\"red\">Aucun calcul de notes</span>");
	push @codes,$projet{'options'}->{'assoc_code'}
	if($projet{'options'}->{'assoc_code'});
    }
    $cb_stores{'assoc_code'}=cb_model(''=>'(aucun)',
				      map { $_=>$_ } 
				      sort { $a cmp $b } (@codes));
    transmet_pref($gui,'pref_assoc',$projet{'options'},{},{'assoc_code'=>1});
}

sub visualise_correc {
    my $sel=$w{'correc_tree'}->get_selection()->get_selected_rows();
    #print "Correc $sel $correc_store\n";
    my $f=$correc_store->get($correc_store->get_iter($sel),CORREC_FILE);
    debug "Visualisation $f...";
    commande_parallele($o{'img_viewer'},$f);
}

sub opt_symbole {
    my ($s)=@_;
    my $k=$s;
    my $type='none';
    my $color='red';

    $k =~ s/-/_/g;
    $type=$o{'symbole_'.$k.'_type'} if(defined($o{'symbole_'.$k.'_type'}));
    $color=$o{'symbole_'.$k.'_color'} if(defined($o{'symbole_'.$k.'_color'}));

    return("$s:$type/$color");
}

sub annote_copies {
    commande('commande'=>[with_prog("AMC-annote.pl"),
			  "--debug",debug_file(),
			  "--progression-id",'annote',
			  "--progression",1,
			  "--projet",absolu('%PROJET/'),
			  "--projets",absolu('%PROJETS/'),
			  "--cr",absolu($projet{'options'}->{'cr'}),
			  "--an-saved",absolu($an_saved),
			  "--notes",absolu($projet{'options'}->{'notes'}),
			  "--taille-max",$o{'taille_max_correction'},
			  "--bareme",absolu($projet{'options'}->{'fichbareme'}),
			  "--qualite",$o{'qualite_correction'},
			  "--line-width",$o{'symboles_trait'},

			  "--indicatives",$o{'symboles_indicatives'},
			  "--symbols",join(',',map { opt_symbole($_); } (qw/0-0 0-1 1-0 1-1/)), 
			  "--position",$projet{'options'}->{'annote_position'},
			  "--pointsize-nl",$o{'annote_ps_nl'},
			  "--ecart",$o{'annote_ecart'},
			  ],
	     'texte'=>'Annotation des copies...',
	     'progres.id'=>'annote',
	     'fin'=>sub { detecte_correc(); },
	     );
}

sub regroupement {

    valide_options_notation();

    commande('commande'=>[with_prog("AMC-regroupe.pl"),
			  "--debug",debug_file(),
			  ($projet{'options'}->{'regroupement_compose'} ? "--compose" : "--no-compose"),
			  "--cr",absolu($projet{'options'}->{'cr'}),
			  "--an-saved",absolu($an_saved),
			  "--mep",absolu($projet{'options'}->{'mep'}),
			  "--mep-saved",absolu($mep_saved),
			  "--tex-src",absolu($projet{'options'}->{'texsrc'}),
			  "--with",moteur_latex(),
			  "--n-copies",$projet{'options'}->{'nombre_copies'},
			  "--progression-id",'regroupe',
			  "--progression",1,
			  "--modele",$projet{'options'}->{'modele_regroupement'},
			  "--fich-assoc",absolu($projet{'options'}->{'association'}),
			  "--fich-noms",absolu($projet{'options'}->{'listeetudiants'}),
			  "--noms-encodage",bon_encodage('liste'),

			  ],
	     'signal'=>2,
	     'texte'=>'Regroupement des pages corrigées par étudiant...',
	     'progres.id'=>'regroupe',
	     );
}

sub regarde_regroupements {
    my $f=absolu($projet{'options'}->{'cr'})."/corrections/pdf";
    debug "Je vais voir $f";
    my $seq=0;
    my @c=map { $seq+=s/[%]d/$f/g;$_; } split(/\s+/,$o{'dir_opener'});
    push @c,$f if(!$seq);
    # nautilus attend des arguments dans l'encodage specifie par LANG & co.
    @c=map { encode($encodage_systeme,$_); } @c;

    commande_parallele(@c);
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

sub activate_doc {
    my $url='file:///usr/share/doc/auto-multiple-choice/html/auto-multiple-choice/index.html';

    my $seq=0;
    my @c=map { $seq+=s/[%]u/$url/g;$_; } split(/\s+/,$o{'html_browser'});
    push @c,$url if(!$seq);
    @c=map { encode($encodage_systeme,$_); } @c;
    
    commande_parallele(@c);
}

###

# mise a jour des zooms depuis le menu par ex.
sub activate_zoom_maj {
    if($projet{'_an_list'}->nombre()==0) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      "Aucune saisie automatique n'a été effectuée : il n'y a donc pas de zooms à reconstruire...");
	$dialog->run;
	$dialog->destroy;      
	return(0);
    }

    commande('commande'=>[with_prog("AMC-zooms.pl"),
			  "--debug",debug_file(),
			  "--projet",absolu('%PROJET/'),
			  "--projets",absolu('%PROJETS/'),
			  "--seuil",$projet{'options'}->{'seuil'},
			  "--n-procs",$o{'n_procs'},
			  "--an-saved",absolu($an_saved),
			  "--cr-dir",absolu($projet{'options'}->{'cr'}),
			  "--progression",1,
			  "--progression-id",'zooms',
			  ],
	     'texte'=>'Re-extraction des zooms...',
	     'progres.id'=>'zooms',
	     );
}

###

# transmet les preferences vers les widgets correspondants
sub transmet_pref {
    my ($gap,$prefixe,$h,$alias,$seulement)=@_;

    for my $t (keys %$h) {
	if(!$seulement || $seulement->{$t}) {
	my $ta=$t;
	$ta=$alias->{$t} if($alias->{$t});

	my $wp=$gap->get_widget($prefixe.'_x_'.$ta);
	if($wp) {
	    $w{$prefixe.'_x_'.$t}=$wp;
	    $wp->set_text($h->{$t});
	}
	$wp=$gap->get_widget($prefixe.'_f_'.$ta);
	if($wp) {
	    $w{$prefixe.'_f_'.$t}=$wp;
	    if($wp->get_action =~ /-folder$/i) {
		$wp->set_current_folder($h->{$t});
	    } else {
		$wp->set_filename($h->{$t});
	    }
	}
	$wp=$gap->get_widget($prefixe.'_v_'.$ta);
	if($wp) {
	    $w{$prefixe.'_v_'.$t}=$wp;
	    $wp->set_active($h->{$t});
	}
	$wp=$gap->get_widget($prefixe.'_s_'.$ta);
	if($wp) {
	    $w{$prefixe.'_s_'.$t}=$wp;
	    $wp->set_value($h->{$t});
	}
	$wp=$gap->get_widget($prefixe.'_col_'.$ta);
	if($wp) {
	    $w{$prefixe.'_col_'.$t}=$wp;
	    $wp->set_color(Gtk2::Gdk::Color->parse($h->{$t}));
	}
	$wp=$gap->get_widget($prefixe.'_cb_'.$ta);
	if($wp) {
	    $w{$prefixe.'_cb_'.$t}=$wp;
	    $wp->set_active($h->{$t});
	}
	$wp=$gap->get_widget($prefixe.'_c_'.$ta);
	if($wp) {
	    $w{$prefixe.'_c_'.$t}=$wp;
	    if($cb_stores{$ta}) {
		debug "CB_STORE($t) ALIAS $ta modifie";
		$wp->set_model($cb_stores{$ta});
		my $i=model_id_to_iter($wp->get_model,COMBO_ID,$h->{$t});
		if($i) {
		    debug("[$t] trouve $i",
			  " -> ".$cb_stores{$ta}->get($i,COMBO_TEXT));
		    $wp->set_active_iter($i);
		}
	    } else {
		debug "pas de CB_STORE pour $ta";
		$wp->set_active($h->{$t});
	    }
	}
	$wp=$gap->get_widget($prefixe.'_ce_'.$ta);
	if($wp) {
	    $w{$prefixe.'_ce_'.$t}=$wp;
	    if($cb_stores{$ta}) {
		debug "CB_STORE($t) ALIAS $ta modifie";
		$wp->set_model($cb_stores{$ta});
	    }
	    my $we=$wp->get_children();
	    $we->set_text($h->{$t});
	    $w{$prefixe.'_x_'.$t}=$we;
	}
	debug "Cle $t --> $ta : ".(defined($wp) ? "trouve widget $wp" : "RIEN");
    }}
}

# met a jour les preferences depuis les widgets correspondants
sub reprend_pref {
    my ($prefixe,$h,$oprefix)=@_;
    $h->{'_modifie'}=($h->{'_modifie'} ? 1 : '');

    for my $t (keys %$h) {
	my $tgui=$t;
	$tgui =~ s/$oprefix$// if($oprefix);
	my $n;
	my $wp=$w{$prefixe.'_x_'.$tgui};
	if($wp) {
	    $n=$wp->get_text();
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_f_'.$tgui};
	if($wp) {
	    if($wp->get_action =~ /-folder$/i) {
		if(-d $wp->get_filename()) {
		    $n=$wp->get_filename();
		} else {
		    $n=$wp->get_current_folder();
		}
	    } else {
		$n=$wp->get_filename();
	    }
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_v_'.$tgui};
	if($wp) {
	    $n=$wp->get_active();
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_s_'.$tgui};
	if($wp) {
	    $n=$wp->get_value();
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_col_'.$tgui};
	if($wp) {
	    $n=$wp->get_color()->to_string();
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_cb_'.$tgui};
	if($wp) {
	    $n=$wp->get_active();
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_c_'.$tgui};
	if($wp) {
	    if($wp->get_model) {
		if($wp->get_active_iter) {
		    $n=$wp->get_model->get($wp->get_active_iter,COMBO_ID);
		} else {
		    $n='';
		}
		#print "[$t] valeur=$n\n";
	    } else {
		$n=$wp->get_active();
	    }
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
    }
    
    debug "Modifications : $h->{'_modifie'}";
}

sub change_methode_impression {
    if($w{'pref_x_print_command_pdf'}) {
	my $m='';
	if($w{'pref_c_methode_impression'}->get_active_iter) {
	    $m=$w{'pref_c_methode_impression'}->get_model->get($w{'pref_c_methode_impression'}->get_active_iter,COMBO_ID);
	}
	$w{'pref_x_print_command_pdf'}->set_sensitive($m eq 'commande');
    }
}

sub edit_preferences {
    my $gap=Gtk2::GladeXML->new($glade_xml,'edit_preferences');

    for(qw/edit_preferences pref_projet_tous pref_projet_annonce pref_x_print_command_pdf pref_c_methode_impression symboles_tree/) {
	$w{$_}=$gap->get_widget($_);
    }

    $gap->signal_autoconnect_from_package('main');

    # tableau type/couleurs pour correction

    for my $t (grep { /^pref(_projet)?_[xfcv]_/ } (keys %w)) {
	delete $w{$t};
    }
    transmet_pref($gap,'pref',\%o);
    transmet_pref($gap,'pref_projet',$projet{'options'}) if($projet{'nom'});

    # projet ouvert -> ne pas changer localisation
    if($projet{'nom'}) {
	$w{'pref_f_rep_projets'}->set_sensitive(0);
	$w{'pref_projet_annonce'}->set_label('<i>Préférences du projet « <b>'.$projet{'nom'}.'</b> »</i>');
    } else {
	$w{'pref_projet_tous'}->set_sensitive(0);
	$w{'pref_projet_annonce'}->set_label('<i>Préférences du projet</i>');
    }

    change_methode_impression();
}

sub accepte_preferences {
    reprend_pref('pref',\%o);
    reprend_pref('pref_projet',$projet{'options'}) if($projet{'nom'});
    $w{'edit_preferences'}->destroy();

    sauve_pref_generales();

    test_commandes();

    if(defined($projet{'options'}->{'_modifie'})
       && $projet{'options'}->{'_modifie'} =~ /\bseuil\b/) {
	if($projet{'_an_list'}->nombre()>0) {
	    # mise a jour de la liste diagnostic
	    detecte_analyse('ids_m'=>[$projet{'_an_list'}->ids()]);

	    # recalcul des zooms ?
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'question','yes-no',
				  "Vous avez modifié le seuil de noirceur. Si vous avez déjà effectué une saisie automatique, les zooms fabriqués pour chaque copie ne sont plus correctement organisés. Voulez-vous les refabriquer ? Cela prend un peu de temps. Vous pouvez aussi les refabriquer plus tard grâce à l'action <i>re-extraire les zooms</i> du menu <i>Outils</i>.");
	    my $reponse=$dialog->run;
	    $dialog->destroy;      
	    
	    if($reponse eq 'yes') {
		activate_zoom_maj();	    
	    } 
	    
	}
    }
}

sub sauve_pref_generales {
    debug "Sauvegarde des preferences generales...";

    if(pref_xx_ecrit(\%o,'AMC',$o_file)) {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'error','ok',
		  "Erreur à l'ecriture du fichier d'options %s : %s",$o_file,$!);
	$dialog->run;
	$dialog->destroy;      
    } else {
	$o{'_modifie'}=0;
    }
}

sub annule_preferences {
    debug "Annule modifs preferences";
    $w{'edit_preferences'}->destroy();
}

sub file_maj {
    my $f=shift;
    if($f && -f $f) {
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
	my $f=absolu($projet{'options'}->{'docs'}->[$i]);
	$doc_store->set($doc_ligne[$i],DOC_MAJ,file_maj($f));
    }
}

sub detecte_mep {
    $w{'commande'}->show();
    $w{'avancement'}->set_text("Recherche des mises en page détectées...");
    $w{'avancement'}->set_fraction(0);
    Gtk2->main_iteration while ( Gtk2->events_pending );

    $projet{'_mep_list'}->maj('progres'=>sub {
	$w{'avancement'}->set_pulse_step(.02);
	$w{'avancement'}->pulse();
	Gtk2->main_iteration while ( Gtk2->events_pending );
    },
		   );

    $mep_store->clear();

    $w{'onglet_saisie'}->set_sensitive($projet{'_mep_list'}->nombre()>0);

    my $ii=0;
    for my $i ($projet{'_mep_list'}->ids()) {
	my $iter=$mep_store->append;
	$mep_store->set($iter,MEP_ID,$i,MEP_PAGE,$projet{'_mep_list'}->attr($i,'page'),MEP_MAJ,file_maj($projet{'_mep_list'}->filename($i)));

	$ii++;
	$w{'avancement'}->set_fraction($ii/$projet{'_mep_list'}->nombre());
	if($ii % 50 ==0) {
	    Gtk2->main_iteration while ( Gtk2->events_pending );
	}
    }

    $w{'avancement'}->set_text('');
    $w{'avancement'}->set_fraction(0);
    $w{'commande'}->hide();
    Gtk2->main_iteration while ( Gtk2->events_pending );
}

sub detecte_correc {
    my $cordir=absolu("cr/corrections/jpg");
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

    debug "Detection analyses / ".join(', ',map { $_."=".$oo{$_} } (keys %oo));

    $w{'commande'}->show();
    my $av_text=$w{'avancement'}->get_text();
    $w{'avancement'}->set_text("Recherche des analyses effectuées...");
    $w{'avancement'}->set_fraction(0) if(!$oo{'interne'});
    Gtk2->main_iteration while ( Gtk2->events_pending );

    my @ids_m;

    if($oo{'ids_m'}) {
	@ids_m=@{$oo{'ids_m'}};
    } else {
	@ids_m=$projet{'_an_list'}->maj('progres'=>sub {
	    $w{'avancement'}->set_pulse_step(.1);
	    $w{'avancement'}->pulse();
	    Gtk2->main_iteration while ( Gtk2->events_pending );
	},
					);
    }

    if($oo{'premier'}) {
	@ids_m=$projet{'_an_list'}->ids();
	$diag_store->clear;
    }

    debug "IDS_M : ".join(' ',@ids_m);

    $w{'onglet_notation'}->set_sensitive($projet{'_an_list'}->nombre()>0);
    detecte_correc() if($projet{'_an_list'}->nombre()>0);

    my $ii=0;

  UNID: for my $i (@ids_m) {
      my $iter='';

      $ii++;

      # a ete efface ?
      if(! $projet{'_an_list'}->existe($i)) {
	  debug "Efface $i";
	  $iter=model_id_to_iter($diag_store,DIAG_ID,$i);
	  if($iter) {
	      $diag_store->remove($iter);
	  } else {
	      debug "- introuvable";
	  }
      } else {

	  debug "ID=$i ::",Dumper($projet{'_an_list'}->{'dispos'}->{$i});
	  
	  # deja dans la liste ? sinon on rajoute...
	  
	  if(!$oo{'premier'}) {
	      $iter=model_id_to_iter($diag_store,DIAG_ID,$i);
	  }
	  $iter=$diag_store->append if(!$iter);
	  
	  my ($eqm,$eqm_coul)=$projet{'_an_list'}->mse_string($i,
							      $o{'seuil_eqm'},
							      'red');
	  my ($sens,$sens_coul)=$projet{'_an_list'}->sensibilite_string($i,$projet{'options'}->{'seuil'},
									$o{'seuil_sens'},
									'red');
	  
	  $diag_store->set($iter,
			   DIAG_ID,$i,
			   DIAG_ID_BACK,$projet{'_an_list'}->couleur($i),
			   DIAG_EQM,$eqm,
			   DIAG_EQM_BACK,$eqm_coul,
			   DIAG_MAJ,file_maj($projet{'_an_list'}->filename($i)),
			   DIAG_DELTA,$sens,
			   DIAG_DELTA_BACK,$sens_coul,
			   );
      }
	  
      $w{'avancement'}->set_fraction(0.9*$ii/(1+$#ids_m)) if(!$oo{'interne'});
      if($ii % 50 ==0) {
	  Gtk2->main_iteration while ( Gtk2->events_pending );
      }
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

    # resume

    my %r=$projet{'_mep_list'}->stats($projet{'_an_list'});
    my $tt='';
    if($r{'incomplet'}) {
	$tt=sprintf("Saisie de %d copie(s) complète(s) et <span foreground=\"red\">%d copie(s) incomplète(s)</span>",$r{'complet'},$r{'incomplet'});
    } else {
	$tt=sprintf("<span foreground=\"darkgreen\">Saisie de %d copie(s) complète(s)</span>",$r{'complet'});
    }
    $w{'diag_result'}->set_markup($tt);

    # ID manquants :

    for my $i (@{$r{'manque_id'}}) {
	my $iter=$inconnu_store->append;
	$inconnu_store->set($iter,
			    INCONNU_SCAN,'absent',
			    INCONNU_ID,$i);
    }
    

    $w{'avancement'}->set_text($av_text);
    $w{'avancement'}->set_fraction(0) if(!$oo{'interne'});
    $w{'commande'}->hide() if(!$oo{'interne'});
    Gtk2->main_iteration while ( Gtk2->events_pending );

    # dialogue apprentissage :

    if($oo{'apprend'}) {
	dialogue_apprentissage('SAISIE_AUTO',
			       "La saisie automatique de vos scans est maintenant terminée. "
			       .($r{'incomplet'}>0 ? sprintf("Elle n'est pas complète (il manque certaines pages pour %d copie(s)). ",$r{'incomplet'}) : '')
			       ."Vous pouvez analyser la qualité de la détection grâce à la valeur des indicateurs donnée dans la liste des analyses :"
			       ."\n"
			       ."- <b>EQM</b> représente l'écart de positionnement des quatre marques de coin. Une grande valeur signale une déformation anormale de la page."
			       ."\n"
			       ."- une grande valeur de <b>sensibilité</b> correspond à une situation dans laquelle le taux de remplissage de certaines cases est très proche du seuil défini."
			       ."\n"
			       ."Vous pouvez aussi observer le calage du scan (<i>page</i>) ainsi que les cases cochées ou non (<i>zooms</i>) en utilisant le menu déployé par un clic-droit sur chaque ligne du tableau <i>Diagnostic</i>."
			       );
    }

}

sub set_source_tex {
    my ($importe)=@_;

    importe_source() if($importe);
    valide_source_tex();
}

sub source_latex_montre_nom {
    my $dialog = Gtk2::MessageDialog
	->new($w{'main_window'},
	      'destroy-with-parent',
	      'info','ok',
	      "Le fichier LaTeX qui décrit le QCM de ce projet est situé à l'emplacement suivant :\n%s",
	      ($projet{'options'}->{'texsrc'} ? absolu($projet{'options'}->{'texsrc'}) : "(aucun fichier)" ));
    $dialog->run;
    $dialog->destroy;
}

sub valide_source_tex {
    $projet{'options'}->{'_modifie'}=1;
    debug "* valide_source_tex";
    $w{'preparation_etats'}->set_sensitive(-f absolu($projet{'options'}->{'texsrc'}));

    if(is_local($projet{'options'}->{'texsrc'})) {
	$w{'edition_latex'}->show();
    } else {
	$w{'edition_latex'}->hide();
    }

    detecte_documents();
}

my @modeles=();
my %modeles_i=();

sub charge_modeles {
    return if($#modeles>=0);
    opendir(DIR, $o{'rep_modeles'});
    my @ms = grep { /\.tex$/ && -f $o{'rep_modeles'}."/$_" } readdir(DIR);
    closedir DIR;
    for my $m (@ms) {
	debug "Fichier modele $m";
	my $d={'id'=>$m,
	       'fichier'=>$o{'rep_modeles'}."/$m",
	   };
	my $mt=$o{'rep_modeles'}."/$m";
	$mt =~ s/\.tex$/.txt/;
	if(-f $mt) {
	    open(DESC,"<:encoding(UTF-8)",$mt);
	  LIG: while(<DESC>) {
	      chomp;
	      s/\#.*//;
	      next LIG if(!$_);
	      $d->{'desc'}.=$_;
	  }
	} else {
	    $d->{'desc'}='(aucune description)';
	}
	#print "MOD : $m\n";
	push @modeles,$d;
    }
}

sub n_fich {
    my ($dir)=@_;

    opendir(NFICH,$dir) or return(0);
    my @f=grep { ! /^\./ } readdir(NFICH);
    closedir(NFICH);

    return(1+$#f,"$dir/$f[0]");
}

sub source_latex_choisir {

    # fenetre de choix du source latex

    my $gap=Gtk2::GladeXML->new($glade_xml,'source_latex_dialog');

    my $dialog=$gap->get_widget('source_latex_dialog');

    my $reponse=$dialog->run();

    my %bouton=();
    for(qw/new choix vide zip/) {
	$bouton{$_}=$gap->get_widget('sl_type_'.$_)->get_active();
	debug "Bouton $_" if($bouton{$_});
    }

    $dialog->destroy();

    debug "REPONSE=$reponse";

    return(0) if(!$reponse);

    # actions apres avoir choisi le type de source latex a utiliser

    if($bouton{'new'}) {
	
	# choix d'un modele

	$gap=Gtk2::GladeXML->new($glade_xml,'source_latex_modele');

	for(qw/source_latex_modele modeles_liste modeles_description/) {
	    $w{$_}=$gap->get_widget($_);
	}

	charge_modeles();
	my $modeles_store = Gtk2::ListStore->new ('Glib::String');
	for my $i (0..$#modeles) {
	    #print "$i->".$modeles[$i]->{'id'}."\n";
	    $modeles_store->set($modeles_store->append(),LISTE_TXT,
				$modeles[$i]->{'id'});
	    
	}
	$w{'modeles_liste'}->set_model($modeles_store);
	my $renderer=Gtk2::CellRendererText->new;
	my $column = Gtk2::TreeViewColumn->new_with_attributes("modèle",
							       $renderer,
							       text=> LISTE_TXT );
	$w{'modeles_liste'}->append_column ($column);
	$w{'modeles_liste'}->get_selection->signal_connect("changed",\&source_latex_mmaj);

	$reponse=$w{'source_latex_modele'}->run();

	debug "Dialogue modele : $reponse";

	# le modele est choisi : l'installer

	my @i;

	if($reponse) {
	    my $sr=$w{'modeles_liste'}->get_selection()->get_selected_rows();
	    if($sr) {
		@i=$sr->get_indices();
	    } else {
		@i=();
	    }
	}

	$w{'source_latex_modele'}->destroy();

	return(0) if(!$reponse);

	if(@i) {
	    debug "Installation modele $i[0] : ".$modeles[$i[0]]->{'fichier'};
	    $projet{'options'}->{'texsrc'}=$modeles[$i[0]]->{'fichier'};
	} else {
	    debug "Aucun modele selectionne";
	    return(0);
	}

    } elsif($bouton{'choix'}) {

	# choisir un fichier deja present

	$gap=Gtk2::GladeXML->new($glade_xml,'source_latex_choix');

	for(qw/source_latex_choix/) {
	    $w{$_}=$gap->get_widget($_);
	}
	$w{'source_latex_choix'}->set_current_folder($home_dir);

	my $filtre_latex=Gtk2::FileFilter->new();
	$filtre_latex->set_name("Fichier LaTeX (*.tex)");
        $filtre_latex->add_pattern("*.tex");
        $filtre_latex->add_pattern("*.TEX");
	$w{'source_latex_choix'}->add_filter($filtre_latex);
	
	$reponse=$w{'source_latex_choix'}->run();

	my $f=$w{'source_latex_choix'}->get_filename();

	$w{'source_latex_choix'}->destroy();

	return(0) if(!$reponse);

	$projet{'options'}->{'texsrc'}=relatif($f);
	debug "Source LaTeX $f";

    } elsif($bouton{'zip'}) {
	
	# choisir un fichier ZIP

	$gap=Gtk2::GladeXML->new($glade_xml,'source_latex_choix_zip');

	for(qw/source_latex_choix_zip/) {
	    $w{$_}=$gap->get_widget($_);
	}
	$w{'source_latex_choix_zip'}->set_current_folder($home_dir);

	my $filtre_zip=Gtk2::FileFilter->new();
	$filtre_zip->set_name("Fichier archive (*.zip)");
        $filtre_zip->add_pattern("*.zip");
        $filtre_zip->add_pattern("*.ZIP");
	$w{'source_latex_choix_zip'}->add_filter($filtre_zip);
	
	$reponse=$w{'source_latex_choix_zip'}->run();

	my $f=$w{'source_latex_choix_zip'}->get_filename();

	$w{'source_latex_choix_zip'}->destroy();

	return(0) if(!$reponse);

	# cree un repertoire temporaire pour dezipper

	my $temp_dir = tempdir( DIR=>tmpdir(),CLEANUP => 1 );

	my $rv=0;

	if(open(UNZIP,"-|","unzip","-d",$temp_dir,$f) ) {
	    while(<UNZIP>) {
		debug $_;
	    }
	    close(UNZIP);
	} else {
	    $rv=1;
	}

	my ($n,$suivant)=n_fich($temp_dir);

	if($rv || $n==0) {
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'error','ok',
				  sprintf("Rien n'a pu être extrait du fichier %s. Vérifiez qu'il est correct.",$f));
	    $dialog->run;
	    $dialog->destroy;
	    return(0);
	} else {
	    # unzip OK
	    # vire les repertoires intermediaires :

	    while($n==1 && -d $suivant) {
		debug "Changement repertoire racine : $suivant";
		$temp_dir=$suivant;
		($n,$suivant)=n_fich($temp_dir);
	    }

	    # bouge les fichiers la ou il faut

	    my $hd=$o{'rep_projets'}."/".$projet{'nom'};

	    mkdir($hd) if(! -e $hd);

	    opendir(MVR,$temp_dir);
	    my @archive_files=grep { ! /^\./ } readdir(MVR);
	    closedir(MVR);

	    my $latex;

	    for(@archive_files) {
		debug "Deplace dans projet : $_";
		$latex=$_ if(/\.tex$/i);
		system("mv","$temp_dir/$_",$hd);
	    }

	    if($latex) {
		$projet{'options'}->{'texsrc'}="%PROJET/$latex";
		debug "LaTeX trouve : $latex";
	    }

	    return(2);
	}

    } elsif($bouton{'vide'}) {

	# choisi un fichier vide

	my $sl=absolu('source.tex');
	if(-e $sl) {
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'error','ok',
				  sprintf("Un fichier <i>source.tex</i> existe déjà dans le répertoire du projet %s. Je ne l'ai pas effacé et il servira de fichier source.",$projet{'nom'}));
	    $dialog->run;
	    $dialog->destroy;      
	    
	    $projet{'options'}->{'texsrc'}='source.tex';

	} else {

	    # creation repertoire si inexistant

	    my $hd=$o{'rep_projets'}."/".$projet{'nom'};

	    mkdir($hd) if(! -e $hd);

	    # creation fichier vide

	    if(! open(FV,">$sl")) {
		debug "Ouverture impossible en creation / $sl : $!";
		return(0);
	    }
	    close(FV);
	    $projet{'options'}->{'texsrc'}='source.tex';

	}
	
    } else {
	return(0);
    }

    return(1);
    
}

sub source_latex_mmaj {
    my $i=$w{'modeles_liste'}->get_selection()->get_selected_rows()->get_indices();
    $w{'modeles_description'}->get_buffer->set_text($modeles[$i]->{'desc'});
}


# copie en changeant eventuellement d'encodage
sub copy_latex {
    my ($src,$dest)=@_;
    # 1) reperage du inputenc dans le source
    my $i='';
    open(SRC,$src);
  LIG: while(<SRC>) {
      s/%.*//;
      if(/\\usepackage\[([^\]]*)\]\{inputenc\}/) {
	  $i=$1;
	  last LIG;
      }
  }
    close(SRC);

    my $ie=get_enc($i);
    my $id=get_enc($o{'encodage_latex'});
    if($ie && $id && $ie->{'iso'} ne $id->{'iso'}) {
	debug "Reencodage $ie->{'iso'} => $id->{'iso'}";
	open(SRC,"<:encoding($ie->{'iso'})",$src) or return('');
	open(DEST,">:encoding($id->{'iso'})",$dest) or close(SRC),return('');
	while(<SRC>) {
	    chomp;
	    s/\\usepackage\[([^\]]*)\]\{inputenc\}/\\usepackage[$id->{'inputenc'}]{inputenc}/;
	    print DEST "$_\n";
	}
	close(DEST);
	close(SRC);
	return(1);
    } else {
	return(copy($src,$dest));
    }
}

sub importe_source {
    my ($fxa,$fxb,$fb) = splitpath($projet{'options'}->{'texsrc'});
    my $dest=absolu($fb);

    # fichier deja dans le repertoire projet...
    return() if(is_local($projet{'options'}->{'texsrc'},1));

    if(-f $dest) {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'error','yes-no',
		  "Le fichier %s existe déjà dans le répertoire projet : voulez-vous écraser son ancien contenu ? Cliquez sur oui pour remplacer le fichier pré-existant par celui que vous venez de sélectionner, ou sur non pour annuler l'import du fichier source.",$fb);
	my $reponse=$dialog->run;
	$dialog->destroy;      

	if($reponse eq 'no') {
	    return(0);
	} 
    }

    if(copy_latex(absolu($projet{'options'}->{'texsrc'}),$dest)) {
	$projet{'options'}->{'texsrc'}=relatif($dest);
	set_source_tex();
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'info','ok',
		  "Le fichier LaTeX a été copié dans le répertoire projet. Vous pouvez maintenant l'éditer soit en utilisant le bouton \"Éditer le fichier LaTeX\", soit directement grâce au logiciel de votre choix.");
	$dialog->run;
	$dialog->destroy;   
    } else {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'error','ok',
		  "Erreur durant la copie du fichier source : %s",$!);
	$dialog->run;
	$dialog->destroy;      
    }
}

sub edite_source {
    my $f=absolu($projet{'options'}->{'texsrc'});
    debug "Edition $f...";
    commande_parallele($o{'tex_editor'},$f);
}

sub valide_projet {
    set_source_tex();

    my $fl=absolu($projet{'options'}->{'listeetudiants'});
    if(-f $fl) {
	$w{'liste'}->set_filename($fl);
    } else {
	debug("Fichier liste introuvable : $fl");
	$w{'liste'}->set_filename('');
    }


    $projet{'_mep_list'}=AMC::MEPList::new(absolu($projet{'options'}->{'mep'}),
					   'brut'=>1,
					   'saved'=>absolu($mep_saved));

    detecte_mep();

    $projet{'_an_list'}=AMC::ANList::new(absolu($projet{'options'}->{'cr'}),
					 'brut'=>1,
					 'saved'=>absolu($an_saved));
    detecte_analyse('premier'=>1);

    debug "Options correction : MB".$projet{'options'}->{'maj_bareme'};
    $w{'maj_bareme'}->set_active($projet{'options'}->{'maj_bareme'});

    transmet_pref($gui,'notation',$projet{'options'});

    my $t=$w{'main_window'}->get_title();
    $t.= ' - projet '.$projet{'nom'} 
        if(!($t =~ s/-.*/- projet $projet{'nom'}/));
    $w{'main_window'}->set_title($t);

    noter_resultat();

    valide_liste('noinfo'=>1,'nomodif'=>1);

    transmet_pref($gui,'export',$projet{'options'});
    transmet_pref($gui,'pref_prep',$projet{'options'});
}

sub projet_ouvre {
    my ($proj,$deja)=(@_);

    my $new_source=0;
    
    # ouverture du projet $projet. Si $deja==1, alors il faut le creer

    if($proj) {
	
	quitte_projet();

	$projet{'nom'}=$proj;

	# choix fichier latex si nouveau projet...
	if($deja) {
	    my $ok=source_latex_choisir();
	    if(!$ok) {
		$projet{'nom'}='';
		return(0);
	    }
	    if($ok==1) {
		$new_source=1;
	    } elsif($ok==2) {
		$deja='';
	    }
	}

	if(!$deja) {

	    if(-f fich_options($proj)) {
		debug "Lecture options du projet $proj...";
		
		$projet{'options'}={pref_xx_lit(fich_options($proj))};
		
		# pour effacer des trucs en trop venant d'un bug anterieur...
		for(keys %{$projet{'options'}}) {
		    delete($projet{'options'}->{$_}) 
			if($_ !~ /^ext_/ && !exists($projet_defaut{$_}));
		}
		debug "Options lues :",
		Dumper(\%projet);
	    } else {
		debug "Pas de fichier options a lire...";
	    }
	}
	
	$projet{'nom'}=$proj;

	# creation du repertoire et des sous-repertoires de projet

	for my $sous ('',qw:cr cr/corrections cr/corrections/jpg cr/corrections/pdf mep scans:) {
	    my $rep=$o{'rep_projets'}."/$proj/$sous";
	    if(! -x $rep) {
		debug "Creation du repertoire $rep...";
		mkdir($rep);
	    }
	}

	# recuperation des options par defaut si elles ne sont pas encore definies dans la conf du projet
    
	for my $k (keys %projet_defaut) {
	    if(! exists($projet{'options'}->{$k})) {
		if($o{'defaut_'.$k}) {
		    $projet{'options'}->{$k}=$o{'defaut_'.$k};
		    debug "Nouveau parametre (defaut) : $k";
		} else {
		    $projet{'options'}->{$k}=$projet_defaut{$k};
		    debug "Nouveau parametre : $k";
		}
	    }
	}

	$w{'onglets_projet'}->set_sensitive(1);

	$w{'menu_outils'}->set_sensitive(1);

	valide_projet();

	$projet{'options'}->{'_modifie'}='';

	set_source_tex(1) if($new_source);

	return(1);
    }
}

sub quitte_projet {
    if($projet{'nom'}) {
	
	valide_options_notation();
	
	if($projet{'options'}->{'_modifie'}) {
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'question','yes-no',
				  sprintf("Vous n'avez pas sauvegardé les options du projet <i>%s</i>, qui ont pourtant été modifiées : voulez-vous le faire avant de le quitter ?",$projet{'nom'}));
	    my $reponse=$dialog->run;
	    $dialog->destroy;      
	    
	    if($reponse eq 'yes') {
		projet_sauve();
	    } 
	}

	%projet=();
    }
}

sub quitter {
    my $ok=0;
    my $reponse='';

    quitte_projet();

    if($o{'conserve_taille'}) {
	my ($x,$y)=$w{'main_window'}->get_size();
	if(!$o{'taille_x_main'} || !$o{'taille_y_main'}
	   || $x != $o{'taille_x_main'} || $y != $o{'taille_y_main'}) {
	    $o{'taille_x_main'}=$x;
	    $o{'taille_y_main'}=$y;
	    $o{'_modifie'}=1;
	    $ok=1;
	}
    }

    if($o{'_modifie'}) {
	if(!$ok) {
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'question','yes-no',
				  "Vous n'avez pas sauvegardé les options générales, qui ont pourtant été modifiées : voulez-vous le faire avant de le quitter ?");
	    $reponse=$dialog->run;
	    $dialog->destroy;      
	}
	
	if($reponse eq 'yes' || $ok) {
	    sauve_pref_generales();
	} 
    }

    Gtk2->main_quit;
    
}

$gui->signal_autoconnect_from_package('main');

if($o{'conserve_taille'} && $o{'taille_x_main'} && $o{'taille_y_main'}) {
    $w{'main_window'}->resize($o{'taille_x_main'},$o{'taille_y_main'});
}

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


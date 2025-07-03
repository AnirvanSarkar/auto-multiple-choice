# -*- perl -*-
#
# Copyright (C) 2020-2025 Alexis Bienvenüe <paamc@passoire.fr>
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

use warnings;
use 5.012;

package AMC::Gui::RenameSource;

use parent 'AMC::Gui';

use AMC::Basic;

use Gtk3;

use_gettext();

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    return $self->dialog();
}

sub dialog {
    my ($self) = @_;
    
    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade($glade_xml, qw/rename_source rename_source_entry/);

    my $dialog = $self->get_ui('rename_source');
    my $entry  = $self->get_ui('rename_source_entry');

    my $src = $self->get_absolute("project:texsrc");
    $src =~ s/.*\///;

    $entry->set_text($src);

    $dialog->show_all();
    
    my $last_dot = rindex($src, ".");
    if($last_dot > 0) {
        $entry->select_region(0, $last_dot);
    }
    
    my $reponse = $dialog->run();

    my $new_filename = $entry->get_text();

    $dialog->destroy();

    debug "RESPONSE=$reponse";

    if($reponse eq "apply") {
        $new_filename =~ s/\//_/g;
        if($self->get('ascii_filenames')) {
            $new_filename = string_to_usascii($new_filename);
        }
        $new_filename = $self->absolu('%PROJET/') . $new_filename;
        return($new_filename);
    } else{
        return();
    }

}    

1;

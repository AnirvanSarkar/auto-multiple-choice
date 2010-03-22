#
# Copyright (C) 2010 Alexis Bienvenue <paamc@passoire.fr>
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

SHELL=/bin/sh

DOMAIN=auto-multiple-choice

XGETTO=

AMC=..

PERL=$(AMC)/*.pl $(AMC)/AMC-perl/AMC/*.pm $(AMC)/AMC-perl/AMC/**/*.pm 

GLADE=$(AMC)/AMC-gui.glade $(AMC)/AMC-perl/AMC/**/*.glade

POS=$(wildcard lang/*.po)
MOS=$(POS:.po=.mo)
LANGS=$(basename $(notdir $(POS)))

all: $(MOS)

clean: FORCE
	rm -f $(MOS)
	rm -f *.bpot
	rm -f *.po

%.mo: %.po
	msgfmt $< -o $@

%.pot: %.bpot po-clean.pl
	perl po-clean.pl $< $@

$(DOMAIN).bpot: $(PERL) $(GLADE)
	xgettext $(XGETTO) --add-comments=TRANSLATORS: $(PERL) -k__ -k__p -k -o $@
	xgettext $(XGETTO) -j $(GLADE) -o $@
list:
	grep -lr __ $(AMC) |grep '\.\(pl\|pm\)$$' | grep -v 'debian' ; ls $(GLADE)

%.merge: $(DOMAIN).pot
	msgmerge -U lang/$*.po $(DOMAIN).pot

merge: $(addsuffix .merge,$(LANGS)) ;

FORCE: ;

.PHONY: all clean list merge FORCE

.INTERMEDIATE: $(DOMAIN).bpot

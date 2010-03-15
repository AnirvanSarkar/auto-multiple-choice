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

BASE_VARS:=$(.VARIABLES)

include Makefile.versions
include Makefile.conf

SUBST_VARS:=$(filter-out $(BASE_VARS) BASE_VARS,$(.VARIABLES))

SHELL=/bin/sh

DESTDIR=

GCC=gcc

GCCPOPPLER=-I /usr/include/poppler -lpoppler

MODS=AMC-*.pl AMC-traitement-image AMC-mepdirect
GLADE=AMC-*.glade
STY=automultiplechoice.sty
MOS=$(shell ls I18N/lang/*.mo)
LANGS=$(notdir $(basename $(MOS)))
SUBMODS=$(notdir $(shell ls doc/modeles))

FROM_IN=menu auto-multiple-choice AMC-gui.glade AMC-gui.pl AMC-perl/AMC/Basic.pm doc/doc-xhtml-site.xsl doc/doc-xhtml.xsl doc/auto-multiple-choice.xml

all: $(FROM_IN) AMC-traitement-image AMC-mepdirect logo.xpm doc I18N ;

MAJ: $(FROM_IN) ;

AMC-traitement-image: AMC-traitement-image.c Makefile
	$(GCC) -O3 -I. -lnetpbm $< -o $@

AMC-mepdirect: AMC-mepdirect.cc Makefile
	$(GCC) $(GCCPOPPLER) -O3 $< -o $@

nv.pl: FORCE
	perl local/versions.pl

%.glade: %.in.glade
	sed $(foreach varname,$(SUBST_VARS), -e 's+@/$(varname)/@+$($(varname))+g;' ) $< > $@

%.pl: %.in.pl
	sed $(foreach varname,$(SUBST_VARS), -e 's+@/$(varname)/@+$($(varname))+g;' ) $< > $@

%.pm: %.in.pm
	sed $(foreach varname,$(SUBST_VARS), -e 's+@/$(varname)/@+$($(varname))+g;' ) $< > $@

%.xsl: %.in.xsl
	sed $(foreach varname,$(SUBST_VARS), -e 's+@/$(varname)/@+$($(varname))+g;' ) $< > $@

%.xml: %.in.xml
	sed $(foreach varname,$(SUBST_VARS), -e 's+@/$(varname)/@+$($(varname))+g;' ) -e 's+/usr/share/xml/docbook/schema/dtd/4.5/docbookx.dtd+$(DOCBOOK_DTD)+g;' $< > $@

%: %.in
	sed $(foreach varname,$(SUBST_VARS), -e 's+@/$(varname)/@+$($(varname))+g;' ) $< > $@

doc:
	$(MAKE) -C doc

I18N:
	$(MAKE) -C I18N

sync:
	$(MAKE) -C download-area all

%.ps: %.dvi
	dvips $< -o $@

%.ppm: %.ps
	convert -density 300 $< $*-%03d.ppm

%.png: %.svg
	inkscape --export-width=32 --export-height=32 --export-png=$@ $<

%.xpm: %.png
	pngtopnm $< | ppmtoxpm > $@

global: FORCE
	-sudo rm /usr/share/perl5/AMC /usr/lib/AMC/AMC-traitement-image /usr/lib/AMC/AMC-mepdirect $(ICONSDIR)/auto-multiple-choice.svg /usr/share/doc/auto-multiple-choice

LOCALDIR=/home/alexis/enseignement/auto-qcm

local: global
	sudo ln -s $(LOCALDIR)/AMC-perl/AMC /usr/share/perl5/AMC
	sudo ln -s $(LOCALDIR)/AMC-traitement-image /usr/lib/AMC/AMC-traitement-image
	sudo ln -s $(LOCALDIR)/AMC-mepdirect /usr/lib/AMC/AMC-mepdirect
	sudo ln -s $(LOCALDIR)/logo.svg $(ICONSDIR)/auto-multiple-choice.svg
	sudo ln -s $(LOCALDIR)/doc /usr/share/doc/auto-multiple-choice

clean: FORCE
	-rm $(FROM_IN) AMC-traitement-image AMC-mepdirect logo.xpm
	$(MAKE) -C doc clean
	$(MAKE) -C I18N clean

install_lang_%: FORCE
	install -d -m 0755 -o root -g root $(DESTDIR)/$(LOCALEDIR)/$*/LC_MESSAGES
	install    -m 0644 -o root -g root I18N/lang/$*.mo $(DESTDIR)/$(LOCALEDIR)/$*/LC_MESSAGES/auto-multiple-choice.mo

install_lang: $(addprefix install_lang_,$(LANGS)) ;

install_models_%: FORCE
	install -d -m 0755 -o root -g root $(DESTDIR)/$(MODELSDIR)/$*
	install    -m 0644 -o root -g root doc/modeles/$*/*.tgz $(DESTDIR)/$(MODELSDIR)/$*
	install    -m 0644 -o root -g root doc/modeles/$*/*.xml $(DESTDIR)/$(MODELSDIR)/$*

install_models: $(addprefix install_models_,$(SUBMODS)) ;

install: install_lang install_models FORCE
	install -d -m 0755 -o root -g root $(DESTDIR)/$(MODSDIR)
	install    -m 0755 -o root -g root $(MODS) $(DESTDIR)/$(MODSDIR)
	install    -m 0644 -o root -g root $(GLADE) $(DESTDIR)/$(MODSDIR)
	install -d -m 0755 -o root -g root $(DESTDIR)/$(TEXDIR)
	install    -m 0644 -o root -g root $(STY) $(DESTDIR)/$(TEXDIR)
	install -d -m 0755 -o root -g root $(DESTDIR)/$(MENUDIR)
	install    -m 0644 -o root -g root -T menu $(DESTDIR)/$(MENUDIR)/auto-multiple-choice
	install -d -m 0755 -o root -g root $(DESTDIR)/$(DESKTOPDIR)
	install    -m 0644 -o root -g root -T desktop $(DESTDIR)/$(DESKTOPDIR)/auto-multiple-choice.desktop
	install -d -m 0755 -o root -g root $(DESTDIR)/$(BINDIR)
	install    -m 0755 -o root -g root auto-multiple-choice $(DESTDIR)/$(BINDIR)
	install -d -m 0755 -o root -g root $(DESTDIR)/$(ICONSDIR)
	install    -m 0644 -o root -g root -T logo.svg $(DESTDIR)/$(ICONSDIR)/auto-multiple-choice.svg
	install -d -m 0755 -o root -g root $(DESTDIR)/$(PIXDIR)
	install    -m 0644 -o root -g root -T logo.xpm $(DESTDIR)/$(PIXDIR)/auto-multiple-choice.xpm
	install -d -m 0755 -o root -g root $(DESTDIR)/$(PERLDIR)/AMC
	install -d -m 0755 -o root -g root $(DESTDIR)/$(PERLDIR)/AMC/Export
	install -d -m 0755 -o root -g root $(DESTDIR)/$(PERLDIR)/AMC/Gui
	install    -m 0644 -o root -g root AMC-perl/AMC/*.pm $(DESTDIR)/$(PERLDIR)/AMC
	install    -m 0644 -o root -g root AMC-perl/AMC/Export/*.pm $(DESTDIR)/$(PERLDIR)/AMC/Export
	install    -m 0644 -o root -g root AMC-perl/AMC/Gui/*.pm $(DESTDIR)/$(PERLDIR)/AMC/Gui
	install    -m 0644 -o root -g root AMC-perl/AMC/Gui/*.glade $(DESTDIR)/$(PERLDIR)/AMC/Gui

# perl >= 5.10 pour operateur //
# libnetpbm9 -> libppm (AMC-traitement-image)
# netpbm -> ppmtoxpm (Manuel.pm)
# xpdf-reader -> pdftoppm (Manuel.pm)
# xpdf-utils -> pdfinfo (AMC-prepare)

BUILDOPTS=-I.svn -Idownload-area -Ilocal -rsudo -k42067447

debsrc_vok:
	dpkg-buildpackage -S -sa $(BUILDOPTS)

debsrc: nv.pl
	$(MAKE) debsrc_vok

deb_vok:
	dpkg-buildpackage -b $(BUILDOPTS)

deb: nv.pl
	$(MAKE) deb_vok

experimental: FORCE
	$(MAKE) -C download-area repos sync

FORCE: ;

.PHONY: install deb debsrc clean global doc I18N experimental FORCE MAJ



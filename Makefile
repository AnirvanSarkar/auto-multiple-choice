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

SUB_MAKEFILES=$(wildcard Makefile.versions Makefile.conf)

include $(SUB_MAKEFILES)

SUBST_VARS:=$(shell grep -h '=' $(SUB_MAKEFILES) |sed 's/=.*//;')

GCC ?= gcc
GCC_PP ?= gcc
CFLAGS ?= -O2
CXXFLAGS ?= -O2

SHELL=/bin/sh

DESTDIR=

MODS=AMC-*.pl AMC-traitement-image AMC-mepdirect
GLADE=AMC-gui.glade
STY=automultiplechoice.sty
MOS=$(wildcard I18N/lang/*.mo)
LANGS=$(notdir $(basename $(MOS)))
SUBMODS=$(notdir $(shell ls doc/modeles))

FROM_IN=debian/menu auto-multiple-choice auto-multiple-choice.desktop AMC-gui.glade AMC-gui.pl AMC-perl/AMC/Basic.pm doc/doc-xhtml-site.xsl doc/doc-xhtml.xsl doc/auto-multiple-choice.xml

PRECOMP_FLAG_FILE=PRECOMP
PRECOMP_ARCHIVE:=$(wildcard $(PRECOMP_FLAG_FILE))

ifeq ($(PRECOMP_ARCHIVE),)
all: $(FROM_IN) AMC-traitement-image AMC-mepdirect logo.xpm doc I18N ;
else
all: all_precomp ;
endif

all_precomp: $(FROM_IN) AMC-traitement-image AMC-mepdirect ;

MAJ: $(FROM_IN) ;

AMC-traitement-image: AMC-traitement-image.c Makefile
	$(GCC) -o $@ $< $(CFLAGS) $(LDFLAGS) $(GCC_NETPBM)

AMC-mepdirect: AMC-mepdirect.cc Makefile
	$(GCC_PP) -o $@ $< $(CXXFLAGS) $(LDFLAGS) $(GCC_POPPLER)

nv.pl: FORCE
	perl local/versions.pl
	make auto-multiple-choice.spec

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

clean_IN: FORCE
	rm -rf debian/auto-multiple-choice
	rm -f $(FROM_IN)

clean: clean_IN FORCE
	rm -f AMC-traitement-image AMC-mepdirect logo.xpm $(PRECOMP_FLAG_FILE)
	rm -f auto-multiple-choice.spec
	$(MAKE) -C doc clean
	$(MAKE) -C I18N clean

install_lang_%: FORCE
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(LOCALEDIR)/$*/LC_MESSAGES
	install    -m 0644 $(USER_GROUP) I18N/lang/$*.mo $(DESTDIR)/$(LOCALEDIR)/$*/LC_MESSAGES/auto-multiple-choice.mo

install_lang: $(addprefix install_lang_,$(LANGS)) ;

install_models_%: FORCE
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(MODELSDIR)/$*
	install    -m 0644 $(USER_GROUP) doc/modeles/$*/*.tgz $(DESTDIR)/$(MODELSDIR)/$*
	install    -m 0644 $(USER_GROUP) doc/modeles/$*/*.xml $(DESTDIR)/$(MODELSDIR)/$*

install_models: $(addprefix install_models_,$(SUBMODS)) ;

install: install_lang install_models FORCE
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(MODSDIR)
	install    -m 0755 $(USER_GROUP) $(MODS) $(DESTDIR)/$(MODSDIR)
	install    -m 0644 $(USER_GROUP) $(GLADE) $(DESTDIR)/$(MODSDIR)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(TEXDIR)
	install    -m 0644 $(USER_GROUP) $(STY) $(DESTDIR)/$(TEXDIR)
ifneq ($(MENUDIR),)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(MENUDIR)
	install    -m 0644 $(USER_GROUP) -T debian/menu $(DESTDIR)/$(MENUDIR)/auto-multiple-choice
endif
ifneq ($(DESKTOPDIR),)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(DESKTOPDIR)
	install    -m 0644 $(USER_GROUP) -T auto-multiple-choice.desktop $(DESTDIR)/$(DESKTOPDIR)/auto-multiple-choice.desktop
endif
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(BINDIR)
	install    -m 0755 $(USER_GROUP) auto-multiple-choice $(DESTDIR)/$(BINDIR)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(ICONSDIR)
	install    -m 0644 $(USER_GROUP) -T logo.svg $(DESTDIR)/$(ICONSDIR)/auto-multiple-choice.svg
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PIXDIR)
	install    -m 0644 $(USER_GROUP) -T logo.xpm $(DESTDIR)/$(PIXDIR)/auto-multiple-choice.xpm
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PERLDIR)/AMC
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PERLDIR)/AMC/Export
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PERLDIR)/AMC/Gui
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/*.pm $(DESTDIR)/$(PERLDIR)/AMC
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/Export/*.pm $(DESTDIR)/$(PERLDIR)/AMC/Export
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/Gui/*.pm $(DESTDIR)/$(PERLDIR)/AMC/Gui
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/Gui/*.glade $(DESTDIR)/$(PERLDIR)/AMC/Gui
ifneq ($(SYSTEM_TYPE),deb) # with debian, done with dh_install{doc,man}
ifneq ($(SYSTEM_TYPE),rpm)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(DOCDIR)
	install    -m 0644 $(USER_GROUP) doc/auto-multiple-choice.{xml,pdf} $(DESTDIR)/$(DOCDIR)
	cp -r doc/html $(DESTDIR)/$(DOCDIR)
endif
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(MAN1DIR)
	install    -m 0644 $(USER_GROUP) doc/*.1 $(DESTDIR)/$(MAN1DIR)
endif

# perl >= 5.10 pour operateur //
# libnetpbm9 -> libppm (AMC-traitement-image)
# netpbm -> ppmtoxpm (Manuel.pm)
# xpdf-reader -> pdftoppm (Manuel.pm)
# xpdf-utils -> pdfinfo (AMC-prepare)

ifdef DEBSIGN_KEY
DEBSIGN=-k$(DEBSIGN_KEY)
else
DEBSIGN=-us -uc
endif

BUILDOPTS=-I.svn -Idownload_area -Ilocal $(DEBSIGN)

SOURCE_DIR=auto-multiple-choice-$(PACKAGE_V_DEB)

precomp_base: FORCE
	$(MAKE) clean_IN
	touch $(PRECOMP_FLAG_FILE)
ifeq ($(SUDOER),)
	tar cvzf ../auto-multiple-choice_$(PACKAGE_V_DEB)_precomp.tar.gz --exclude-vcs '--exclude=*~' --exclude download_area .
else
	-mkdir ../$(SOURCE_DIR)
	sudo mount --bind $(PWD) ../$(SOURCE_DIR)
	cd .. ; tar cvzf auto-multiple-choice_$(PACKAGE_V_DEB)_precomp.tar.gz --exclude-vcs '--exclude=*~' --exclude download_area $(SOURCE_DIR)
	sudo umount ../$(SOURCE_DIR)
	rmdir ../$(SOURCE_DIR)
endif

precomp_simple_vok:
	$(MAKE) precomp_base

precomp_vok: logo.xpm I18N doc
	$(MAKE) precomp_base

precomp: 
	$(MAKE) clean
	$(MAKE) MAJ nv.pl
	$(MAKE) precomp_vok

precomp_simple: 
	$(MAKE) MAJ nv.pl
	$(MAKE) precomp_simple_vok

debsrc_vok:
ifeq ($(SUDOER),)
	dpkg-buildpackage -S -sn $(BUILDOPTS)
else
	-mkdir ../$(SOURCE_DIR)
	sudo mount --bind $(PWD) ../$(SOURCE_DIR)
	cd ../$(SOURCE_DIR) ; dpkg-buildpackage -S -sn $(BUILDOPTS)
	sudo umount ../$(SOURCE_DIR)
	rmdir ../$(SOURCE_DIR)
endif

debsrc: nv.pl
	$(MAKE) debsrc_vok

deb_vok:
	dpkg-buildpackage -b $(BUILDOPTS)

deb: nv.pl
	$(MAKE) deb_vok

unstable: FORCE
	$(MAKE) -C download_area unstable sync

re_unstable: FORCE
	$(MAKE) -C download_area re_unstable sync

FORCE: ;

.PHONY: all all_precomp install deb debsrc precomp clean global doc I18N experimental FORCE MAJ



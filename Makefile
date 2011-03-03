#
# Copyright (C) 2008-2011 Alexis Bienvenue <paamc@passoire.fr>
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

SUB_MAKEFILES=$(wildcard Makefile.versions Makefile.conf)

include $(SUB_MAKEFILES)

PACKAGE_DEB_DV=1

SUBST_VARS:=$(shell grep -h '=' $(SUB_MAKEFILES) | grep -v '^\#' | sed 's/?\?=.*//;' ) PACKAGE_DEB_DV

GCC ?= gcc
GCC_PP ?= gcc
CFLAGS ?= -O2
CXXFLAGS ?= -O2

SHELL=/bin/sh

DESTDIR=

BINARIES=AMC-traitement-image AMC-mepdirect AMC-detect

MODS=AMC-*.pl $(BINARIES)
GLADE=AMC-gui.glade
MOD_GLADE=$(wildcard AMC-perl/AMC/Gui/*.glade.in)
STY=doc/sty/automultiplechoice.sty
DTX=doc/sty/automultiplechoice.dtx
MOS=$(wildcard I18N/lang/*.mo)
LANGS=$(notdir $(basename $(MOS)))
SUBMODS=$(notdir $(shell ls doc/modeles))

DOC_XML_IN=$(wildcard doc/auto-multiple-choice.*.in.xml)

FROM_IN=auto-multiple-choice auto-multiple-choice.desktop AMC-gui.glade $(MOD_GLADE:.glade.in=.glade) AMC-gui.pl AMC-perl/AMC/Basic.pm doc/doc-xhtml-site.fr.xsl doc/doc-xhtml-site.en.xsl doc/doc-xhtml.xsl $(DOC_XML_IN:.in.xml=.xml) $(DTX)

PRECOMP_FLAG_FILE=PRECOMP
PRECOMP_ARCHIVE:=$(wildcard $(PRECOMP_FLAG_FILE))

MAIN_LOGO=icons/auto-multiple-choice

ifeq ($(PRECOMP_ARCHIVE),)
all: $(FROM_IN) $(BINARIES) $(MAIN_LOGO).xpm doc I18N ;
else
all: all_precomp ;
endif

all_precomp: $(FROM_IN) $(BINARIES) ;

MAJ: $(FROM_IN) ;

AMC-traitement-image: AMC-traitement-image.c Makefile
	$(GCC) -o $@ $< $(CFLAGS) $(LDFLAGS) $(GCC_NETPBM)

AMC-mepdirect: AMC-mepdirect.cc Makefile
	$(GCC_PP) -o $@ $< $(CXXFLAGS) $(LDFLAGS) $(CXXLDFLAGS) $(GCC_POPPLER)

AMC-detect: AMC-detect.cc Makefile
	$(GCC_PP) -o $@ $< $(CXXFLAGS) $(LDFLAGS) $(CXXLDFLAGS) -lm $(GCC_OPENCV)

%.xml: %.in.xml
	sed $(foreach varname,$(SUBST_VARS), -e 's|@/$(varname)/@|$($(varname))|g;' ) -e 's+/usr/share/xml/docbook/schema/dtd/4.5/docbookx.dtd+$(DOCBOOK_DTD)+g;' $< > $@

%: %.in $(SUB_MAKEFILES)
	sed $(foreach varname,$(SUBST_VARS), -e 's|@/$(varname)/@|$($(varname))|g;' ) $< > $@

doc:
	$(MAKE) -C doc
	$(MAKE) -C doc/sty

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

clean_IN: FORCE
	rm -rf debian/auto-multiple-choice
	rm -f $(FROM_IN)

clean: clean_IN FORCE
	rm -f $(BINARIES) $(MAIN_LOGO).xpm
	rm -f auto-multiple-choice.spec
	$(MAKE) -C doc/sty clean
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
ifneq ($(TEXDOCDIR),)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(TEXDOCDIR)
	install    -m 0644 $(USER_GROUP) doc/sty/*.pdf doc/sty/*.tex $(DESTDIR)/$(TEXDOCDIR)
endif
ifneq ($(DESKTOPDIR),)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(DESKTOPDIR)
	install    -m 0644 $(USER_GROUP) -T auto-multiple-choice.desktop $(DESTDIR)/$(DESKTOPDIR)/auto-multiple-choice.desktop
endif
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(BINDIR)
	install    -m 0755 $(USER_GROUP) auto-multiple-choice $(DESTDIR)/$(BINDIR)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(ICONSDIR)
	install    -m 0644 $(USER_GROUP) icons/*.svg $(DESTDIR)/$(ICONSDIR)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PIXDIR)
	install    -m 0644 $(USER_GROUP) -T $(MAIN_LOGO).xpm $(DESTDIR)/$(PIXDIR)/auto-multiple-choice.xpm
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

##############################################################################
# Following lines are only helpfull for source tarball and package building
# These targets run only with source from svn checkout
##############################################################################

LOCALDIR=$(shell pwd)

global: FORCE
	-sudo rm /usr/share/perl5/AMC /usr/lib/AMC/AMC-traitement-image /usr/lib/AMC/AMC-detect /usr/lib/AMC/AMC-mepdirect $(ICONSDIR) /usr/share/doc/auto-multiple-choice $(LOCALEDIR)/fr/LC_MESSAGES/auto-multiple-choice.mo $(DESKTOPDIR)/auto-multiple-choice.desktop $(MODELSDIR)

local: global
	test -d /usr/lib/AMC || sudo mkdir -p /usr/lib/AMC
	test -d /usr/share/auto-multiple-choice  || sudo mkdir -p /usr/share/auto-multiple-choice
	test -d $(LOCALEDIR)/fr/LC_MESSAGES || sudo mkdir -p $(LOCALEDIR)/fr/LC_MESSAGES
	sudo ln -s $(LOCALDIR)/I18N/lang/fr.mo $(LOCALEDIR)/fr/LC_MESSAGES/auto-multiple-choice.mo
	sudo ln -s $(LOCALDIR)/AMC-perl/AMC /usr/share/perl5/AMC
	sudo ln -s $(LOCALDIR)/AMC-traitement-image /usr/lib/AMC/AMC-traitement-image
	sudo ln -s $(LOCALDIR)/AMC-detect /usr/lib/AMC/AMC-detect
	sudo ln -s $(LOCALDIR)/AMC-mepdirect /usr/lib/AMC/AMC-mepdirect
	sudo ln -s $(LOCALDIR)/icons $(ICONSDIR)
	sudo ln -s $(LOCALDIR)/doc /usr/share/doc/auto-multiple-choice
	sudo ln -s $(LOCALDIR)/auto-multiple-choice.desktop $(DESKTOPDIR)/auto-multiple-choice.desktop
	sudo ln -s $(LOCALDIR)/doc/modeles $(MODELSDIR)

ifdef DEBSIGN_KEY
DEBSIGN=-k$(DEBSIGN_KEY)
else
DEBSIGN=-us -uc
endif

BUILDOPTS=-I.svn -Idownload_area -Ilocal $(DEBSIGN)

TMP_DIR=/tmp
SOURCE_DIR=auto-multiple-choice-$(PACKAGE_V_DEB)
TMP_SOURCE_DIR=$(TMP_DIR)/$(SOURCE_DIR)

SRC_EXCL=--exclude debian '--exclude=*~' 

version_files:
	perl local/versions.pl
	$(MAKE) auto-multiple-choice.spec

tmp_copy:
	rm -rf $(TMP_SOURCE_DIR)
	mkdir $(TMP_SOURCE_DIR)
	rsync -aC --exclude '*~' --exclude download_area --exclude local . $(TMP_SOURCE_DIR)
	$(MAKE) -C $(TMP_SOURCE_DIR) clean

sources_vok:
	$(MAKE) tmp_copy
	cd /tmp ; tar cvzf auto-multiple-choice_$(PACKAGE_V_DEB)_sources.tar.gz $(SRC_EXCL) $(SOURCE_DIR)
	$(MAKE) -C $(TMP_SOURCE_DIR) MAJ
	$(MAKE) -C $(TMP_SOURCE_DIR) $(MAIN_LOGO).xpm I18N doc
	$(MAKE) -C $(TMP_SOURCE_DIR) clean_IN
	$(MAKE) -C $(TMP_SOURCE_DIR) auto-multiple-choice.spec
	touch $(TMP_SOURCE_DIR)/$(PRECOMP_FLAG_FILE)
	cd /tmp ; tar cvzf auto-multiple-choice_$(PACKAGE_V_DEB)_precomp.tar.gz $(SRC_EXCL) $(SOURCE_DIR)

tmp_deb:
	$(MAKE) local/deb-auto-changelog
	$(MAKE) tmp_copy
	cp local/deb-auto-changelog $(TMP_SOURCE_DIR)/debian/changelog

debsrc_vok: tmp_deb
	cd $(TMP_SOURCE_DIR) ; dpkg-buildpackage -S -sn $(BUILDOPTS)

deb_vok: tmp_deb
	cd $(TMP_SOURCE_DIR) ; dpkg-buildpackage -b $(BUILDOPTS)

# % : make sure version_files are rebuilt before calling target %_vok

$(foreach key,deb debsrc sources,$(eval $(key): clean version_files ; $$(MAKE) $(key)_vok))

# debian repository

unstable:
	$(MAKE) -C download_area unstable sync

re_unstable:
	$(MAKE) -C download_area re_unstable sync

FORCE: ;

.PHONY: all all_precomp install version_files deb deb_vok debsrc debsrc_vok sources sources_vok clean clean_IN global local doc I18N tmp_copy tmp_deb unstable re_unstable FORCE MAJ



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

SHELL=/bin/sh

DESTDIR=

DEB_HOST_ARCH := $(shell dpkg-architecture -qDEB_HOST_ARCH)
DEB_BUILD_ARCH := $(shell dpkg-architecture -qDEB_BUILD_ARCH)
ifeq ($(DEB_HOST_ARCH),$(DEB_BUILD_ARCH))
GCC=gcc
GCCARCHFLAGS=
else
GCC=gcc
ifeq ($(DEB_HOST_ARCH),amd64)
GCCARCHFLAGS=-m64
endif
ifeq ($(DEB_HOST_ARCH),i386)
GCCARCHFLAGS=-m32
endif
endif

GCCPOPPLER=-I /usr/include/poppler -lpoppler

BINDIR=/usr/bin
PERLDIR=/usr/share/perl5
MODSDIR=/usr/lib/AMC
TEXDIR=/usr/share/texmf-texlive/tex/latex/AMC
MENUDIR=/usr/share/menu
DESKTOPDIR=/usr/share/applications
ICONSDIR=/usr/share/icons/hicolor/scalable/apps
PIXDIR=/usr/share/pixmaps
LOCALEDIR=/usr/share/locale

MODS=AMC-*.pl AMC-traitement-image AMC-mepdirect
GLADE=AMC-*.glade
STY=automultiplechoice.sty
MOS=I18N/lang/*.mo

all: AMC-traitement-image AMC-mepdirect AMC-gui.glade doc logo.xpm I18N ;

AMC-traitement-image: AMC-traitement-image.c Makefile
	$(GCC) $(GCCARCHFLAGS) -O3 -I. -lnetpbm $< -o $@

AMC-mepdirect: AMC-mepdirect.cc Makefile
	$(GCC) $(GCCARCHFLAGS) $(GCCPOPPLER) -O3 $< -o $@

nv.pl: FORCE
	perl local/versions.pl

%.glade: %.in.glade
	perl versions.pl < $< > $@

doc:
	$(MAKE) -C doc

i18N:
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
	-rm AMC-traitement-image AMC-mepdirect AMC-gui.glade logo.xpm
	$(MAKE) -C doc clean
	$(MAKE) -C I18N clean

install_lang_%: FORCE
	install    -m 0644 -o root -g root I18N/lang/$*.mo $(DESTDIR)/$(LOCALEDIR)/$*/LC_MESSAGES/auto-multiple-choice.mo

install_lang_all: $(addprefix install_lang_,$(basename $(MOS)))
	install -d -m 0755 -o root -g root $(DESTDIR)/$(LOCALEDIR)

install: install_lang_all FORCE
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

debsrc: nv.pl
	dpkg-buildpackage -S -sa $(BUILDOPTS)

deb: nv.pl
	dpkg-buildpackage -b $(BUILDOPTS)

experimental: FORCE
	$(MAKE) -C download-area repos sync

FORCE: ;

.PHONY: install deb debsrc clean global doc I18N experimental FORCE



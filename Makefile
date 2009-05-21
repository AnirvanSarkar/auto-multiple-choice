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

SHELL=/bin/sh


DESTDIR=

BINDIR=/usr/bin
PERLDIR=/usr/share/perl5
MODSDIR=/usr/lib/AMC
TEXDIR=/usr/share/texmf-texlive/tex/latex/AMC
MENUDIR=/usr/share/menu
DESKTOPDIR=/usr/share/applications
ICONSDIR=/usr/share/icons/hicolor/scalable/apps
PIXDIR=/usr/share/pixmaps

MODS=AMC-*.pl AMC-traitement-image
GLADE=AMC-*.glade
STY=automultiplechoice.sty

all: AMC-traitement-image AMC-gui.glade doc logo.xpm ;

AMC-traitement-image: AMC-traitement-image.c Makefile
	gcc -O3 -I. -lppm $< -o $@

%.glade: %.in.glade FORCE
	perl versions.pl < $< > $@

doc:
	$(MAKE) -C doc

sync:
	$(MAKE) -C download-area sync

%.ps: %.dvi
	dvips $< -o $@

%.ppm: %.ps
	convert -density 300 $< $*-%03d.ppm

%.png: %.svg
	inkscape --export-width=32 --export-height=32 --export-png=$@ $<

%.xpm: %.png
	pngtopnm $< | ppmtoxpm > $@

global: FORCE
	-sudo rm /usr/share/perl5/AMC /usr/lib/AMC/AMC-traitement-image $(ICONSDIR)/auto-multiple-choice.svg /usr/share/doc/auto-multiple-choice

local: global
	sudo ln -s /home/alexis/enseignement/auto-qcm/AMC-perl/AMC /usr/share/perl5/AMC
	sudo ln -s /home/alexis/enseignement/auto-qcm/AMC-traitement-image /usr/lib/AMC/AMC-traitement-image
	sudo ln -s /home/alexis/enseignement/auto-qcm/logo.svg $(ICONSDIR)/auto-multiple-choice.svg
	sudo ln -s /home/alexis/enseignement/auto-qcm/doc /usr/share/doc/auto-multiple-choice

clean: FORCE
	-rm AMC-traitement-image AMC-gui.glade

install: FORCE
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
	install -d -m 0755 -o root -g root $(DESTDIR)/$(PERLDIR)/AMC/Gui
	install    -m 0644 -o root -g root AMC-perl/AMC/*.pm $(DESTDIR)/$(PERLDIR)/AMC
	install    -m 0644 -o root -g root AMC-perl/AMC/Gui/*.pm $(DESTDIR)/$(PERLDIR)/AMC/Gui
	install    -m 0644 -o root -g root AMC-perl/AMC/Gui/*.glade $(DESTDIR)/$(PERLDIR)/AMC/Gui

# perl >= 5.10 pour operateur //
# libnetpbm9 -> libppm (AMC-traitement-image)
# netpbm -> ppmtoxpm (Manuel.pm)
# xpdf-reader -> pdftoppm (Manuel.pm)
# xpdf-utils -> pdfinfo (AMC-prepare)
deb: FORCE
	dpkg-buildpackage -I.svn -Idownload-area -rsudo -k42067447

VERSION=0.1.0
RELEASE=4

FORCE: ;

.PHONY: install deb debsimple clean global doc FORCE



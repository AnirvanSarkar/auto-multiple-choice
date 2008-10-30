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

DOCBOOKS=$(shell ls *.xml)

all: $(DOCBOOKS:.xml=.pdf) $(DOCBOOKS:.xml=.x) ; 

%.pdf: %.xml
	dblatex $<

#	fop -xml $< -xsl /usr/share/xml/docbook/stylesheet/nwalsh/fo/docbook.xsl -pdf $@

%.x: %.ext %.man %.html ;

%.ext: %.xml
	./extrait-fichiers.pl --liste $@ $<

%.man: %.xml
	xsltproc --nonet --param man.charmap.use.subset "0" --param make.year.ranges "1" --param make.single.year.ranges "1" /usr/share/xml/docbook/stylesheet/nwalsh/manpages/docbook.xsl $<
	date > $@


%.html: %.xml
	-rm html/$*/*.html
	xsltproc --nonet --param use.id.as.filename 1 --param admon.graphics 1 --stringparam admon.graphics.path ../images/ --stringparam html.stylesheet ../style.css  --stringparam callout.graphics.path ../images/callouts/ --stringparam base.dir html/$*/ /usr/share/xml/docbook/stylesheet/nwalsh/html/chunk.xsl $<
	date > $@

# xmlto -o html/$*  html $<

# xalan -in auto-multiple-choice.xml -xsl /usr/share/xml/docbook/stylesheet/nwalsh/html/docbook.xsl -param use.extensions 1 -param linenumbering.extension 1 -out html/a.html
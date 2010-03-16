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

include ../Makefile.conf

DOCBOOKS=$(filter-out $(wildcard *.in.xml),$(wildcard *.xml))

all: $(DOCBOOKS:.xml=.pdf) $(DOCBOOKS:.xml=.x) ; 

clean:
	rm -f *.{1,aux,cb,cb2,glo,idx,log,out,toc,tex,html,pdf,ext}
	rm -f modeles/*.tgz
	rm -f modeles/**/*.tgz
	rm -f html/auto-multiple-choice/*.html

%.tex: %.xml
	dblatex -t tex $< -o $@
	perl addlink.pl $@

%.pdf: %.tex
	pdflatex $< ; pdflatex $<

%.x: %.ext %.man %.html ;

%.ext: %.xml
	perl extrait-fichiers.pl --liste $@ $<

%.man: %.xml
	xsltproc --nonet --param man.charmap.use.subset "0" --param make.year.ranges "1" --param make.single.year.ranges "1" $(DOCBOOK_MAN_XSL) $<
	date > $@


%.html: %.xml doc-xhtml.xsl
	rm -f html/$*/*.html
	xsltproc --nonet --stringparam base.dir html/$*/ doc-xhtml.xsl $<
	date > $@


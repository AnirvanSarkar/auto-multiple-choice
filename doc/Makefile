
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
	xsltproc --nonet --param admon.graphics 1 --stringparam admon.graphics.path ../images/ --stringparam html.stylesheet ../style.css  --stringparam callout.graphics.path ../images/callouts/ --stringparam base.dir html/$*/ /usr/share/xml/docbook/stylesheet/nwalsh/html/chunk.xsl $<
	date > $@

# xmlto -o html/$*  html $<

# xalan -in auto-multiple-choice.xml -xsl /usr/share/xml/docbook/stylesheet/nwalsh/html/docbook.xsl -param use.extensions 1 -param linenumbering.extension 1 -out html/a.html
#
# Copyright (C) 2012-2021 Alexis Bienvenüe <paamc@passoire.fr>
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

SHELL=/bin/sh

include ../Makefile-all.conf

export PERLPATH

SVG=$(shell find . -name '*.svg')
EPS=$(SVG:.svg=.eps)

all: $(EPS)

%.eps: %.svg
# old-style or new-style arguments 
	inkscape --export-eps=$@ $< || inkscape --export-type=eps -o $@ $<

clean:
	-rm $(EPS)

test: $(EPS) FORCE
	@echo "Using qpdf"
	./all_tests
	@echo "Using pdftk"
	./selected_tests --extract-with pdftk

blind-test: $(EPS) FORCE
	@echo "Using qpdf"
	./all_tests --blind
	@echo "Using pdftk"
	./selected_tests --blind --extract-with pdftk
ifneq (,$(wildcard /usr/local/bin/sejda-console))
	@echo "Using sejda-console"
	./selected_tests --blind --extract-with sejda-console
endif

FORCE: ;

.PHONY: FORCE all clean test blind-test


#
# Copyright (C) 2008-2025 Alexis Bienvenüe <paamc@passoire.fr>
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

MODELS=$(wildcard */*.d)

all: $(MODELS:.d=.tgz)

%.tgz: %.d
	find $< -type d -exec chmod 0755 '{}' \;
	find $< -type f -exec chmod 0644 '{}' \;
ifeq ($(TAR_REPRODUCIBLE_ARGS),nonreproducible)
	tar -cz -f $@ -C $< .
else
	tar cn -C $< $(TAR_REPRODUCIBLE_ARGS) -O . | gzip $(GZIP_REPRODUCIBLE_ARGS) -c > $@
endif

clean:
	rm -f *.tgz
	rm -f **/*.tgz

.PHONY: clean all

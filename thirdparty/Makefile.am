# Author: Tobi Oetiker <tobi@oetiker.ch>
# License: Public Domain

AUTOMAKE_OPTIONS =  foreign

THIRDPARTY_DIR := $(shell pwd)

THIRDPARTY_DIST := $(shell test -d CPAN && find CPAN -type d -name ".??*" -prune -o -not -name ".*" -a -not -name "*~" -a -not -name "*.tmp"  -a -type f -print )

EXTRA_DIST = $(THIRDPARTY_DIST) $(wildcard bin/cpanm)

all-local: touch

# The package Locale::gettext needs libintl.a but we cannot give it using
# CPPFLAGS and LDFLAGS. Looking at Makefile.PL, we noticed that it is possible
# to set them using the CC variable. It looks weird to set CC for all perl
# packages! This fix comes from:
#     https://rt.cpan.org/Public/Bug/Display.html?id=16098
# export PKG_CONFIG_PATH
# undefine CFLAGS
# undefine LIBS
export PKG_CONFIG_PATH

bin/cpanm:
	$(URL_CAT) http://cpanmin.us | PERL_CPANM_HOME=$(THIRDPARTY_DIR) $(PERL) - -q --notest --local-lib $(THIRDPARTY_DIR) --save-dists $(THIRDPARTY_DIR)/CPAN --force App::cpanminus
Ore/bin/orepan_index.pl:
	PERL_CPANM_HOME=$(THIRDPARTY_DIR)/Ore $(THIRDPARTY_DIR)/bin/cpanm -q --notest  --local-lib $(THIRDPARTY_DIR)/Ore File::Which OrePAN

#
# The initial cpanm invokation.
#
# The purpose of OrePAN is only to provide a modules/02packages.details.txt.gz
# for installing offline.
# I use --no-skip-installed in order to prevent already installed modules
# (such as Digest::MD5) from not being installed in the mini CPAN. These
# already installed modules will be notified as:
#     Successfully reinstalled Digest-MD5-2.55
# This is necessary because cpanm is not going to fetch the module locally
# and thus the local offline invokations of cpanm cannot work.
touch: $(shell test -f ../PERL_MODULES~ && ! diff ../PERL_MODULES ../PERL_MODULES~ || echo ../PERL_MODULES)
touch: bin/cpanm Ore/bin/orepan_index.pl
	@echo "POPULATING OUR LOCAL mini CPAN"
	cat ../PERL_MODULES | grep -v ' ' | PERL_CPANM_HOME=$(THIRDPARTY_DIR) xargs $(PERL) $(THIRDPARTY_DIR)/bin/cpanm -q --self-contained --notest --local-lib-contained $(THIRDPARTY_DIR) --save-dists $(THIRDPARTY_DIR)/CPAN --mirror file://$(THIRDPARTY_DIR)/CPAN
	cat ../PERL_MODULES | grep ' ' | PERL_CPANM_HOME=$(THIRDPARTY_DIR) xargs -L1 $(PERL) $(THIRDPARTY_DIR)/bin/cpanm -q --self-contained --notest --local-lib-contained $(THIRDPARTY_DIR) --save-dists $(THIRDPARTY_DIR)/CPAN --mirror file://$(THIRDPARTY_DIR)/CPAN
	PERL5LIB=$(THIRDPARTY_DIR)/Ore/lib/perl5 $(THIRDPARTY_DIR)/Ore/bin/orepan_index.pl --repository $(THIRDPARTY_DIR)/CPAN 2>/dev/null >/dev/null
	touch touch

clean-local:
	ls -1 | $(GREP) -v Makefile | $(GREP) -v CPAN | $(GREP) -v bin | xargs rm -rf

distclean-local:
	ls -1 | $(GREP) -v Makefile. | xargs rm -rf
clean:
	@echo "We don't remove the mini CPAN because it takes so much time to rebuild."
	@echo "To force cleaning of the mini CPAN, use 'make clean-local'."
# Copyright (C) 2014 Tobias Oetiker
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

AUTOMAKE_OPTIONS = foreign

SUFFIXES = .1 .man .pm

SUBDIRS = lib

BIN = bin/@PACKAGE@ bin/system-kvm

PM :=  $(shell find lib/ -name "*.pm")

MAN = man/kvmadm.1
POD = doc/kvmadm.pod

GENERATED_EXTRADIST = $(MAN)
EXTRA_DIST = VERSION COPYRIGHT README.md LICENSE CHANGES AUTHORS $(PM) $(GENERATED_EXTRADIST)

YEAR := $(shell date +%Y)
DATE := $(shell date +%Y-%m-%d)

dist_bin_SCRIPTS = $(BIN)

imandir = $(mandir)/man1
iman_DATA = $(MAN)

svcdir = $(pkgdatadir)/smf
svc_DATA = smf/system-kvm.xml

doc/%.pod: bin/% configure
	$(AM_V_GEN)mkdir -p doc;grep -A100000 '=head1 NAME' $< > $@
        
man/%.1: bin/% configure
	$(AM_V_GEN)mkdir -p man; test $(POD2MAN) = "no" || $(POD2MAN) --release=$(VERSION) --center=$(PACKAGE_NAME) $<  > $@
        
README.md COPYRIGHT: configure
	$(AM_V_GEN)$(PERL) -i -p -e 's/\d{4}-\d{2}-\d{2}/$(DATE)/g;s/[0-4]\.\d+\.\d+(?:-\w+)?/$(PACKAGE_VERSION)/g'  $@

CHANGES: configure
	git log --simplify-merges --full-history --no-merges --pretty=format:'%ai %d  %s -- %an' > CHANGES
	
install-exec-hook:
	cd "$(DESTDIR)$(exec_prefix)" && $(PERL) -i -p -e 's{^#!.*perl.*}{#!$(PERL)};' $(BIN)

install-data-hook:
	test "$(SVCIMPORT)" = "yes" && svccfg import $(pkgdatadir)/smf/system-kvm.xml

dist-hook: $(POD) $(MAN) CHANGES
	$(AM_V_GEN)cd $(distdir) && $(PERL) -i -p -e '"$(PACKAGE_VERSION)" =~ /(\d+)\.(\d+)\.(\d+)/ and $$v = sprintf("%d.%03d%03d",$$1,$$2,$$3) and s/^\$$VERSION\s+=\s+".+?"/\$$VERSION = "$$d"/;'  $(BIN)
	$(GMAKE) $(MAN)


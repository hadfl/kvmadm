# Author: Tobi Oetiker <tobi@oetiker.ch>
# License: Public Domain

AUTOMAKE_OPTIONS =  foreign

SUFFIXES = .1 .man .pm

SUBDIRS = thirdparty lib

BIN = bin/@PACKAGE@ bin/system-kvm
PM :=  $(shell find lib/ -name "*.pm")
PROBES :=  $(shell find probes/ -name "*_probe")
MAN = man/@PACKAGE@.1
POD = doc/@PACKAGE@.pod

THIRDPARTY_DIR := $(shell pwd)/thirdparty

GENERATED_EXTRADIST = $(MAN)
EXTRA_DIST = VERSION COPYRIGHT README.md LICENSE CHANGES AUTHORS PERL_MODULES $(BIN) $(PM) \
	$(GENERATED_EXTRADIST) smf/system-kvm.xml.in

CHANGES:
	git log --full-history --simplify-merges --dense --no-merges > CHANGES

YEAR := $(shell date +%Y)
DATE := $(shell date +%Y-%m-%d)

if ENABLE_SVCINSTALL
      
svcdir = @SVCINSTALLDIR@
svc_DATA = smf/system-kvm.xml

endif

datadir = $(prefix)

README.md COPYRIGHT: VERSION
	$(AM_V_GEN)$(PERL) -i -p -e 's/\d{4}-\d{2}-\d{2}/$(DATE)/g;s/[0-4]\.\d+\.\d+/$(PACKAGE_VERSION)/g'  $@

README: README.md
	cp README.md README

imandir = $(mandir)/man1
iman_DATA = $(MAN)

doc/%.pod: bin/% VERSION
	$(AM_V_GEN)mkdir -p doc;grep -A100000 '=head1 NAME' $< > $@

man/%.1: bin/% VERSION
	$(AM_V_GEN)mkdir -p man; test $(POD2MAN) = "no" || $(POD2MAN) --release=$(VERSION) --center=$(PACKAGE_NAME) $<  > $@

dist_bin_SCRIPTS = $(BIN) $(PROBES)

dist-hook: $(POD)  $(MAN) CHANGES
	$(PERL) -i -p -e 's/#VERSION#/$(PACKAGE_VERSION)/g;s/#YEAR#/$(YEAR)/g;s/#DATE#/$(DATE)/g;'  $(distdir)/README.md $(distdir)/COPYRIGHT
	$(PERL) -i -p -e 's/^my .*# VERSION/my \$$VERSION = q{$(PACKAGE_VERSION)}; # VERSION/' $(distdir)/$(BIN)

install-exec-hook:
	[ "$(PERL5LIB)" = "" ] || cd "$(DESTDIR)$(exec_prefix)" && $(PERL) -i -p -e 's{.*# PERL5LIB}{use lib qw($(PERL5LIB)); # PERL5LIB}' $(BIN) || true
	cd "$(DESTDIR)$(exec_prefix)" && $(PERL) -i -p -e 's{^use .*# LIBDIR}{use lib qw($(libdir)); # LIBDIR}' $(BIN)
	cd "$(DESTDIR)$(exec_prefix)" && $(PERL) -i -p -e 's{^#!.*perl.*}{#!$(PERL)};' $(BIN)
	mkdir -p $(DESTDIR)$(libdir)
	[ ! -d $(THIRDPARTY_DIR)/lib/perl5 ] || cp -fr $(THIRDPARTY_DIR)/lib/perl5/* $(DESTDIR)$(libdir)

test:
	$(PERL) -Ithirdparty/lib/perl5 "-MExtUtils::Command::MM" "-e" "test_harness(0, 'lib','thirdparty/lib/perl5')" t/*.t

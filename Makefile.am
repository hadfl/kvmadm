#  Copyright (C) 2016 Tobias Oetiker

AUTOMAKE_OPTIONS = foreign

SUBDIRS = thirdparty lib

BIN = bin/$(SCRIPT_NAME) bin/system-kvm

MAN = man/$(SCRIPT_NAME).1
POD = doc/$(SCRIPT_NAME).pod
PROBES :=  $(shell find probes/ -name "*_probe")

#PERLTESTS := $(shell find t -name "*.t")

THIRDPARTY_DIR := $(shell pwd)/thirdparty

EXTRA_DIST = VERSION COPYRIGHT README.md LICENSE CHANGES AUTHORS PERL_MODULES $(BIN) $(MAN) \
	smf/system-kvm.xml.in

YEAR := $(shell date +%Y)
DATE := $(shell date +%Y-%m-%d)

if ENABLE_SVCINSTALL
svcdir = @SVCINSTALLDIR@
svc_DATA = smf/system-kvm.xml
endif

README.md COPYRIGHT : VERSION
	$(PERL) -i -p -e 's/(#VERSION#|\d+\.\d+\.\d+(?:-\w+)?)/$(PACKAGE_VERSION)/g;s/(#YEAR#|20[1-4]\d)/$(YEAR)/g;s/(#DATE#|20[1-9]\d-[01]\d-[0-3]\d)/$(DATE)/g;' $@

imandir = $(mandir)/man1
iman_DATA = $(MAN)

doc/%.pod: bin/% VERSION
	$(AM_V_GEN)mkdir -p doc;grep -A100000 '=head1 NAME' $< > $@

man/%.1: bin/% VERSION
	$(AM_V_GEN)mkdir -p man; test $(POD2MAN) = "no" || $(POD2MAN) --release=$(VERSION) --center=$(PACKAGE_NAME) $<  > $@

dist_bin_SCRIPTS = $(BIN) $(PROBES)

dist-hook: thirdparty
	$(PERL) -i -p -e 's/^our\s+\$$VERSION\s*=\s*".+?";/our \$$VERSION = "$(PACKAGE_VERSION)";/;'  $(distdir)/lib/$(CLASS_NAME)/*.pm

dist-hook: $(POD)
	$(PERL) -i -p -e 's/^my .*# VERSION/my \$$VERSION = q{$(PACKAGE_VERSION)}; # VERSION/' $(distdir)/$(BIN)

install-exec-hook:
	[ "$(PERL5LIB)" == "" ] || cd "$(DESTDIR)$(exec_prefix)" && $(PERL) -i -p -e 's{.*# PERL5LIB}{use lib qw($(PERL5LIB)); # PERL5LIB}' $(BIN) || true
	cd "$(DESTDIR)$(exec_prefix)" && $(PERL) -i -p -e 's{.*# LIBDIR}{use lib qw($(libdir)); # LIBDIR}' $(BIN)
	cd "$(DESTDIR)$(exec_prefix)" && $(PERL) -i -p -e 's{^#!.*perl.*}{#!$(PERL)};' $(BIN)
	cd "$(DESTDIR)$(libdir)/KVMadm" && $(PERL) -i -p -e 's{^my .*# RUNPATH}{my \$$RUN_PATH = "$(localstatedir)/run"; # RUNPATH};' Config.pm
	[ ! -d $(THIRDPARTY_DIR)/lib/perl5 ] || cp -fr $(THIRDPARTY_DIR)/lib/perl5/* $(DESTDIR)$(libdir)

#test:
#	$(PERL) "-MExtUtils::Command::MM" "-e" "test_harness(0, 'lib','thirdparty/lib/perl5')" t/*.t


#  Copyright (C) 2015 Tobias Oetiker

AC_INIT([kvmadm],m4_esyscmd([tr -d '\n' < VERSION]),[hadfl@omniosce.org])
AC_PREREQ([2.59])
AC_CONFIG_AUX_DIR(conftools)
SCRIPT_NAME=kvmadm
AC_SUBST(SCRIPT_NAME)
CLASS_NAME=KVMadm
AC_SUBST(CLASS_NAME)

# need this to allow long path names
AM_INIT_AUTOMAKE([1.9 tar-ustar foreign])
AM_MAINTAINER_MODE

m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES([yes])])

AC_PREFIX_DEFAULT(/opt/$PACKAGE_NAME-$PACKAGE_VERSION)

AC_ARG_VAR(PERL,   [Path to local perl binary])
AC_PATH_PROG(PERL, perl, no)
AC_PATH_PROG(CURL, curl, no)
AC_PATH_PROG(WGET, wget, no)
AC_PATH_PROG(POD2MAN, pod2man, no)

AC_ARG_ENABLE(svcinstall,
    AC_HELP_STRING(
        [--enable-svcinstall=DIR],
        [install smf manifest into given directory]
    ),
    [SVCINSTALLDIR=$enableval],
    [SVCINSTALLDIR=no]
)

AC_SUBST(SVCINSTALLDIR)
AM_CONDITIONAL(ENABLE_SVCINSTALL,[test $SVCINSTALLDIR != no])

URL_CAT="neither curl nor wget found"
if test -x "$WGET"; then
    URL_CAT="$WGET -O -"
else
    if test -x "$CURL"; then
        URL_CAT="$CURL --location --insecure"
    fi
fi

AC_SUBST(URL_CAT)

ac_perl_version="5.10.1"

if test "x$PERL" != "x"; then
  AC_MSG_CHECKING(for perl version greater than or equal to $ac_perl_version)
  $PERL -e "use $ac_perl_version;" >/dev/null 2>&1
  if test $? -ne 0; then
    AC_MSG_RESULT(no);
    AC_MSG_ERROR(at least version 5.10.1 is required to run mojolicious)
  else
    AC_MSG_RESULT(ok);
  fi
else
  AC_MSG_ERROR(could not find perl)
fi

AC_PROG_GREP

AC_ARG_VAR(GMAKE,   [Path to local GNU Make binary])
AC_PATH_PROGS(GMAKE, [gnumake gmake make])

AC_MSG_CHECKING([for gnu make availablility])
if  ( $GMAKE --version 2> /dev/null | $GREP GNU  > /dev/null 2>&1 );  then
    AC_MSG_RESULT([$GMAKE is GNU make])
else
    AC_MSG_ERROR([GNU make not found. Try setting the GMAKE environment variable.])
fi

AC_ARG_ENABLE(pkgonly,
        AC_HELP_STRING([--enable-pkgonly],
                        [Skip all checking]))
AC_SUBST(enable_pkgonly)

actual_prefix=$prefix
if test x$actual_prefix = xNONE; then
    actual_prefix=$ac_default_prefix
fi
AC_SUBST(actual_prefix)

actual_exec_prefix=$exec_prefix
if test x$actual_exec_prefix = xNONE; then
    actual_exec_prefix=$actual_prefix
fi
AC_SUBST(actual_exec_prefix)

actual_datarootdir=$datarootdir
if test x$actual_datarootdir = x'${prefix}/share'; then
    actual_datarootdir=$actual_prefix/share
fi

actual_mandir=$mandir
if test x$actual_mandir = x'${datarootdir}/man'; then
    actual_mandir=$actual_datarootdir/man
fi
AC_SUBST(actual_mandir)

AC_ARG_VAR(PERL5LIB,   [Colon separated list of perl library directories])
AC_SUBST(PERL5LIB)

AC_CONFIG_FILES([
    Makefile
    lib/Makefile
    thirdparty/Makefile
    smf/system-kvm.xml
])

AC_SUBST(VERSION)

AC_OUTPUT

cat <<NOTES

** CONFIGURE DONE **********************************************

Settings:

  PERL5LIB = ${PERL5LIB:-"not set"}
  PERL = $PERL

The Makefiles use GNU make functionality.
Continue installation with

  $GMAKE install

NOTES

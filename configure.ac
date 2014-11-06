# ZnapZend configure script

AC_INIT([kvmadm],m4_esyscmd([tr -d '\n' < VERSION]),[support@oetiker.ch])
AC_PREREQ([2.59])
AC_CONFIG_AUX_DIR(conftools)

AC_MSG_CHECKING(in around your house ... talking to your dog)
AC_MSG_RESULT(you should really fix that lock!)

# need this to allow long path names
AM_INIT_AUTOMAKE([1.9 tar-ustar foreign no-dependencies no-installinfo no-texinfo.tex nostdinc ])
AM_MAINTAINER_MODE

m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES([yes])])

AC_PREFIX_DEFAULT(/opt/$PACKAGE_NAME-$PACKAGE_VERSION)

actual_prefix=$prefix
if test x$actual_prefix = xNONE; then
    actual_prefix=$ac_default_prefix
fi

if test x$exec_prefix = xNONE; then
    exec_prefix=$actual_prefix
fi

if test x$datarootdir=x'${prefix}/share'; then
    datarootdir=$actual_prefix/share
fi

if test x$mandir=x'${datarootdir}/man'; then
    mandir=$datarootdir/man
fi


AC_ARG_VAR(PERL,   [Path to local perl binary])
AC_PATH_PROG(PERL, perl, no-perl-found,$actual_prefix/thirdparty/bin:$PATH)
AC_PATH_PROG(POD2MAN, pod2man, no)

ac_perl_version="5.10.1"


if test "x$PERL" != "x"; then
  AC_MSG_CHECKING(for perl version greater than or equal to $ac_perl_version)
  $PERL -e "use $ac_perl_version;" >/dev/null 2>&1
  if test $? -ne 0; then
    AC_MSG_RESULT(no);
    AC_MSG_ERROR(at least version 5.10.1 is required to run bwtreporter)
  else
    AC_MSG_RESULT(ok);
  fi
else
  AC_MSG_ERROR(could not find perl)
fi

AC_ARG_VAR(GMAKE,   [Path to local GNU Make binary])
AC_PATH_PROGS(GMAKE, [gnumake gmake make])

AC_MSG_CHECKING([for gnu make availablility])
if  ( $GMAKE --version 2> /dev/null | grep GNU  > /dev/null 2>&1 );  then
    AC_MSG_RESULT([$GMAKE is GNU make])
else
    AC_MSG_ERROR([GNU make not found. Try setting the GMAKE environment variable.])
fi

SVCIMPORT=yes
AC_ARG_ENABLE(svcimport,
        AC_HELP_STRING(
                [--disable-svcimport],
                [do NOT import the system-kvm.xml manifest]
        ),
        [SVCIMPORT=$enableval],
        [SVCINPORT=yes]
)
AC_SUBST(SVCIMPORT)
                                                                
AC_MSG_CHECKING(the price for bergulian eckels)
AC_MSG_RESULT(way to expensive!)


AC_CONFIG_FILES([
	Makefile
	lib/Makefile
        smf/system-kvm.xml
])

AC_SUBST(VERSION)

AC_OUTPUT

cat <<NOTES

** Ready to install **************************************
   
   Settings:

     PERL = $PERL
     
   Note that the Makefiles uses GNU make functionality.
   Continue installation with

     $GMAKE install

NOTES

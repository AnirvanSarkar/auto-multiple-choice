AC_INIT([znapzend], 1.3.1,[him@foo.bar])
AC_PREREQ([2.59])

AC_LANG_PUSH([C++])

AC_CONFIG_AUX_DIR(conftools)

# need this to allow long path names
AM_INIT_AUTOMAKE([1.9 tar-ustar foreign no-dependencies no-installinfo no-texinfo.tex nostdinc])


# When AM_MAINTAINER_MODE is disabled, the build files (Makefile.in...) won't
# be updated automatically when configure.ac is changed.
AM_MAINTAINER_MODE([disable])

m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES([yes])])

AC_ARG_VAR(PERL,   [Path to local perl binary])
AC_PATH_PROG(PERL, perl, no)
AC_PATH_PROG(CURL, curl, no)
AC_PATH_PROG(WGET, wget, no)
AC_PATH_PROG(POD2MAN, pod2man, no)

PKG_CHECK_MODULES(LIBFFI, [libffi])
PKG_CHECK_MODULES(NETPBM, [netpbm])
PKG_CHECK_MODULES(POPPLER, [poppler])
PKG_CHECK_MODULES(GTK3, [gtk+-3.0])
PKG_CHECK_MODULES(GLIB, [glib-2.0])
PKG_CHECK_MODULES(LIBRSVG, [librsvg-2.0])
PKG_CHECK_MODULES(CAIRO, [cairo])
PKG_CHECK_MODULES(OPENCV, [opencv])
PKG_CHECK_MODULES(PANGO, [pango])
PKG_CHECK_MODULES(FREETYPE, [freetype2])

PKG_CHECK_MODULES([IMAGEMAGICK], [imagemagick < 7],
   [AC_DEFINE([HAVE_IMAGEMAGICK], [1], [Use ImageMagick])],
   [PKG_CHECK_MODULES([GRAPHICSMAGICK], [graphicsmagick],
       [AC_DEFINE([HAVE_GRAPHICSMAGICK], [1], [Use GraphicsMagick])
    ])
])


AC_ARG_WITH(gettext, AC_HELP_STRING([--with-gettext=PREFIX],
            [Support translations using Gettext]),
            [gettext_prefix=$withval], [])

if test "x$gettext_prefix" != "x"; then
    LDFLAGS="${LDFLAGS} -L$gettext/lib"
    CPPFLAGS="${CPPFLAGS} -I$gettext/include"
    PATH="${PATH}:$gettext/bin"
elif test -f "/usr/local/lib/libintl.so" ; then
    LDFLAGS="${LDFLAGS} -L/usr/local/lib"
fi
AC_CHECK_LIB([intl], [gettext])
AC_CHECK_HEADER([libintl.h],
    AC_CHECK_FUNC([gettext], [gettext=yes], gettext=no), gettext=no)
AC_PATH_PROG([GETTEXT], [gettext], [no])
AC_PATH_PROG([MSGFMT], [msgfmt], [no])
if test "x$GETTEXT" = "xno" -o "x$MSGFMT" = "xno" ; then
    AC_MSG_ERROR([Gettext not found. Try to set --with-gettext=PREFIX.])
else
    AC_SUBST([LOCALEDEFS], [-DLOCALEDIR=\\\"$localedir\\\"])
    AC_SUBST([CATALOG], [LC_MESSAGES])
fi

URL_CAT="neither curl nor wget found"
if test -x "$WGET"; then
    URL_CAT="$WGET -O -"
else
    if test -x "$CURL"; then
        URL_CAT="$CURL --location --insecure"
    fi
fi

AC_SUBST(URL_CAT)


if test "x$PERL" = "x"; then
  AC_MSG_ERROR(could not find perl)
fi


AC_MSG_CHECKING(is perl reasonably complete)
if $PERL -MExtUtils::MakeMaker -e '' 2>/dev/null; then
  AC_MSG_RESULT(yes. ExtUtils::MakeMaker is available);
else
  AC_MSG_RESULT(no)
  AC_MSG_ERROR([a complete perl ('perl-core' in the redhat world) installation is required])
fi

AC_MSG_CHECKING([if require a c compiler to get perl modules compiled])
if $PERL -MIO::Socket::IP -e 'exit($IO::Socket::IP::VERSION < 0.37)' 2>/dev/null; then
    AC_MSG_RESULT(no)
else
    AC_MSG_RESULT(yes)
    perl_cc=`$PERL -MConfig -e 'print $Config{cc}'`
    AC_PATH_PROG(PERL_CC_PATH, $perl_cc, no)
    AC_MSG_CHECKING(is perls favorite c compiler ($perl_cc) available)
    if test x$PERL_CC_PATH = xno; then
        AC_MSG_RESULT(no)
        AC_MSG_ERROR([perl needs the '$perl_cc' compiler package to build dependencies])
    else
        AC_MSG_RESULT(yes)
    fi
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

AC_ARG_ENABLE(doc,
        AC_HELP_STRING([--enable-doc],
                        [Enable building of PDF and HTML documentation using DocBook]))
AC_SUBST(enable_doc)

actual_prefix=$prefix
if test x$actual_prefix = xNONE; then
    actual_prefix=$ac_default_prefix
fi

AC_ARG_VAR(PERL5LIB,   [Colon separated list of perl library directories])
AC_SUBST(PERL5LIB)

AC_CONFIG_FILES([
    Makefile
    thirdparty/Makefile
    lib/Makefile
    I18N/Makefile.in
])

AC_SUBST(VERSION)

AC_OUTPUT

cat <<NOTES
Configure done. Summary:

  PERL5LIB = ${PERL5LIB:-"not set"}
  PERL = $PERL

The Makefiles use GNU make functionality.
Continue installation with

  $GMAKE install
NOTES

AC_INIT([auto-multiple-choice],[1.3.1],[him@foo.bar])
AC_PREREQ([2.69])

AC_CONFIG_AUX_DIR(autoconf)
AC_CONFIG_MACRO_DIR(autoconf/m4)

AC_PROG_CC
AC_PROG_CXX
AC_PROG_GREP
AC_PROG_SED

# need this to allow long path names
AM_INIT_AUTOMAKE([1.9 tar-ustar foreign no-dependencies no-installinfo no-texinfo.tex nostdinc])

# AM_GNU_GETTEXT([external])

# When AM_MAINTAINER_MODE is enabled, the build files (Makefile.in...) will
# be updated automatically when Makefile.am or configure.ac is changed.
AM_MAINTAINER_MODE([enable])

m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES([yes])])

AC_ARG_WITH([minicpan],
    AS_HELP_STRING([--disable-minicpan], [Disable local installation of Perl
    modules in order to use your system-installed Perl modules.]),
    [USE_MINICPAN=$enableval], [USE_MINICPAN=yes])

#
# Check for a Perl binary. Also check that MakeMaker is available (for
# building cpan modules).
#
AC_ARG_VAR(PERL,   [Path to local perl binary])
AC_PATH_PROG(PERL, perl, no)
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

#
# Check for curl or wget.
#
AC_PATH_PROG(CURL, curl, no)
AC_PATH_PROG(WGET, wget, no)
URL_CAT="neither curl nor wget found"
if test -x "$WGET"; then
    URL_CAT="$WGET -O -"
else
    if test -x "$CURL"; then
        URL_CAT="$CURL --location --insecure"
    fi
fi
AC_SUBST(URL_CAT)

PKG_CHECK_MODULES(SQLITE, [sqlite3])
PKG_CHECK_MODULES(LIBFFI, [libffi])
PKG_CHECK_MODULES(NETPBM, [netpbm])
PKG_CHECK_MODULES(GLIB, [glib-2.0 gio-2.0])
PKG_CHECK_MODULES(GTK3, [gtk+-3.0])
PKG_CHECK_MODULES(GOBJECT_INTROSPECTION, [gobject-introspection-1.0 >= 0.10.0])
PKG_CHECK_MODULES(POPPLER, [poppler poppler-glib])
PKG_CHECK_MODULES(OPENCV, [opencv])
PKG_CHECK_MODULES(LIBRSVG, [librsvg-2.0])
PKG_CHECK_MODULES(CAIRO, [cairo])
PKG_CHECK_MODULES(PANGO, [pango pangocairo])
PKG_CHECK_MODULES(FREETYPE, [freetype2])

#
# Create the `base' modules list.
#
# We first remove any module that already exists in the Perl's system install;
# for example Digest::MD5 is shipped in some Perl distributions. Later, we
# will add some alternative modules ImageMagick and GraphicsMagick.
test -f PERL_MODULES && mv PERL_MODULES PERL_MODULES~
while read m; do
    PERL5LIB= $PERL -M$m -e '' 2>/dev/null || echo $m
done > PERL_MODULES << PERL_MODULES
Digest::MD5
Module::Load::Conditional
Archive::Zip
Clone
DBD::SQLite
Email::MIME
Email::Sender
File::BaseDir
File::MimeInfo
OpenOffice::OODoc
Text::CSV
XML::Simple
XML::Writer
Glib::Object::Introspection
Gtk3
Locale::gettext
PERL_MODULES

#
# Check for either ImageMagick or GraphicsMagick installed. If one or the
# other is found, add it to the list of PERL_MODULES. ImageMagick is
# first searched for.
#
PKG_CHECK_MODULES([IMAGEMAGICK], [imagemagick < 7],
   [echo "Image::Magick" >> PERL_MODULES],
   [PKG_CHECK_MODULES([GRAPHICSMAGICK], [graphicsmagick],
       [echo "Graphics::Magick" >> PERL_MODULES],
       [AC_MSG_ERROR([either ImageMagick or GraphicsMagick is required.
       For example, try to set IMAGEMAGICK_{CFLAGS,LIBS}.])])
])

#
# Check the necessary Perl modules if the mini CPAN is not used.
#
PERL_MODULES_STATUS="using mini-CPAN"
if test "x$USE_MINICPAN" != xyes; then
    PERL_MODULES_STATUS="using system Perl modules (no missing module)"
    MISSING_PERL_MODULES=""
    if test "$enable_pkgonly" != yes; then
    for module in m4_esyscmd([tr '\n' ' ' < PERL_MODULES]); do
        AC_MSG_CHECKING([for perl module '$module'])
        if ${PERL} -I`dirname $0`/thirdparty/lib/perl5 -e 'my($m,$v) = split /\@/, q{'$module'};eval "use $m"; exit 1 if $@; exit 1 if not $v or eval(q{$}.$m.q{::VERSION}) ne $v' ; then
            AC_MSG_RESULT([Ok])
        else
            MISSING_PERL_MODULES="${MISSING_PERL_MODULES} $module"
            AC_MSG_WARN([missing])
        fi
    done
    fi
fi


#
# In case we use the mini CPAN only:
# Check for gettext and libintl.a so that we can compile Locale::gettext.
#
AC_ARG_WITH(gettext, AS_HELP_STRING(
    [--with-gettext=PREFIX],
    [Prefix pointing to where gettext is installed.]),
    [GETTEXT_PREFIX=$withval], [])
if test "x$USE_MINICPAN" = xyes; then
    if test "x$GETTEXT_PREFIX" != x; then
        CPPFLAGS="${CPPFLAGS} -I$GETTEXT_PREFIX/include"
        LDFLAGS="${LDFLAGS} -L$GETTEXT_PREFIX/lib"
        PATH="$GETTEXT_PREFIX/bin:${PATH}"
    fi
    AC_SEARCH_LIBS(gettext, [intl], [], AC_MSG_ERROR([libintl.a could not be found.
        Try using --with-gettext=PREFIX or LDFLAGS=-L/path/to/gettextx/lib]))
    AC_CHECK_HEADER(libintl.h, [], AC_MSG_ERROR([libintl.h could not be found.
        Try using --with-gettext=PREFIX or CPPFLAGS=-I/path/to/gettext/include]))
    # These two programs are only useful during the build of the manpages.
    # In fact, manpages are already built in dist tarballs. But let's ask
    # for gettext anyway.
    AC_PATH_PROG([GETTEXT], [gettext], [no])
    AC_PATH_PROG([MSGFMT], [msgfmt], [no])
    if test "x$GETTEXT" = "xno" -o "x$MSGFMT" = "xno" ; then
        AC_MSG_ERROR([gettext or msgfmt not found. Try to set --with-gettext=PREFIX.])
    fi
fi

#
# When using the mini CPAN only:
# The Perl module Locale::gettext, at least up to 1.07 (as seen in april 2018),
# has issues at handling custom LDFLAGS and CPPFLAGS for libintl.a, which is
# unfortunate on BSD and macOS systems. The workaround is to install instead
# a development version (i.e., > 1.0.7) that rely on Config::Autoconf and
# accepts the use of INC (i.e., CPPFLAGS) and LIBS (i.e., LDFLAGS) in the
# 'perl Makefile.PL' call.
#
if test "x$USE_MINICPAN" = xyes && test "x$GETTEXT_PREFIX" != x ; then
    $SED "/Locale::gettext/d" PERL_MODULES > temp && mv temp PERL_MODULES
    cat >> PERL_MODULES <<PERL_MODULES
Config::AutoConf
https://github.com/vandry/Perl-Locale-gettext/archive/bf143b9ad157105992afbdbf806c9b90d90ec48b.tar.gz --configure-args "INC='$CPPFLAGS' LIBS='$LDFLAGS $LIBS'"
PERL_MODULES
fi

#
# When using the mini CPAN only:
# Image::Magick has the same kind of issues as Locale::gettext on BSD/macOS
# systems.
#
if test "x$USE_MINICPAN" = xyes; then
    $SED "/Image::Magick/d" PERL_MODULES > temp && mv temp PERL_MODULES
    cat >> PERL_MODULES <<PERL_MODULES
Image::Magick --configure-args "INC='$(pkg-config --cflags imagemagick)' LIBS='$(pkg-config --libs imagemagick)'"
PERL_MODULES
fi


AC_ARG_VAR(GMAKE,   [Path to local GNU Make binary])
AC_PATH_PROGS(GMAKE, [gnumake gmake make])

AC_MSG_CHECKING([for gnu make availablility])
if  ( $GMAKE --version 2> /dev/null | $GREP GNU  > /dev/null 2>&1 );  then
    AC_MSG_RESULT([$GMAKE is GNU make])
else
    AC_MSG_ERROR([GNU make not found. Try setting the GMAKE environment variable.])
fi

AC_ARG_ENABLE(doc,
    AS_HELP_STRING([--enable-doc],[Enable building of PDF and HTML documentation using DocBook]))
AC_SUBST(enable_doc)

actual_prefix=$prefix
if test x$actual_prefix = xNONE; then
    actual_prefix=$ac_default_prefix
fi

AC_ARG_VAR(PERL5LIB,   [Colon separated list of perl library directories])
AC_SUBST(PERL5LIB)

if test x"$enable_doc" = xyes; then
    # Using fontconfig, we check that all required fonts are available.
    AC_PATH_PROG(FC_LIST, fc-list, no)
    missing_font=""
    while read font; do
        $FC_LIST --quiet "$font" || missing_font="$missing_font, $font"
    done << EOF
    Dejavu Sans
    DejaVu Serif
    DejaVu Sans
    DejaVu Sans Mono
    IPAexMincho
    IPAexGothic
EOF
    if test x$missing_font != x; then
        AC_MSG_ERROR([Missing fonts for building the auto-multiple-choice book:
        $missing_font])
    fi
fi


AC_CONFIG_FILES([
    Makefile
    thirdparty/Makefile
    lib/Makefile
    I18N/Makefile
    libexec/exec/Makefile
])

AC_SUBST(VERSION)

if test "x$MISSING_PERL_MODULES" != x; then
cat << ERR
**** Error:

Some Perl modules have not been found. Either install them with somthing like:
    cpan ${MISSING_PERL_MODULES}

Otherwise, you can use the local mini CPAN with --enable-minicpan.
ERR
fi

AC_OUTPUT

cat <<NOTES
configure done. Summary:

  PERL5LIB = ${PERL5LIB:-"not set"}
  PERL = $PERL
  PERL_MODULES_STATUS = ${PERL_MODULES_STATUS}

The Makefiles use GNU make functionality. Continue with:

  $GMAKE
NOTES

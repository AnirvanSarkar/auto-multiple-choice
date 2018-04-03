Developer mode (bare project after a git clone)
==============================================

In this mode, `configure` won't be available. Instead, you are provided with
a bootstrap script that will call the appropriate autotools. You also need to
run ./configure --enable-maintainer-mode so that the tools for rebuilding the
doc and sty (i.e., latex) are looked for.

    ./autogen.sh
    ./configure --enable-maintainer-mode

Distribution mode (dist tarball downloaded by a user)
=====================================================

In this case you just have to run

    ./configure
    make
    make install

Example of projects:

- https://github.com/oetiker/znapzend/blob/master/Makefile.am
- https://github.com/p12tic/wnckmm/blob/master/configure.ac


I think that automultiplechoice.sty, doc/*.pdf, doc/*.html and
doc/auto-multiple-choice.1 must be in 

Files being subsitutued on each 'make':

- AMC-gui.pl.in
- AMC-latex-link.pl.in
- auto-multiple-choice.desktop.in
- auto-multiple-choice.spec.in
- Makefile
- auto-multiple-choice.in
- AMC-gui-apropos.glade.in
- authors-subs.xsl
- local/deb-auto-changelog.in
- doc/auto-multiple-choice.en.in.xml
- doc/amcdocstyle.sty.in
- doc/doc-xhtml-site.fr.xsl.in
- doc/auto-multiple-choice.ja.in.xml
- doc/doc-xhtml-site.en.xsl.in
- doc/doc-xhtml-site.ja.xsl.in
- doc/auto-multiple-choice.fr.in.xml
- doc/doc-xhtml.xsl.in
- I18N/po-clean.pl.in
- AMC-perl/AMC/Basic.pm.in
- doc/sty/Makefile
- doc/sty/automultiplechoice.dtx.in


### PDF and HTML documentation rebuilt on each 'make'

This is because 


autogen.sh vs bootstrap.sh : https://lists.gnu.org/archive/html/octave-maintainers/2012-09/msg00272.html

- main binary in $PREFIX/bin/
- perl scripts in $PREFIX/lib/AMC/perl
- compiled binaries in $PREFIX/lib/AMC/exec
- perl5 packages (must be in includePath)


/usr/local/Cellar/auto-multiple-choice/1.3.0.2199
├── bin
│  └── auto-multiple-choice
├── lib
│  └── AMC
│     ├── exec
│     │  ├── AMC-buildpdf
│     │  └── AMC-detect
│     └── perl
│        ├── AMC-analyse.pl
│        ├── ...
│        ├── AMC-gui.pl
│        └── AMC-regroupe.pl
├── libexec
│  ├── lib
│  │  ├── libgcc_s.1.dylib
│  │  ├── libgcj.16.dylib
│  │  ├── libiconv.2.dylib
│  │  ├── libstdc++.6.dylib
│  │  ├── libz.1.dylib
│  │  └── perl5
│  │     ├── AMC
│  │     │  ├── Annotate.pm
│  │     │  ├── Basic.pm
│  │     │  ├── Boite.pm
│  │     │  ├── Calage.pm
│  │     │  ├── Config.pm
│  │     │  ├── Data.pm
│  │     │  ├── DataModule
│  │     │  │  ├── association.pm
│  │     │  │  ├── capture.pm
│  │     │  │  ├── layout.pm
│  │     │  │  ├── report.pm
│  │     │  │  └── scoring.pm
│  │     │  ├── DataModule.pm
│  │     │  ├── Exec.pm
│  │     │  ├── Export
│  │     │  │  ├── CSV.pm
│  │     │  │  ├── List.pm
│  │     │  │  ├── ods.pm
│  │     │  │  ├── register
│  │     │  │  │  ├── CSV.pm
│  │     │  │  │  ├── List.pm
│  │     │  │  │  └── ods.pm
│  │     │  │  └── register.pm
│  │     │  ├── Export.pm
│  │     │  ├── FileMonitor.pm
│  │     │  ├── Filter
│  │     │  │  ├── latex.pm
│  │     │  │  ├── plain.pm
│  │     │  │  ├── register
│  │     │  │  │  ├── latex.pm
│  │     │  │  │  └── plain.pm
│  │     │  │  └── register.pm
│  │     │  ├── Filter.pm
│  │     │  ├── Gui
│  │     │  │  ├── Association.glade
│  │     │  │  ├── Association.pm
│  │     │  │  ├── Avancement.pm
│  │     │  │  ├── Commande.pm
│  │     │  │  ├── Manuel.glade
│  │     │  │  ├── Manuel.pm
│  │     │  │  ├── Notes.glade
│  │     │  │  ├── Notes.pm
│  │     │  │  ├── PageArea.pm
│  │     │  │  ├── Prefs.pm
│  │     │  │  ├── WindowSize.pm
│  │     │  │  ├── Zooms.glade
│  │     │  │  └── Zooms.pm
│  │     │  ├── Messages.pm
│  │     │  ├── NamesFile.pm
│  │     │  ├── Path.pm
│  │     │  ├── Print
│  │     │  │  ├── cups.pm
│  │     │  │  └── cupslp.pm
│  │     │  ├── Print.pm
│  │     │  ├── Queue.pm
│  │     │  ├── Scoring.pm
│  │     │  ├── ScoringEnv.pm
│  │     │  ├── State.pm
│  │     │  ├── Subprocess.pm
│  │     │  └── Substitute.pm
│  │     ├── Archive
│  │     │  ├── Zip
│  │     │  │  ├── Archive.pm
│  │     │  │  ├── BufferedFileHandle.pm
│  │     │  │  ├── DirectoryMember.pm
│  │     │  │  ├── FAQ.pod
│  │     │  │  ├── FileMember.pm
│  │     │  │  ├── Member.pm
│  │     │  │  ├── MemberRead.pm
│  │     │  │  ├── MockFileHandle.pm
│  │     │  │  ├── NewFileMember.pm
│  │     │  │  ├── StringMember.pm
│  │     │  │  ├── Tree.pm
│  │     │  │  └── ZipFileMember.pm
│  │     │  └── Zip.pm
│  │     ...
│  └── man
│     ├── man1
│     │  └── config_data.1
│     ├── man3
│     │  ├── File::BaseDir.3
│     │  ├── File::IconTheme.3
│     │  ├── File::UserDirs.3
│     │  ├── Glib.3
│     │  ├── Glib::BookmarkFile.3
│     │  ├── Glib::Boxed.3
│     │  ├── Glib::Bytes.3
│     │  ├── Glib::CodeGen.3
│     │  ├── Glib::devel.3
│     │  ├── Glib::Error.3
│     │  ├── Glib::Flags.3
│     │  ├── Glib::GenPod.3
│     │  ├── Glib::index.3
│     │  ├── Glib::KeyFile.3
│     │  ├── Glib::Log.3
│     │  ├── Glib::MainLoop.3
│     │  ├── Glib::MakeHelper.3
│     │  ├── Glib::Markup.3
│     │  ├── Glib::Object.3
│     │  ├── Glib::Object::Introspection.3
│     │  ├── Glib::Object::Subclass.3
│     │  ├── Glib::OptionContext.3
│     │  ├── Glib::OptionGroup.3
│     │  ├── Glib::Param::Boolean.3
│     │  ├── Glib::Param::Double.3
│     │  ├── Glib::Param::Enum.3
│     │  ├── Glib::Param::Flags.3
│     │  ├── Glib::Param::GType.3
│     │  ├── Glib::Param::Int.3
│     │  ├── Glib::Param::Int64.3
│     │  ├── Glib::Param::String.3
│     │  ├── Glib::Param::UInt.3
│     │  ├── Glib::Param::UInt64.3
│     │  ├── Glib::Param::Unichar.3
│     │  ├── Glib::ParamSpec.3
│     │  ├── Glib::ParseXSDoc.3
│     │  ├── Glib::Signal.3
│     │  ├── Glib::Type.3
│     │  ├── Glib::Utils.3
│     │  ├── Glib::Variant.3
│     │  ├── Glib::VariantType.3
│     │  ├── Glib::version.3
│     │  ├── Glib::xsapi.3
│     │  ├── Module::Build.3
│     │  ├── Module::Build::API.3
│     │  ├── Module::Build::Authoring.3
│     │  ├── Module::Build::Base.3
│     │  ├── Module::Build::Bundling.3
│     │  ├── Module::Build::Compat.3
│     │  ├── Module::Build::ConfigData.3
│     │  ├── Module::Build::Cookbook.3
│     │  ├── Module::Build::Notes.3
│     │  ├── Module::Build::Platform::aix.3
│     │  ├── Module::Build::Platform::cygwin.3
│     │  ├── Module::Build::Platform::darwin.3
│     │  ├── Module::Build::Platform::Default.3
│     │  ├── Module::Build::Platform::MacOS.3
│     │  ├── Module::Build::Platform::os2.3
│     │  ├── Module::Build::Platform::Unix.3
│     │  ├── Module::Build::Platform::VMS.3
│     │  ├── Module::Build::Platform::VOS.3
│     │  ├── Module::Build::Platform::Windows.3
│     │  ├── Module::Build::PPMMaker.3
│     │  ├── Pango.3
│     │  ├── Pango::AttrBackground.3
│     │  ├── Pango::AttrColor.3
│     │  ├── Pango::AttrFallback.3
│     │  ├── Pango::AttrFamily.3
│     │  ├── Pango::AttrFontDesc.3
│     │  ├── Pango::AttrForeground.3
│     │  ├── Pango::AttrGravity.3
│     │  ├── Pango::AttrGravityHint.3
│     │  ├── Pango::Attribute.3
│     │  ├── Pango::AttrInt.3
│     │  ├── Pango::AttrIterator.3
│     │  ├── Pango::AttrLanguage.3
│     │  ├── Pango::AttrLetterSpacing.3
│     │  ├── Pango::AttrList.3
│     │  ├── Pango::AttrRise.3
│     │  ├── Pango::AttrScale.3
│     │  ├── Pango::AttrShape.3
│     │  ├── Pango::AttrSize.3
│     │  ├── Pango::AttrStretch.3
│     │  ├── Pango::AttrStrikethrough.3
│     │  ├── Pango::AttrStrikethroughColor.3
│     │  ├── Pango::AttrString.3
│     │  ├── Pango::AttrStyle.3
│     │  ├── Pango::AttrUnderline.3
│     │  ├── Pango::AttrUnderlineColor.3
│     │  ├── Pango::AttrVariant.3
│     │  ├── Pango::AttrWeight.3
│     │  ├── Pango::Cairo.3
│     │  ├── Pango::Cairo::Context.3
│     │  ├── Pango::Cairo::Font.3
│     │  ├── Pango::Cairo::FontMap.3
│     │  ├── Pango::Color.3
│     │  ├── Pango::Context.3
│     │  ├── Pango::Font.3
│     │  ├── Pango::FontDescription.3
│     │  ├── Pango::FontFace.3
│     │  ├── Pango::FontFamily.3
│     │  ├── Pango::FontMap.3
│     │  ├── Pango::FontMetrics.3
│     │  ├── Pango::Fontset.3
│     │  ├── Pango::Gravity.3
│     │  ├── Pango::index.3
│     │  ├── Pango::Language.3
│     │  ├── Pango::Layout.3
│     │  ├── Pango::LayoutIter.3
│     │  ├── Pango::LayoutLine.3
│     │  ├── Pango::Matrix.3
│     │  ├── Pango::Renderer.3
│     │  ├── Pango::Script.3
│     │  ├── Pango::ScriptIter.3
│     │  ├── Pango::TabArray.3
│     │  ├── Pango::version.3
│     │  ├── Test::MockModule.3
│     │  └── XML::Parser::Expat.3
│     ├── pdftk.1
│     ├── pdftk.1.html
│     └── pdftk.1.txt
├── README
├── README.md
└── share
   ├── auto-multiple-choice
   │  ├── icons
   │  │  ├── amc-annotate.svg
   │  │  ├── amc-auto-assoc.svg
   │  │  ├── amc-auto-capture.svg
   │  │  ├── amc-group.svg
   │  │  ├── amc-manual-assoc.svg
   │  │  ├── amc-manual-capture.svg
   │  │  ├── amc-mark.svg
   │  │  ├── amc-send.svg
   │  │  └── auto-multiple-choice.svg
   │  └── models
   │     ├── ar
   │     │  ├── directory.xml
   │     │  ├── groups.tgz
   │     │  ├── scoring.tgz
   │     │  ├── separate.tgz
   │     │  └── simple.tgz
   │     ├── en
   │     │  ├── directory.xml
   │     │  ├── groups.tgz
   │     │  ├── Nominative-sheets-separateanswersheet.tgz
   │     │  ├── Nominative-sheets.tgz
   │     │  ├── scoring.tgz
   │     │  ├── separate.tgz
   │     │  ├── simple-txt.tgz
   │     │  └── simple.tgz
   │     ├── fr
   │     │  ├── bareme.tgz
   │     │  ├── directory.xml
   │     │  ├── ensemble.tgz
   │     │  ├── groupes.tgz
   │     │  ├── Pre-remplies-ensemble.tgz
   │     │  ├── Pre-remplies.tgz
   │     │  ├── simple-txt.tgz
   │     │  └── simple.tgz
   │     └── ja
   │        ├── directory.xml
   │        ├── groups.tgz
   │        ├── scoring.tgz
   │        ├── separate.tgz
   │        ├── simple-txt.tgz
   │        └── simple.tgz
   ├── doc
   │  └── auto-multiple-choice
   │     ├── auto-multiple-choice.en.pdf
   │     ├── auto-multiple-choice.en.xml
   │     ├── auto-multiple-choice.fr.pdf
   │     ├── auto-multiple-choice.fr.xml
   │     ├── auto-multiple-choice.ja.pdf
   │     ├── auto-multiple-choice.ja.xml
   │     └── html
   │        ├── auto-multiple-choice.en
   │        │  ├── alt.html
   │        │  ├── AMC-analyse.html
   │        │  ├── AMC-annote.html
   │        │  ├── AMC-association-auto.html
   │        │  ├── AMC-association.html
   │        │  ├── AMC-export.html
   │        │  ├── AMC-imprime.html
   │        │  ├── AMC-note.html
   │        │  ├── AMC-prepare.html
   │        │  ├── AMC-TXT.html
   │        │  ├── ar01s09.html
   │        │  ├── auto-multiple-choice.html
   │        │  ├── commands.html
   │        │  ├── flag.svg
   │        │  ├── graphical-interface.html
   │        │  ├── index.html
   │        │  ├── latex.html
   │        │  ├── prerequis.html
   │        │  ├── re03.html
   │        │  ├── re05.html
   │        │  ├── re12.html
   │        │  └── usagenotes.html
   │        ├── auto-multiple-choice.fr
   │        │  ├── alt.html
   │        │  ├── AMC-prepare.html
   │        │  ├── AMC-TXT.html
   │        │  ├── auto-multiple-choice.html
   │        │  ├── commandes.html
   │        │  ├── Divers.html
   │        │  ├── flag.svg
   │        │  ├── index.html
   │        │  ├── interface-graphique.html
   │        │  ├── latex.html
   │        │  ├── notesutilisation.html
   │        │  └── prerequis.html
   │        ├── auto-multiple-choice.ja
   │        │  ├── alt.html
   │        │  ├── AMC-analyse.html
   │        │  ├── AMC-annote.html
   │        │  ├── AMC-association-auto.html
   │        │  ├── AMC-association.html
   │        │  ├── AMC-export.html
   │        │  ├── AMC-imprime.html
   │        │  ├── AMC-note.html
   │        │  ├── AMC-prepare.html
   │        │  ├── AMC-TXT.html
   │        │  ├── auto-multiple-choice.html
   │        │  ├── commands.html
   │        │  ├── flag.svg
   │        │  ├── graphical-interface.html
   │        │  ├── index.html
   │        │  ├── ix01.html
   │        │  ├── latex.html
   │        │  ├── prerequis.html
   │        │  ├── re03.html
   │        │  ├── re05.html
   │        │  ├── re12.html
   │        │  └── usagenotes.html
   │        ├── images
   │        │  ├── callouts
   │        │  │  ├── 1.png
   │        │  │  ├── 2.png
   │        │  │  ├── 3.png
   │        │  │  ├── 4.png
   │        │  │  ├── 5.png
   │        │  │  ├── 6.png
   │        │  │  ├── 7.png
   │        │  │  ├── 8.png
   │        │  │  ├── 9.png
   │        │  │  ├── 10.png
   │        │  │  ├── 11.png
   │        │  │  ├── 12.png
   │        │  │  ├── 13.png
   │        │  │  ├── 14.png
   │        │  │  └── 15.png
   │        │  ├── important.png
   │        │  ├── note.png
   │        │  └── warning.png
   │        ├── index.html
   │        └── style.css
   ├── locale
   │  ├── ar
   │  │  └── LC_MESSAGES
   │  │     └── auto-multiple-choice.mo
   │  ├── de
   │  │  └── LC_MESSAGES
   │  │     └── auto-multiple-choice.mo
   │  ├── es
   │  │  └── LC_MESSAGES
   │  │     └── auto-multiple-choice.mo
   │  ├── fr
   │  │  └── LC_MESSAGES
   │  │     └── auto-multiple-choice.mo
   │  └── ja
   │     └── LC_MESSAGES
   │        └── auto-multiple-choice.mo
   ├── man
   │  └── man1
   │     ├── AMC-analyse.1
   │     ├── AMC-analyse.ja.1
   │     ├── AMC-annotate.1
   │     ├── AMC-annotate.ja.1
   │     ├── AMC-association-auto.1
   │     ├── AMC-association-auto.ja.1
   │     ├── AMC-association.1
   │     ├── AMC-association.ja.1
   │     ├── AMC-export.1
   │     ├── AMC-export.ja.1
   │     ├── AMC-getimages.1
   │     ├── AMC-getimages.ja.1
   │     ├── AMC-imprime.1
   │     ├── AMC-imprime.ja.1
   │     ├── AMC-mailing.1
   │     ├── AMC-mailing.ja.1
   │     ├── AMC-meptex.1
   │     ├── AMC-meptex.ja.1
   │     ├── AMC-note.1
   │     ├── AMC-note.ja.1
   │     ├── AMC-prepare.1
   │     ├── AMC-prepare.fr.1
   │     ├── AMC-prepare.ja.1
   │     ├── auto-multiple-choice.1
   │     ├── auto-multiple-choice.fr.1
   │     └── auto-multiple-choice.ja.1
   └── texmf-local
      ├── doc
      │  └── latex
      │     └── AMC
      │        ├── automultiplechoice.pdf
      │        ├── questions.tex
      │        ├── sample-amc.pdf
      │        ├── sample-amc.tex
      │        ├── sample-plain.pdf
      │        ├── sample-plain.tex
      │        ├── sample-separate.pdf
      │        └── sample-separate.tex
      └── tex
         └── latex
            └── AMC
               └── automultiplechoice.sty

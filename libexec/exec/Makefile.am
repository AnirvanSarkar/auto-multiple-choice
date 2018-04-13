buildpdf_SOURCES = AMC-buildpdf.cc buildpdf.h minimal-getline.c
buildpdf_CPPFLAGS = $(CAIRO_CFLAGS) $(PANGO_CFLAGS) $(POPPLER_CFLAGS) $(OPENCV_CFLAGS)
buildpdf_LDFLAGS = -lstdc++ -lm $(CAIRO_LIBS) $(PANGO_LIBS) $(POPPLER_LIBS) $(OPENCV_LIBS)

detect_SOURCES = AMC-detect.cc minimal-getline.c
detect_CPPFLAGS = $(OPENCV_CFLAGS)
detect_LDFLAGS = -lstdc++ -lm $(OPENCV_LIBS)

pdfformfields_SOURCES = pdfformfields.c
pdfformfields_CPPFLAGS = $(POPPLER_CFLAGS) $(GLIB_CFLAGS)
pdfformfields_LDFLAGS = $(POPPLER_LIBS) $(GLIB_LIBS)

libexec_PROGRAMS = buildpdf detect pdfformfields
$(info $(CAIRO_CFLAGS))
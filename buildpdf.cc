/*

 Copyright (C) 2013 Alexis Bienvenue <paamc@passoire.fr>

 This file is part of Auto-Multiple-Choice

 Auto-Multiple-Choice is free software: you can redistribute it
 and/or modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation, either version 2 of
 the License, or (at your option) any later version.

 Auto-Multiple-Choice is distributed in the hope that it will be
 useful, but WITHOUT ANY WARRANTY; without even the implied warranty
 of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Auto-Multiple-Choice.  If not, see
 <http://www.gnu.org/licenses/>.

*/

#ifndef __BUILDPDF__

#define __BUILDPDF__ 1

#include <math.h>
#include <stdio.h>
#include <string.h>
#include <cairo.h>
#include <cairo-pdf.h>
#include <poppler.h>
#include <pango/pangocairo.h>

#include "opencv2/highgui/highgui.hpp"

/*

  Helpers to read PNG files from memory (as an array or as a vector)
  with Cairo

 */

struct buffer_closure {
  uchar *buffer;
  unsigned long int length;
  unsigned long int offset;
};

#define BUFFER_CLOSURE(ptr) ((buffer_closure*)(ptr))

static cairo_status_t read_buffer(void *closure, uchar *data, unsigned int length) {
  if(BUFFER_CLOSURE(closure)->offset + length > BUFFER_CLOSURE(closure)->length) {
    return(CAIRO_STATUS_READ_ERROR);
  }
  memcpy(data,BUFFER_CLOSURE(closure)->buffer + BUFFER_CLOSURE(closure)->offset,length);
  BUFFER_CLOSURE(closure)->offset += length;
  return(CAIRO_STATUS_SUCCESS);
}

struct vector_closure {
  std::vector<uchar>::iterator iterator;
  unsigned long int length;
};

#define VECTOR_CLOSURE(ptr) ((vector_closure*)(ptr))

static cairo_status_t read_vector(void *closure, uchar *data, unsigned int length) {
  if(VECTOR_CLOSURE(closure)->length < length) {
    return(CAIRO_STATUS_READ_ERROR);
  }
  std::copy(VECTOR_CLOSURE(closure)->iterator,VECTOR_CLOSURE(closure)->iterator+length,
	    (uchar*)data);
  VECTOR_CLOSURE(closure)->iterator+=length;
  VECTOR_CLOSURE(closure)->length-=length;
  return(CAIRO_STATUS_SUCCESS);
}

/*

  BuildPdf

  This class is used by AMC-annotate to build a pdf from PNG files
  (scans), PDF files (subject pages), with transformation matrix
  support and drawing support (rectangles, circles, marks, text).

*/

class BuildPdf {
public:
  /* constructor: w and h are the page size in pixels, and d the "dots
     per point", that is the number of pixels in one pt (1pt is 1/72
     inches).

     Note that when drawing, all coordinates will be given to BuildPdf
     in pixels (with (0,0) = top-left corner).
  */
  BuildPdf(double w,double h,double d):
    width_in_pixels(w), height_in_pixels(h), dppt(d), n_pages(-1),
    user_one_point(0),
    document(NULL), layout(NULL), surface(NULL), cr(NULL),
    line_width(1.0), font_size(12.0), debug(0), png_compression_level(9) { };

  ~BuildPdf();

  /* call set_debug(1) to get more debugging output on stderr. */
  void set_debug(int d) { debug=d; }

  void set_png_compression_level(int l) { png_compression_level=l; }

  /* start_output strats to build a PDF into file output_filename. */
  int start_output(char* output_filename);
  /* close_output finishes with building the PDF, and closes the file. */
  void close_output();

  /* next_page begins with another blank page. */
  int next_page();

  /* new_page_from_png begins with another page, with the PNG image
     as a background. */
  int new_page_from_png(const char* filename);
  int new_page_from_png(void *buffer, unsigned long int buffer_length);
  int new_page_from_png(std::vector<uchar> &buf);

  /* new_page_from_image begins with another page, with the image from
     file filename as a background (first converted to PNG using
     OpenCV). */
  int new_page_from_image(const char* filename);

  /* load_pdf loads a PDF file, to be used by new_page_from_pdf. */
  int load_pdf(char* filename);
  /* new_page_from_pdf begins with another page, using page page_nb of
     the loaded PDF as a background. */
  int new_page_from_pdf(int page_nb);

  /* set_line_width sets the line width (in points) for next
     drawings. */
  void set_line_width(double lw);
  /* set_font_size sets the font size (in points) for next
     drawings. */
  int set_font_size(double font_size);

  /* color sets the color for next drawings, either with RBG or
     RGBA. */
  void color(double r,double g, double b,double a) {
    cairo_set_source_rgba(cr,r,g,b,a);
  }
  void color(double r,double g, double b) {
    cairo_set_source_rgb(cr,r,g,b);
  }

  /* set_matrix sets the matrix that transforms layout coordinates to
     scan coordinates (as recorded in the layout AMC database). */
  void set_matrix(double a, double b, double c ,double d, double e, double f);
  /* identity_matrix sets the matrix to identity (to be used when the
     background is the question page, not a scan). */
  void identity_matrix();

  /* drawing methods : */
  void draw_rectangle(double xmin, double xmax, double ymin, double ymax);
  void draw_mark(double xmin, double xmax, double ymin, double ymax);
  void draw_text(double x, double y,double xpos,double ypos,const char *text);
  int draw_text_rectangle(double xmin, double xmax,
			  double ymin, double ymax,
			  const char *text);
  void draw_circle(double xmin, double xmax, double ymin, double ymax);

private:
  double width_in_pixels;
  double height_in_pixels;
  double dppt;
  int n_pages;
  PopplerDocument *document;
  PangoLayout *layout;
  cairo_surface_t *surface;
  cairo_t *cr;
  cairo_matrix_t matrix;
  double user_one_point;
  double line_width;
  double font_size;
  int debug;
  int png_compression_level;

  double normalize_distance();
  PangoLayout* r_font_size_layout(double ratio);
  int new_page_from_image_surface(cairo_surface_t *image_surface);
  void draw_text(PangoLayout* local_layout,
		 double x, double y,double xpos, double ypos,const char *text);
};

BuildPdf::~BuildPdf() {
  close_output();
  if(document != NULL) g_object_unref(document);
}

int BuildPdf::start_output(char* output_filename) {
  close_output();

  printf(": opening -> %s\n",output_filename);
  surface=cairo_pdf_surface_create(output_filename,
				   width_in_pixels/dppt,
				   height_in_pixels/dppt);

  cairo_status_t status=cairo_surface_status(surface);
  if(status != CAIRO_STATUS_SUCCESS) {
    printf("! ERROR : creating surface - %s\n",
	   cairo_status_to_string(status));
    cairo_surface_destroy(surface);
    surface=NULL;
    return(1);
  }

  cr=cairo_create(surface);
  status=cairo_status(cr);
  if(status != CAIRO_STATUS_SUCCESS) {
    printf("! ERROR : creating cairo - %s\n",
	   cairo_status_to_string(status));
    cairo_surface_destroy(surface);
    cairo_destroy(cr);
    surface=NULL;
    cr=NULL;
    return(1);
  }
  
  layout=pango_cairo_create_layout(cr);
  if(layout==NULL) {
     printf("! ERROR : creating pango/cairo layout - %s\n",
	   cairo_status_to_string(status));
    cairo_surface_destroy(surface);
    cairo_destroy(cr);
    surface=NULL;
    cr=NULL;
    return(1);
  }
  n_pages=0;
  user_one_point=0;

  printf(": OK\n");
  return(0);
}

void BuildPdf::close_output() {
  if(n_pages>=0) {
    printf(": closing...\n");
    cairo_surface_finish(surface);
    cairo_surface_destroy(surface);
    surface=NULL;
    cairo_destroy(cr);
    cr=NULL;
    if(layout != NULL) {
      g_object_unref(layout);
      layout=NULL;
    }
    n_pages=-1;
  }
}

int BuildPdf::next_page() {
  if(n_pages<0) {
    printf("! ERROR: next_page in closed document\n");
    return(1);
  }
  if(n_pages>=1) cairo_show_page(cr);
  n_pages++;
  return(0);
}

int BuildPdf::new_page_from_png(const char* filename) {
  printf(": PNG < %s\n",filename);
  cairo_surface_t *image_surface=cairo_image_surface_create_from_png(filename);
  return(new_page_from_image_surface(image_surface));
}

int BuildPdf::new_page_from_png(void *buffer, unsigned long int buffer_length) {
  buffer_closure closure;
  closure.buffer=(uchar*)buffer;
  closure.length=buffer_length;
  closure.offset=0;

  printf(": PNG < BUFFER\n");
  
  cairo_surface_t *image_surface=cairo_image_surface_create_from_png_stream(read_buffer,&closure);
  return(new_page_from_image_surface(image_surface));
}

int BuildPdf::new_page_from_png(std::vector<uchar> &buf) {
  vector_closure closure;
  closure.iterator=buf.begin();
  closure.length=buf.size();

  printf(": PNG < BUFFER\n");
  
  cairo_surface_t *image_surface=cairo_image_surface_create_from_png_stream(read_vector,&closure);
  return(new_page_from_image_surface(image_surface));
}

int BuildPdf::new_page_from_image(const char* filename) {
  printf(": IMAGE < %s\n",filename);
  cv::Mat image=cv::imread(filename,CV_LOAD_IMAGE_COLOR);
  std::vector<uchar> buf;
  imencode(".png",image,buf,
	   std::vector<int>(CV_IMWRITE_PNG_COMPRESSION,png_compression_level));
  printf(": converted to PNG (%d bytes)\n",buf.size());
  return(new_page_from_png(buf));
}

int BuildPdf::new_page_from_image_surface(cairo_surface_t *image_surface) {
  if(image_surface==NULL) {
    printf("! ERROR : NULL image_surface\n");
    return(1);
  }
  
  cairo_status_t image_surface_status=cairo_surface_status(image_surface);
  if(image_surface_status != CAIRO_STATUS_SUCCESS) {
    printf("! ERROR : creating image surface / %s\n",
	   cairo_status_to_string(image_surface_status));
    cairo_surface_destroy(image_surface);
    return(1);
  }
  int w=cairo_image_surface_get_width(image_surface);
  int h=cairo_image_surface_get_height(image_surface);
  if(w<=0 || h<=0) {
    printf("! ERROR : image dimensions should be positive (%dx%d)\n",
	   w,h);
    cairo_surface_destroy(image_surface);
    return(1);
  }
  double rx=width_in_pixels/dppt/cairo_image_surface_get_width(image_surface);
  double ry=height_in_pixels/dppt/cairo_image_surface_get_height(image_surface);
  if(next_page()) {
    cairo_surface_destroy(image_surface);
    return(1);
  }

  if(rx<ry) {
    ry=rx;
  } else {
    rx=ry;
  }

  printf(": R=%g\n",rx);
  
  cairo_identity_matrix(cr);
  cairo_scale(cr,rx,rx);

  cairo_save(cr);
  cairo_set_source_surface(cr,image_surface,0,0);
  cairo_paint(cr);
  cairo_restore(cr);

  cairo_surface_destroy(image_surface);
  return(0);
}

int BuildPdf::load_pdf(char* filename) {
  GError *error=NULL;
  gchar *uri;

  if(document != NULL) g_object_unref(document);

  uri = g_filename_to_uri (filename, NULL, &error);
  if (uri == NULL) {
    printf("! ERROR: poppler fail: %s\n", error->message);
    return 1;
  }

  document = poppler_document_new_from_file (uri, NULL, &error);
  if (document == NULL) {
    printf("! ERROR: poppler fail: %s\n", error->message);
    return 1;
  }

  identity_matrix();
  return(0);
}

int BuildPdf::new_page_from_pdf(int page_nb) {
  if(next_page()) {
    return(1);
  }

  if(document==NULL) {
    printf("! ERROR: no pdf loaded.\n");
    return(1);
  }
  PopplerPage *page = poppler_document_get_page (document, page_nb-1);
  if (page == NULL) {
    printf("! ERROR:poppler fail: page not found.\n");
    return 1;
  }
  cairo_identity_matrix(cr);
  poppler_page_render_for_printing (page, cr);
  g_object_unref (page);

  identity_matrix();
  return(0);
}

double BuildPdf::normalize_distance() {
  double dx,dy;
  dx=1.0;
  dy=1.0;
  cairo_device_to_user_distance(cr,&dx,&dy);
  return( sqrt((dx*dx+dy*dy)/2.0) );
}

void BuildPdf::set_line_width(double lw) {
  if(lw>=0) {
    line_width=lw;
    if(line_width*user_one_point>0) 
      cairo_set_line_width(cr,line_width*user_one_point);
  }
}

int BuildPdf::set_font_size(double fs) {
  font_size=fs;
  PangoFontDescription *desc=pango_font_description_new();
  if(desc==NULL) {
    printf("! ERROR : font description creation\n");
    return(1);
  }
  pango_font_description_set_size(desc,font_size*PANGO_SCALE);
  pango_layout_set_font_description(layout,desc);
  return(0);
}

PangoLayout* BuildPdf::r_font_size_layout(double ratio) {
  PangoLayout *local_layout=pango_layout_copy(layout);
  if(local_layout==NULL) {
    printf("! ERROR : creating local pango layout.\n");
    return(NULL);
  }
  const PangoFontDescription *desc=pango_layout_get_font_description(layout);
  gint size=pango_font_description_get_size(desc);
  PangoFontDescription *new_desc=pango_font_description_copy(desc);
  if(desc==NULL) {
    printf("! ERROR : creating local pango font description.\n");
    g_object_unref(local_layout);
    return(NULL);
  }
  if(pango_font_description_get_size_is_absolute(desc)) {
    pango_font_description_set_absolute_size(new_desc,size*ratio);
  } else {
    pango_font_description_set_size(new_desc,size*ratio);
  }
  pango_layout_set_font_description(local_layout,new_desc);
  return(local_layout);
}

void BuildPdf::set_matrix(double a, double b, double c ,double d, double e, double f) {
  cairo_matrix_init(&matrix,a,c,b,d,e,f);
  cairo_identity_matrix(cr);
  cairo_scale(cr,1/dppt,1/dppt);
  cairo_transform(cr,&matrix);

  user_one_point=normalize_distance();
  set_line_width(line_width);

  pango_cairo_context_set_resolution(pango_layout_get_context(layout),
				     user_one_point * 72.);
  pango_cairo_update_layout(cr,layout);
  set_font_size(font_size);
}

void BuildPdf::identity_matrix() {
  set_matrix(1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
} 

void BuildPdf::draw_rectangle(double xmin, double xmax, double ymin, double ymax) {
  cairo_rectangle(cr,xmin,ymin,xmax-xmin,ymax-ymin);
  cairo_stroke(cr);
}

void BuildPdf::draw_mark(double xmin, double xmax, double ymin, double ymax) {
  cairo_move_to(cr,xmin,ymin);
  cairo_line_to(cr,xmax,ymax);
  cairo_move_to(cr,xmin,ymax);
  cairo_line_to(cr,xmax,ymin);
  cairo_stroke(cr);
}

void BuildPdf::draw_text(PangoLayout* local_layout,
			 double x, double y,
			 double xpos, double ypos,
			 const char *text) {
  PangoRectangle extents;

  if(x<0) x+=width_in_pixels;
  if(y<0) y+=height_in_pixels;

  pango_layout_set_text(local_layout,text,-1);
  pango_layout_get_pixel_extents(local_layout,&extents,NULL);
  printf("TEXT=\"%s\" X=%ld Y=%ld W=%ld H=%ld\n",
	 text,
	 extents.x,extents.y,
	 extents.width,extents.height);
  cairo_move_to(cr,
		x-xpos*extents.width-extents.x,
		y-ypos*extents.height-extents.y);
  pango_cairo_show_layout(cr,local_layout);
}

void BuildPdf::draw_text(double x, double y,
			 double xpos, double ypos,
			 const char *text) {
  draw_text(layout,x,y,xpos,ypos,text);
}

int BuildPdf::draw_text_rectangle(double xmin, double xmax,
				   double ymin, double ymax,
				   const char *text) {
  double r,rp;
  PangoRectangle extents;
  PangoLayout* local_layout;

  pango_layout_set_text(layout,text,-1);
  pango_layout_get_pixel_extents(layout,&extents,NULL);
  printf("TEXT=\"%s\" X=%ld Y=%ld W=%ld H=%ld\n",
	 text,
	 extents.x,extents.y,
	 extents.width,extents.height);
  r=(xmax-xmin)/extents.width;
  rp=(ymax-ymin)/extents.height;
  if(rp<r) r=rp;
  printf(": ratio=%g\n",r);

  local_layout=r_font_size_layout(r);
  if(local_layout==NULL) {
    return(1);
  }
  draw_text(local_layout,
	    (xmin+xmax)/2,(ymin+ymax)/2,
	    0.5,0.5,text);

  g_object_unref(local_layout);
  return(0);
}

void BuildPdf::draw_circle(double xmin, double xmax, double ymin, double ymax) {
  cairo_new_path(cr);
  cairo_arc(cr,(xmin+xmax)/2,(ymin+ymax)/2,
	    sqrt((xmax-xmin)*(xmax-xmin)+(ymax-ymin)*(ymax-ymin))/2,
	    0.0,2*M_PI);
  cairo_stroke(cr);
}

#endif

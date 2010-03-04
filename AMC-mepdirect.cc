
#include <math.h>

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <GlobalParams.h>
#include <Object.h>
#include <PDFDoc.h>
#include <splash/SplashBitmap.h>
#include <splash/Splash.h>
#include <SplashOutputDev.h>

static int firstPage = 1;
static int lastPage = 0;

static char *repertoire = NULL;
static GooString *fileName = NULL;
static char *ppmFile = NULL;

static double progres_pas=0;
static char *progres_nom=NULL;

static char NON[]="no";

static double resolution = 150.0;

static int x = 0;
static int y = 0;
static int w = 0;
static int h = 0;
static GBool useCropBox = gFalse;

/* codes RGB particuliers :

  200,quest,reponse  : case a cocher (avec reponse<200)
  201,nombre,chiffre : case identification ID page
  201,100,i          : marques de position (i=1 a 4)
  201,255,255        : sous la case NOM
  202,0,ID           : composante connexe ID

*/

#define N_QUEST 255
#define N_REP 255
#define N_NID 3
#define N_CH 40
#define N_MARQUE 4

struct minMax {
  int xmin,xmax,ymin,ymax;
};

void mm_init(minMax *mm) {
  mm->xmin=-1;
  mm->ymin=-1;
  mm->xmax=-1;
  mm->ymax=-1;
}

void minimax(struct minMax *mm,int x,int y) {
  if(x<mm->xmin || mm->xmin<0) mm->xmin=x;
  if(x>mm->xmax) mm->xmax=x;
  if(y<mm->ymin || mm->ymin<0) mm->ymin=y;
  if(y>mm->ymax) mm->ymax=y;
}

int cochee(SplashBitmap *im,minMax *mm) {
  SplashColor color;
  im->getPixel((int)((mm->xmin+mm->xmax)/2),(int)((mm->ymin+mm->ymax)/2),&color[0]);
  return(color[0]<250);
}

int get_nombre(SplashBitmap *im,minMax mm[],int max_ch) {
  int i;
  int n=0;
  for(i=0;i<=max_ch;i++) {
    if(mm[i].xmin>=0) {
      n=2*n+cochee(im,&mm[i]);
    }
  }
  return(n);
}

int en_couleur(SplashColorPtr pixel) {
  return(!(*pixel==*(pixel+1) && *pixel==*(pixel+2)));
}

static void savePageSlice(PDFDoc *doc,
                   SplashOutputDev *splashOut, 
                   int pg, int x, int y, int w, int h, 
                   double pg_w, double pg_h, 
                   char *repertoire) {

  SplashBitmap *im;
  SplashColorPtr base,pixel;

  char *xml_file=NULL;
  FILE *xml;

  static struct minMax question[N_QUEST+1][N_REP+1];
  static struct minMax identification[N_NID+1][N_CH+1];
  static struct minMax nom;
  static struct minMax marque[N_MARQUE+1];

  int row_size;
  int id_etu,id_page,id_check;
  double diametre_marque;

  printf("Page %d :\n - rasterisation\n",pg);

  if (w == 0) w = (int)ceil(pg_w);
  if (h == 0) h = (int)ceil(pg_h);
  w = (x+w > pg_w ? (int)ceil(pg_w-x) : w);
  h = (y+h > pg_h ? (int)ceil(pg_h-y) : h);
  doc->displayPageSlice(splashOut, 
    pg, resolution, resolution, 
    0,
    !useCropBox, gFalse, gFalse,
    x, y, w, h
  );

  im=splashOut->getBitmap();

  printf(" - analysis\n",pg);

  for(x=0;x<=N_QUEST;x++) for(y=0;y<=N_REP;y++) {
    mm_init(&question[x][y]);
  }
  for(x=0;x<=N_NID;x++) for(y=0;y<=N_CH;y++) {
    mm_init(&identification[x][y]);
  }
  mm_init(&nom);
  for(x=0;x<=N_MARQUE;x++) {
    mm_init(&marque[x]);
  }

  base=im->getDataPtr();
  row_size=im->getRowSize();

  for(y=0;y<im->getHeight();y++) {
    pixel=base;
    for(x=0;x<im->getWidth();x++) {
      if(*pixel==200 && en_couleur(pixel)) { // case a cocher
	if(*(pixel+1)<=N_QUEST && *(pixel+2)<=N_REP)
	  minimax(&question[*(pixel+1)][*(pixel+2)],x,y);
      }
      if(*pixel==201 && en_couleur(pixel)) { // case ID
	if(*(pixel+1)<=N_NID && *(pixel+2)<=N_CH)
	  minimax(&identification[*(pixel+1)][*(pixel+2)],x,y);
      }
      if(*pixel==201 && *(pixel+1)==100) { // marque
	if(*(pixel+2)<=N_MARQUE)
	  minimax(&marque[*(pixel+2)],x,y);
      }
      if(*pixel==201 && *(pixel+1)==255 && *(pixel+2)==255) {
	minimax(&nom,x,y);
      }
      pixel+=3;
    }
    base+=row_size;
  }

  // ecriture PPM pour debogage

  if(ppmFile) {
    im->writePNMFile(ppmFile);
  }

  // extraction informations diverses

  id_etu=get_nombre(im,identification[1],N_CH);
  id_page=get_nombre(im,identification[2],N_CH);
  id_check=get_nombre(im,identification[3],N_CH);

  diametre_marque=0;
  for(x=1;x<=N_MARQUE;x++) {
    diametre_marque+=(marque[x].xmax-marque[x].xmin)
      +(marque[x].ymax-marque[x].ymin);
  }
  diametre_marque/=(2*N_MARQUE);

  // sortie

  if(repertoire != NULL) {
    
    asprintf(&xml_file,"%s/mep-%d-%d-%d.xml",repertoire,id_etu,id_page,id_check);
    xml = fopen (xml_file,"w");
    
    printf(" - writing to %s\n",xml_file);
    
    if (xml!=NULL) {
      
      fprintf(xml,"<?xml version='1.0' standalone='yes'?>\n");
      fprintf(xml,"<mep image=\"poppler\" id=\"+%d/%d/%d+\" src=\"%s\" page=\"%d\" dpi=\"%.1f\" tx=\"%d\" ty=\"%d\" diametremarque=\"%.2f\">\n",
	      id_etu,id_page,id_check,
	      fileName->getCString(),
	      pg,resolution,
	      im->getWidth(),im->getHeight(),
	      diametre_marque
	      );
      for(x=0;x<=N_NID;x++) {
	for(y=0;y<=N_CH;y++) {
	  if(identification[x][y].xmin>=0)
	    fprintf(xml,"  <chiffre n=\"%d\" i=\"%d\" xmin=\"%d\" xmax=\"%d\" ymin=\"%d\" ymax=\"%d\"/>\n",
		    x,y,identification[x][y].xmin,identification[x][y].xmax,
		    identification[x][y].ymin,identification[x][y].ymax);
	}}
      for(x=0;x<=N_QUEST;x++) {
	for(y=0;y<=N_REP;y++) {
	  if(question[x][y].xmin>=0)
	    fprintf(xml,"  <case question=\"%d\" reponse=\"%d\" xmin=\"%d\" xmax=\"%d\" ymin=\"%d\" ymax=\"%d\"/>\n",
		    x,y,question[x][y].xmin,question[x][y].xmax,
		    question[x][y].ymin,question[x][y].ymax);
	}}
      
      for(x=0;x<=N_MARQUE;x++) {
	if(marque[x].xmin>=0)
	  fprintf(xml,"  <coin id=\"%d\"><x>%.1f</x><y>%.1f</y></coin>\n",
		  x,((double)marque[x].xmin+(double)marque[x].xmax)/2.0,
		  ((double)marque[x].ymin+(double)marque[x].ymax)/2.0);
      }
      fprintf(xml,"</mep>\n");    
      fclose (xml);
    } else {
      printf("Output error.\n");
    }
    
    free(xml_file);
  }
  if(progres_pas>0 && progres_nom!=NULL) {
    printf("===<%s>=+%f\n",progres_nom,progres_pas);
    fflush(stdout);
  }
}

int main(int argc, char *argv[]) {
  PDFDoc *doc;
  SplashColor paperColor;
  SplashOutputDev *splashOut;
  int exitCode;
  int pg;
  double pg_w, pg_h, tmp;
  char c;

  exitCode = 99;

  // parse args

  opterr = 0;
     
  while ((c = getopt (argc, argv, "f:l:r:d:o:e:n:")) != -1) {
    switch (c) {
    case 'f': firstPage=atoi(optarg);
      break;
    case 'l': lastPage=atoi(optarg);
      break;
    case 'r': resolution=atof(optarg);
      break;
    case 'd': repertoire=optarg;
      break;
    case 'o': ppmFile=optarg;
      break;
    case 'e': progres_pas=atof(optarg);
      break;
    case 'n': progres_nom=optarg;
      break;
    }
  }

  if(argc-1==optind) {
    fileName=new GooString(argv[optind]);
  } else {
    if(argc-1<optind) {
      printf("Needs PDF filename\n");
    } else {
      printf("Too much arguments\n");
    }
    exitCode=2;
    goto err0;
  }

  // read config file

  globalParams = new GlobalParams();

  if (!globalParams->setAntialias(NON)) {
      fprintf(stderr, "Bad '-aa' value\n");
  }
  if (!globalParams->setVectorAntialias(NON)) {
      fprintf(stderr, "Bad '-aaVector' value\n");
  }

  // open PDF file

  if(fileName != NULL) {
    doc = new PDFDoc(fileName, NULL, NULL);
  } else {
    printf("Needs PDF filename\n");
    goto err0;
  }

  if (!doc->isOk()) {
    fprintf(stderr,"Error %d opening PDF file\n",doc->getErrorCode());
    exitCode = 1;
    goto err1;
  }

  // get page range
  if (firstPage < 1)
    firstPage = 1;
  if (lastPage < 1 || lastPage > doc->getNumPages())
    lastPage = doc->getNumPages();

  progres_pas/=(lastPage-firstPage+1);

  // write PPM files
  paperColor[0] = 255;
  paperColor[1] = 255;
  paperColor[2] = 255;
  splashOut = new SplashOutputDev(splashModeRGB8, 4,
				  gFalse, paperColor);
  splashOut->startDoc(doc->getXRef());
  for (pg = firstPage; pg <= lastPage; ++pg) {
    if (useCropBox) {
      pg_w = doc->getPageCropWidth(pg);
      pg_h = doc->getPageCropHeight(pg);
    } else {
      pg_w = doc->getPageMediaWidth(pg);
      pg_h = doc->getPageMediaHeight(pg);
    }

    pg_w = pg_w * (resolution / 72.0);
    pg_h = pg_h * (resolution / 72.0);
    if (doc->getPageRotate(pg)) {
      tmp = pg_w;
      pg_w = pg_h;
      pg_h = tmp;
    }
    savePageSlice(doc, splashOut, pg, x, y, w, h, pg_w, pg_h, repertoire);
  }
  delete splashOut;

  exitCode = 0;

  // clean up
 err1:
  delete doc;
  delete globalParams;

 err0:

  // check for memory leaks
  Object::memCheck(stderr);
  gMemReport(stderr);

  return exitCode;
}

#! /bin/sh

FILE=$3
PACK=`echo "$1 $2" | sed 's: ::g'`

perl -pi -e "s:PACKAGE:$PACK:" $FILE

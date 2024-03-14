#! /bin/sh

DIR=`dirname $0`

LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8 LC_COLLATE=fr_FR.UTF-8 $DIR/french-test.pl "$@"


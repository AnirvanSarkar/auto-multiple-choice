#! /bin/sh

cd ..

TMP=/tmp/AMC-check-perltidy
R=0

for f in `find . -name '*.pl' -o -name '*.pl.in' -o -name '*.pm' -o -name '*.pm.in'`
do

    if [ ! -f "$f.in" ];
    then
        echo "*** $f"
	perltidy $f -o $TMP
        diff $f $TMP || R=1
    fi
    
done

exit $R

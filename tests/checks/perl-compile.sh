#! /bin/sh

cd ..

for f in `find . -name '*.pl' -o -name '*.pl.in' -o -name '*.pm' -o -name '*.pm.in'`
do

    if [ ! -f "$f.in" ];
    then
	output=`perl -c $f 2>&1`
	if [ $? -ne 0 ];
	then
	    echo $output
	    exit 1
	fi
    fi
    
done

exit 0

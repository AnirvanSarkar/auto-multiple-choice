#! /bin/bash

FAILS=0

TESTS=$@

if [ ! -d $HOME/AMC-tmp ];
then
    echo "Creating $HOME/AMC-tmp ..."
    mkdir -p $HOME/AMC-tmp
fi

BDIR=$HOME/.config/gtk-3.0/
BFILE=$BDIR/bookmarks
if [ ! -d $BDIR ];
then
    echo "Creating $BDIR ..."
    mkdir -p $BDIR
fi
if [ ! -f $BFILE ];
then
    echo "Creating $BFILE ..."
    touch $BFILE
fi
if grep -q AMC-tmp $BFILE
then
    echo "Bookmark is here"
else
    echo "Adding bookmark..."
    (echo "file://$HOME/AMC-tmp AMC-tmp" ; cat $BFILE) > $BFILE.old
    cp $BFILE.old $BFILE
fi

DISPLAY_NUM=${DISPLAY_NUM:-4}

Xvfb :$DISPLAY_NUM &
XVFB_PID=$!

echo "Xvfb started for display $DISPLAY_NUM with PID $XVFB_PID"

export DISPLAY=:$DISPLAY_NUM

DBUS_RUN=""
if [ -x /usr/bin/dbus-run-session ];
then
    DBUS_RUN="dbus-run-session --"
fi

for t in $TESTS
do

    if $DBUS_RUN ./test-$t.py
    then
        echo -e "[ \e[0;32mOK\e[0m ] $t"
    else
        echo -e "[\e[0;31mFAIL\e[0m] $t"
        FAILS=1
    fi

done

kill -9 $XVFB_PID

exit $FAILS



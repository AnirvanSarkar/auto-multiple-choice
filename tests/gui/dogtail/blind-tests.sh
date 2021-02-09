#! /bin/bash

FAILS=0

TESTS=$@

if [ ! "$TESTS" ];
then
    echo "Standard tests"
    TESTS="cups manual pdfform postcorrect simple utf8"
fi

echo "Tests: $TESTS"

if [ ! -d $HOME/AMC-tmp ];
then
    echo "Creating $HOME/AMC-tmp ..."
    mkdir -p $HOME/AMC-tmp
fi
if [ ! -d $HOME/.AMC.d ];
then
    echo "Creating $HOME/.AMC.d ..."
    mkdir -p $HOME/.AMC.d
fi

STATE=$HOME/.AMC.d/state.xml
if [ ! -f $STATE ];
then
    echo "Creating $STATE ..."
    echo '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<state>
  <apprentissage>
    <ASSOC_AUTO_OK>1</ASSOC_AUTO_OK>
    <MAJ_DOCS_OK>1</MAJ_DOCS_OK>
    <MAJ_MEP_OK>1</MAJ_MEP_OK>
    <SAISIE_AUTO>1</SAISIE_AUTO>
  </apprentissage>
  <profile>TEST</profile>
</state>' > $STATE
fi

BDIR=$HOME/.config/gtk-3.0
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

# gedit should not be too large
gsettings set org.gnome.gedit.state.window size "(500, 500)"

DISPLAY_NUM=${DISPLAY_NUM:-4}

Xvfb :$DISPLAY_NUM -screen 0 1600x1200x24 &
XVFB_PID=$!

echo "Xvfb started for display $DISPLAY_NUM with PID $XVFB_PID"

export DISPLAY=:$DISPLAY_NUM

DBUS_RUN=""
if [ -x /usr/bin/dbus-run-session ];
then
    DBUS_RUN="dbus-run-session --"
fi

RESULTS_FILE=/tmp/AMC-guitests.log

echo "GUI tests results:" > $RESULTS_FILE

for t in $TESTS
do

    if $DBUS_RUN ./test-$t.py
    then
        echo -e "[ \e[0;32mOK\e[0m ] $t" >> $RESULTS_FILE
    else
        echo -e "[\e[0;31mFAIL\e[0m] $t" >> $RESULTS_FILE
        FAILS=1
    fi

    # screenshot
    import -window root /tmp/AMC-gui-$t.jpg

done

kill -9 $XVFB_PID

cat $RESULTS_FILE

exit $FAILS



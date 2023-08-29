#! /usr/bin/perl

# Converts deb822 files in /etc/apt/sources.list to plain sources.list lines.

my $a = {};

sub go {
    for my $s ( @{ $a->{Suites} } ) {
        print "deb "
          . $a->{URIs}->[0] . " $s "
          . join( " ", @{ $a->{Components} } ) . "\n";
    }
    $a = {};
}

my $dir = "/etc/apt/sources.list.d";

opendir( my $dh, $dir ) || exit 0;
my @sources = grep { /\.sources$/ && -f "$dir/$_" } readdir($dh);
closedir $dh;

for my $f (@sources) {
    print "# $f\n";

    open SOURCE, "$dir/$f";

    $a = {};

    while (<SOURCE>) {
        if    (/(.*?): (.*)/) { push @{ $a->{$1} }, split( /\s/, $2 ); }
        elsif (/^$/)          { go; }
    }

    go;

    close SOURCE;
}


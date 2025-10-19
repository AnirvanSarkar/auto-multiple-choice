#! /usr/bin/perl

my $sub='';
my $fh;

open(XY, "automultiplechoice.xy");
LINE: while(<XY>) {
    if(/\\xyopen\{(.*)\}/) {
        $sub = $1;
        open($fh, ">", "automultiplechoice.$sub");
        next LINE;
    }
    if(/\\xyclose\{\}/) {
        $sub = '';
        close $fh;
        next LINE;
    }
    if($sub) {
        print $fh $_;
    }
}
close(XY);

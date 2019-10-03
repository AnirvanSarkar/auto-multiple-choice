#! /usr/bin/perl

sub sample {
    my (@choices) = @_;
    return $choices[ int( rand( 1 + $#choices ) ) ];
}

sub random_letter {
    sample( split( //, "abcdefghijklmnopqrstuvwxyz" ) );
}

sub random_word {
    join( '', map { random_letter() } ( 1 .. ( 2 + int( rand(8) ) ) ) );
}

sub random_words {
    my ($n) = @_;
    join( " ", map { random_word() } ( 1 .. $n ) );
}

sub random_question {
    my $q = "";
    $q .= "** " . random_words(5) . "\n" . random_words(10) . "\n";
    for my $i ( 1 .. ( 2 + int( rand(8) ) ) ) {
        $q .=
          sample( "-", "+" ) . " " . random_words( 2 + int( rand(8) ) ) . "\n";
    }
    $q .= "\n";
}

print "# AMC-TXT source\n";
print "Columns: 2\n";

print "Title: " . random_words(6) . "\n";
print "Presentation: "
  . random_words(5) . "\n"
  . random_words(10) . "\n"
  . random_words(10) . "\n";
print "Code: 8\n";
print "\n";

print "*( Group A: 10 questions\n\n";

for my $i ( 1 .. 10 ) {
    print random_question() . "\n";
}

print "*)\n\n";

print "*( Group B: 15 questions\n\n";

for my $i ( 1 .. 15 ) {
    print random_question();
}

print "*)\n\n";


#! /usr/bin/env perl
#
# Copyright (C) 2012-2022 Alexis Bienvenüe <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 2 of
# the License, or (at your option) any later version.
#
# Auto-Multiple-Choice is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Auto-Multiple-Choice.  If not, see
# <http://www.gnu.org/licenses/>.

use warnings;
use 5.012;

package AMC::Test;

use AMC::Basic;
use AMC::Data;
use AMC::DataModule::capture qw(:zone);
use AMC::DataModule::scoring qw(:question);
use AMC::Scoring;
use AMC::NamesFile;
use AMC::Queue;
use AMC::Topics;

use Text::CSV;
use File::Spec::Functions qw(tmpdir);
use File::Temp qw(tempfile tempdir);
use File::Copy;
use Digest::MD5;

use Data::Dumper;

use DBI;

use IPC::Run qw(run);

use Getopt::Long;

use utf8;

use_gettext;

my $defaults = {
    dir                 => '',
    filter              => '',
    tex_engine          => 'pdflatex',
    multiple            => '',
    pre_allocate        => 0,
    n_copies            => 5,
    check_marks         => '',
    perfect_copy        => [3],
    src                 => '',
    debug               => 0,
    debug_pixels        => 0,
    scans               => '',
    seuil               => 0.5,
    seuil_up            => 1.0,
    bw_threshold        => 0.6,
    ignore_red          => '',
    tol_marque          => 0.4,
    rounding            => 'i',
    grain               => 0.01,
    notemax             => 20,
    postcorrect_student => '',
    postcorrect_copy    => '',
    list                => '',
    list_key            => 'id',
    code                => 'student',
    check_assoc         => '',
    association_manual  => '',
    annote              => '',
    annote_files        => [],
    annote_ascii        => 0,
    annote_position     => 'marge',
    annote_color        => 'red',
    annotate_single     => '',
    verdict             => '%(id) %(ID)' . "\n" . 'TOTAL : %S/%M => %s/%m',
    verdict_question    => "\"%" . "s/%" . "m\"",
    model               => '(N).pdf',
    ok_checksums        => {},
    ok_checksums_file   => '',
    to_check            => [],
    export_full_csv     => [],
    export_full_ods     => [],
    export_columns      => 'student.copy',
    export_csv_ticked   => 'AB',
    export_csv_decimal  => ',',
    export_ods          => '',
    blind               => 0,
    check_zooms         => {},
    check_subject       => '',
    skip_prepare        => 0,
    skip_scans          => 0,
    tracedest           => \*STDERR,
    debug_file          => '',
    log_to              => '',
    pages               => '',
    extract_with        => 'qpdf',
    force_convert       => 0,
    force_magick        => 0,
    no_gs               => 0,
    documents           => 'sc',
    speed               => 0,
    full_scans          => '',
    full_density        => 300,
    tmpdir              => '',
    decoder             => '',
    password            => '',
    password_key        => 'password',
    setup               => 1,
    exitonerror         => 1,
    postinstall         => '',
    additional_test     => '',
    check_topics        => [],
    move_files          => [],
};

sub new {
    my ( $class, %oo ) = @_;

    my $self = { error => 0, %$defaults };

    for ( keys %oo ) {
        $self->{$_} = $oo{$_} if ( exists( $self->{$_} ) );
    }

    bless( $self, $class );

    my $to_stdout = 0;

    GetOptions(
        "debug!"         => \$self->{debug},
        "blind!"         => \$self->{blind},
        "log-to=s"       => \$self->{log_to},
        "to-stdout!"     => \$to_stdout,
        "extract-with=s" => \$self->{extract_with},
        "tmp=s"          => \$self->{tmpdir},
    );

    $self->{tracedest} = \*STDOUT if ($to_stdout);
    binmode $self->{tracedest}, ":utf8";

    $self->setup() if($self->{setup});

    return $self;
}

sub clean {
    my ($self) = @_;

    $self->set( src => '', scans => '', names => '', list => '', error => 0 );
}

sub setup {
    my ($self)=@_;

    $self->{dir} =~ s:/[^/]*$:: if(-f $self->{dir});

    $self->{tmpdir} = tmpdir() if ( !$self->{tmpdir} );

    if ( !$self->{src} ) {
        opendir( my $dh, $self->{dir} )
          || die "can't opendir $self->{dir}: $!";
        my @tex = grep { /\.(tex|txt)$/ } sort { $a cmp $b } readdir($dh);
        closedir $dh;
        $self->{src} = $tex[0];
    }

    if ( !$self->{list} ) {
        opendir( my $dh, $self->{dir} )
          || die "can't opendir $self->{dir}: $!";
        my @l = grep { /\.(csv|txt)$/ } readdir($dh);
        closedir $dh;
        $self->{list} = $l[0] || '';
    }
    $self->{names} =
      AMC::NamesFile::new( $self->{dir} . '/' . $self->{list}, 'utf8', 'id' )
      if ( $self->{list} && -f $self->{dir} . '/' . $self->{list} );


    $self->install;

    $self->{check_dir} = $self->{tmpdir} . "/AMC-VISUAL-TEST";
    mkdir( $self->{check_dir} ) if ( !-d $self->{check_dir} );

    $self->read_checksums( $self->{ok_checksums_file} );
    $self->read_checksums( $self->{dir} . '/ok-checksums' );

    require Time::HiRes if ( $self->{speed} );
}

sub set {
    my ( $self, %oo ) = @_;

    for ( keys %oo ) {
        $self->{$_} = $oo{$_} if ( exists( $self->{$_} ) );
    }

    return $self;
}

sub failed {
    my ( $self, $error ) = @_;
    $self->{error} += $error;
    exit($error) if ( $self->{exitonerror} );
}

sub read_checksums {
    my ( $self, $file ) = @_;

    if ( -f $file ) {
        my $n = 0;
        open CSF, $file or die "Error opening $file: $!";
        while (<CSF>) {
            if (/^\s*([a-f0-9]+)\s/) {
                $self->{ok_checksums}->{$1} = 1;
                $n++;
            }
        }
        close CSF;
        $self->trace("[I] $n checksums read from $file");
    }

}

sub install {
    my ($self) = @_;

    my $temp_loc = $self->{tmpdir};
    $self->{temp_dir} = tempdir(
        DIR     => $temp_loc,
        CLEANUP => ( !$self->{debug} )
    );

    opendir( my $sh, $self->{dir} )
      || die "can't opendir $self->{dir}: $!";
    for my $f ( grep { !/^\./ } ( readdir($sh) ) ) {
        system( "cp", "-r", $self->{dir} . '/' . $f, $self->{temp_dir} );
    }
    closedir $sh;

    for my $mv ( @{ $self->{move_files} } ) {
        debug("Move $mv->{from} to $mv->{to}");
        system(
            "mv",
            $self->{temp_dir} . '/' . $mv->{from},
            $self->{temp_dir} . '/' . $mv->{to}
        );
    }

    print { $self->{tracedest} } "[>] Installed in $self->{temp_dir}\n";

    if ( -d ( $self->{temp_dir} . "/scans" ) && !$self->{scans} ) {
        opendir( my $dh, $self->{temp_dir} . "/scans" )
          || die "can't opendir $self->{temp_dir}: $!";
        my @s = sort { $a cmp $b } grep { !/^\./ } readdir($dh);
        closedir $dh;

        if (@s) {
            $self->trace( "[I] Provided scans: " . ( 1 + $#s ) );
            $self->{scans} =
              [ map { $self->{temp_dir} . "/scans/$_" } sort { $a cmp $b } @s ];
        }
    }

    $self->{scans} = [] if ( !$self->{scans} );

    for my $d (
        qw(data cr cr/corrections cr/corrections/jpg cr/corrections/pdf scans))
    {
        mkdir( $self->{temp_dir} . "/$d" ) if ( !-d $self->{temp_dir} . "/$d" );
    }

    if ( $self->{log_to} ) {
        $self->{debug_file} = $self->{log_to};
    } else {
        $self->{debug_file} = $self->{temp_dir} . "/debug.log";
    }
    open( DB, ">>", $self->{debug_file} );
    print DB "Test\n";
    close(DB);

    if ( $self->{postinstall} ) {
        &{ $self->{postinstall} }($self);
    }

    return $self;
}

sub start_clock {
    my ($self) = @_;
    return if ( !$self->{speed} );

    $self->{start}   = [times];
    $self->{start_t} = [Time::HiRes::gettimeofday];
}

sub stop_clock {
    my ( $self, $title ) = @_;
    return if ( !$self->{speed} );

    my @stop = times;
    $self->trace(
        sprintf(
            "[t] $title: USER = %.2f s, SYSTEM = %.2f s, REAL = %.2f s",
            $stop[2] - $self->{start}->[2],
            $stop[3] - $self->{start}->[3],
            Time::HiRes::tv_interval( $self->{start_t} )
        )
    );
}

sub see_blob {
    my ( $self, $name, $blob ) = @_;
    my $path = $self->{temp_dir} . '/' . $name;
    open FILE, ">$path";
    binmode(FILE);
    print FILE $blob;
    close FILE;
    $self->see_file($path);
}

sub see_file {
    my ( $self, $file ) = @_;
    my $ext = $file;
    $ext =~ s/.*\.//;
    $ext = lc($ext);
    my $digest = Digest::MD5->new;
    open( FILE, $file ) or die "Can't open '$file': $!";
    while (<FILE>) {
        if ( $ext eq 'pdf' ) {
            s:(^|(?<=<<))\s*/(Producer|CreationDate|ModDate)\s+\(.*\)::;
        }
        $digest->add($_);
    }
    close FILE;
    my $dig = $digest->hexdigest;
    my $ff  = $file;
    $ff =~ s:.*/::;
    if ( $self->{ok_checksums}->{$dig} ) {
        $self->trace("[T] File ok (checksum): $ff");
        return ();
    }

    if ( commande_accessible('comparepdf') ) {
        # compares with already validated file
        my $validated = $self->{temp_dir} . "/checked/$ff";
        if ( -f $validated && $ff =~ /\.pdf$/i ) {
            if ( run( 'comparepdf', '-ca', '-v0', $validated, $file ) ) {
                $self->trace("[T] File ok (compare): $ff");
                return ();
            }
        }
    }

    my $i = 0;
    my $dest;
    do {
        $dest = sprintf( "%s/%04d-%s", $self->{check_dir}, $i, $ff );
        $i++;
    } while ( -f $dest );
    copy( $file, $dest );
    push @{ $self->{to_check} }, [ $dig, $dest ];
}

sub trace {
    my ( $self, @m ) = @_;
    print { $self->{tracedest} } join( ' ', @m ) . "\n";
    if ( $self->{debug_file} ) {
        open( LOG, ">>:utf8", $self->{debug_file} )
          || die "Unable to open file $self->{debug_file} as log";
        print LOG join( ' ', @m ) . "\n";
        close LOG;
    }
}

sub command {
    my ( $self, @c ) = @_;

    $self->trace( "[*] " . join( ' ', @c ) ) if ( $self->{debug} );
    if ( !run( \@c, '>>', $self->{debug_file}, '2>>', $self->{debug_file} ) ) {
        my $cc = $c[0];
        $cc .= " " . $c[1] if ( $#c > 0 );
        $cc .= " ..."      if ( $#c > 1 );
        $self->trace("[E] Command `$cc' returned with $?");
        $self->failed(1);
    }
}

sub amc_command {
    my ( $self, $sub, @opts ) = @_;

    push @opts, '--debug', '%PROJ/debug.log' if ( $self->{debug} );
    @opts = map {
        s:%DATA:$self->{temp_dir}/data:g;
        s:%PROJ:$self->{temp_dir}:g;
        $_;
    } @opts;

    $self->command( 'auto-multiple-choice', $sub, @opts );
}

sub prepare {
    my ($self) = @_;

    $self->start_clock();
    $self->amc_command(
        'prepare',                       '--filter',
        $self->{filter},                 '--with',
        $self->{tex_engine},             '--mode',
        's[' . $self->{documents} . ']', '--epoch',
        946684800,                       '--n-copies',
        $self->{n_copies},               '--prefix',
        $self->{temp_dir} . '/',         '%PROJ/' . $self->{src},
        '--data',                        '%DATA',
    );
    $self->amc_command( 'meptex', '--src', '%PROJ/calage.xy',
        '--data', '%DATA', );
    $self->stop_clock("subject and layout");

    $self->start_clock();
    $self->amc_command(
        'prepare',           '--filter',
        $self->{filter},     '--with',
        $self->{tex_engine}, '--mode',
        'b',                 '--n-copies',
        $self->{n_copies},   '--data',
        '%DATA',             '%PROJ/' . $self->{src},
    );
    $self->stop_clock("scoring strategy");
}

sub analyse {
    my ($self, %oo) = @_;

    $self->start_clock();

    if ( ( $self->{perfect_copy} || $self->{full_scans} ) && !$oo{directory} ) {
        $self->amc_command(
            'prepare',           '--filter',
            $self->{filter},     '--with',
            $self->{tex_engine}, '--mode',
            'k',                 '--epoch',
            946684800,           '--n-copies',
            $self->{n_copies},   '--prefix',
            '%PROJ/',            '--data',
            '%DATA',             '%PROJ/' . $self->{src},
        );
    }

    if ( $self->{perfect_copy} && !$oo{directory} ) {
        my $nf = $self->{temp_dir} . "/num";
        open( NUMS, ">$nf" );
        for ( @{ $self->{perfect_copy} } ) { print NUMS "$_\n"; }
        close(NUMS);
        $self->amc_command(
            'imprime',
            '--sujet'         => '%PROJ/corrige.pdf',
            '--methode'       => 'file',
            '--output'        => '%PROJ/xx-copie-%e.pdf',
            '--fich-numeros'  => $nf,
            '--data'          => '%DATA',
            '--extract-with'  => $self->{extract_with},
            '--password'      => $self->{password},
            '--password-key'  => $self->{password_key},
            '--students-list' => '%PROJ/' . $self->{list},
            '--list-key'      => $self->{list_key},
        );

        opendir( my $dh, $self->{temp_dir} )
          || die "can't opendir $self->{temp_dir}: $!";
        my @s = grep { /^xx-copie-/ } readdir($dh);
        closedir $dh;
        push @{ $self->{scans} }, map { $self->{temp_dir} . "/$_" } @s;
    }

    if ( $self->{full_scans} && !$oo{directory} ) {
        my @cmd = (
            "gs",
            "-sDEVICE=png16m",
            "-sOutputFile=$self->{temp_dir}/full-%04d.png",
            "-r$self->{full_density}",
            "-dNOPAUSE",
            "-dSAFER",
            "-dBATCH"
        );
        push @cmd, "-dQUIET" if ( !$self->{debug} );
        system( @cmd, $self->{temp_dir} . "/corrige.pdf" );

        opendir( my $dh, $self->{temp_dir} )
          || die "can't opendir $self->{temp_dir}: $!";
        my @s = grep { /^full-/ } readdir($dh);
        closedir $dh;

        my @st = ();
        my $q  = AMC::Queue::new();
        for my $page (@s) {
            my $dest =
              $self->{temp_dir} . "/" . $page . "." . $self->{full_scans};
            $q->add_process(
                magick_module("convert"), "$self->{temp_dir}/$page",
                "-rotate",                rand(6) - 3,
                "+noise",                 "Poisson",
                "-threshold",             "40%",
                "+noise",                 "Gaussian",
                "-threshold",             "15%",
                $dest
            );
            push @st, $dest;
        }
        $q->run;
        push @{ $self->{scans} }, @st;

        $self->{perfect_copy} = [ 1 .. $self->{n_copies} ];
    }

    $self->stop_clock("fake scans build");

    # prepares a file with the scans list

    my $scans_list = $self->{temp_dir} . "/scans-list.txt";
    open( SL, ">", $scans_list ) or die "Open $scans_list: $!";
    if ( $oo{directory} ) {
        opendir( my $dh, $self->{temp_dir} . "/" . $oo{directory} )
          || die "can't opendir $oo{directory}: $!";
        my @s = sort { $a cmp $b } grep { !/^\./ } readdir($dh);
        closedir $dh;

        if (@s) {
            $self->trace( "[I] " . @s . " scans from $oo{directory}" );
            for my $f (@s) {
                print SL $self->{temp_dir} . "/"
                  . $oo{directory} . "/"
                  . $f . "\n";
            }
        }
    } else {
        for ( @{ $self->{scans} } ) { print SL "$_\n"; }
    }
    close(SL);

    #

    $self->start_clock();

    $self->amc_command(
        'read-pdfform',
        '--list'     => $scans_list,
        '--data'     => '%DATA',
        '--password' => $self->{password},
        ( $self->{multiple} ? '--multiple' : '--no-multiple' ),
    );

    my @extract_opts = ();
    if ( $self->{extract_with} =~ /^pdftk/ || $self->{force_magick} ) {
        push @extract_opts, '--no-use-qpdf';
    }
    if ( $self->{extract_with} eq 'qpdf' || $self->{force_magick} ) {
        push @extract_opts, '--no-use-pdftk';
    }
    if ( $self->{no_gs} ) {
        push @extract_opts, '--no-use-gs';
    }
    $self->amc_command(
        'getimages',
        '--list'        => $scans_list,
        '--copy-to'     => $self->{temp_dir} . "/scans",
        '--orientation' => $self->get_orientation(),
        '--password'    => $self->{password},
        (
            $self->{force_convert} || $self->{force_magick}
            ? "--force-convert"
            : "--no-force-convert"
        ),
        @extract_opts,
    );

    $self->{pre_allocate} = $oo{pre_allocate}
      if ( exists( $oo{pre_allocate} ) );

    $self->amc_command(
        'analyse',
        ( $self->{multiple} ? '--multiple' : '--no-multiple' ),
        '--bw-threshold',
        $self->{bw_threshold},
        '--pre-allocate',
        $self->{pre_allocate},
        '--tol-marque',
        $self->{tol_marque},
        ( $self->{ignore_red} ? '--ignore-red' : '--no-ignore-red' ),
        '--project-dir',
        '%PROJ',
        '--data',
        '%DATA',
        '--debug-image-dir',
        '%PROJ/cr',
        '--liste-fichiers',
        $scans_list,
    ) if ( $self->{debug} );
    $self->amc_command(
        'analyse',
        ( $self->{multiple} ? '--multiple' : '--no-multiple' ),
        '--bw-threshold',
        $self->{bw_threshold},
        '--pre-allocate',
        $self->{pre_allocate},
        '--tol-marque',
        $self->{tol_marque},
        ( $self->{ignore_red} ? '--ignore-red' : '--no-ignore-red' ),
        (
                 $self->{debug}
              || $self->{debug_pixels} ? '--debug-pixels' : '--no-debug-pixels'
        ),
        '--project-dir',
        '%PROJ', '--data', '%DATA',
        '--liste-fichiers',
        $scans_list,
    );

    $self->stop_clock("automatic data capture");

}

sub gather_multicode {
    my ($self)=@_;

    $self->note( multi => 1 );
    $self->amc_command( 'gathermulticode', '--project', '%PROJ', );
}

sub decode {
    my ($self) = @_;

    if ( $self->{decoder} ) {
        $self->amc_command( 'decode', '--data', '%DATA', '--project', '%PROJ',
            '--decoder', $self->{decoder}, );

    }
}

sub note {
    my ($self, %oo) = @_;

    $self->start_clock();
    $self->amc_command(
        'note',
        ( $oo{multi} ? "--multi-only" : "--no-multi-only" ),
        '--data',
        '%DATA',
        '--seuil',
        $self->{seuil},
        '--seuil-up',
        $self->{seuil_up},
        '--grain',
        $self->{grain},
        '--arrondi',
        $self->{rounding},
        '--notemax',
        $self->{notemax},
        '--postcorrect-student',
        $self->{postcorrect_student},
        '--postcorrect-copy',
        $self->{postcorrect_copy},
    );
    $self->stop_clock("scoring");
}

sub assoc {
    my ($self) = @_;

    return if ( !$self->{list} );

    my @code = ();
    if ( $self->{code} eq '<preassoc>' ) {
        push @code, '--pre-association';
    } else {
        push @code, '--notes-id', $self->{code};
    }

    $self->amc_command( 'association-auto', '--liste', '%PROJ/' . $self->{list},
        '--liste-key', $self->{list_key}, @code, '--data', '%DATA', );

    if ( $self->{association_manual} ) {
        for my $a ( @{ $self->{association_manual} } ) {
            $self->amc_command(
                'association',            '--liste',
                '%PROJ/' . $self->{list}, '--data',
                '%DATA',                  '--set',
                '--student',              $a->{student},
                '--copy',                 $a->{copy},
                '--id',                   $a->{id},
            );
        }
    }
}

sub get_marks {
    my ($self) = @_;

    my $sf  = $self->{temp_dir} . "/data/scoring.sqlite";
    my $dbh = DBI->connect( "dbi:SQLite:dbname=$sf", "", "" );
    $self->{marks} =
      $dbh->selectall_arrayref( "SELECT * FROM scoring_mark", { Slice => {} } );

    if ( !$self->{full_scans} ) {
        $self->trace("[I] Marks:");
        for my $m ( @{ $self->{marks} } ) {
            $self->trace(
                "    "
                  . join( ' ',
                    map { $_ . "=" . $m->{$_} }
                      (qw/student copy total max mark/) )
            );
        }
    }

    $dbh->disconnect;
}

sub get_orientation {
    my ($self) = @_;

    my $l = AMC::Data->new( $self->{temp_dir} . "/data" )->module('layout');
    $l->begin_read_transaction('tgor');
    my $o = $l->orientation();
    $l->end_transaction('tgor');

    $l->disconnect;

    return ($o);
}

sub check_perfect {
    my ($self) = @_;
    return if ( !$self->{perfect_copy} );

    $self->trace(
        "[T] Perfect copies test: "
          . (
            $self->{full_scans}
            ? "ALL"
            : join( ',', @{ $self->{perfect_copy} } )
          )
    );

    my %p = map { $_ => 1 } @{ $self->{perfect_copy} };

    for my $m ( @{ $self->{marks} } ) {
        $p{ $m->{student} } = 0
          if ( $m->{total} == $m->{max} );
    }

    for my $i ( keys %p ) {
        if ( $p{$i} ) {
            $self->trace("[E] Non-perfect copy: $i");
            $self->failed(1);
        }
    }
}

sub check_marks {
    my ($self) = @_;
    return if ( !$self->{check_marks} );

    $self->trace(
        "[T] Marks test: " . join( ',', keys %{ $self->{check_marks} } ) );

    my %p = ( %{ $self->{check_marks} } );

    for my $m ( @{ $self->{marks} } ) {
        my $st = studentids_string( $m->{student}, $m->{copy} );
        if ( defined( $p{$st} ) ) {
            if ( $p{$st} == $m->{mark} ) {
                delete( $p{$st} );
            }
        }
        $st = '/' . $self->find_assoc( $m->{student}, $m->{copy} );
        if ( defined( $p{$st} ) ) {
            delete( $p{$st} )
              if ( $p{$st} == $m->{mark} );
        }
    }

    my @no = ( keys %p );
    if (@no) {
        $self->trace( "[E] Uncorrect marks: " . join( ',', @no ) );
        $self->failed(1);
    }

}

sub get_assoc {
    my ($self) = @_;

    my $sf = $self->{temp_dir} . "/data/association.sqlite";

    if ( -f $sf ) {
        my $dbh = DBI->connect( "dbi:SQLite:dbname=$sf", "", "" );
        $self->{association} =
          $dbh->selectall_arrayref( "SELECT * FROM association_association",
            { Slice => {} } );

        $self->trace("[I] Assoc:") if ( @{ $self->{association} } );
        for my $m ( @{ $self->{association} } ) {
            for my $t (qw/auto manual/) {
                my ($n) = $self->{names}
                  ->data( $self->{list_key}, $m->{$t}, test_numeric => 1 );
                if ($n) {
                    $m->{$t} = $n->{ $self->{list_key} };
                    $m->{name} = $n->{_ID_};
                }
            }
            $self->trace(
                "    " . join(
                    ' ',
                    map {
                        $_ . "="
                          . ( defined( $m->{$_} ) ? $m->{$_} : "<undef>" )
                    } (qw/student copy auto manual name/)
                )
            );
        }

        $dbh->disconnect;
    }
}

sub find_assoc {
    my ( $self, $student, $copy ) = @_;
    my $r = '';
    for my $a ( @{ $self->{association} } ) {
        $r = ( defined( $a->{manual} ) ? $a->{manual} : $a->{auto} )
          if ( $a->{student} == $student && $a->{copy} == $copy );
    }
    return ($r);
}

sub compare {
    my ( $a, $b ) = @_;
    return ( ( ( $a eq 'x' ) && ( !defined($b) ) ) || ( $a eq $b ) );
}

sub check_assoc {
    my ($self) = @_;
    return if ( !$self->{check_assoc} );

    $self->trace( "[T] Association test: "
          . join( ',', sort { $a cmp $b } ( keys %{ $self->{check_assoc} } ) )
    );

    my %p = ( %{ $self->{check_assoc} } );

    for my $m ( @{ $self->{association} } ) {
        my $st = studentids_string( $m->{student}, $m->{copy} );
        delete( $p{$st} )
          if ( defined( $p{$st} )
            && compare( $self->{check_assoc}->{$st}, $m->{auto} ) );
        delete( $p{ 'm:' . $st } )
          if ( defined( $p{ 'm:' . $st } )
            && compare( $self->{check_assoc}->{ 'm:' . $st }, $m->{manual} ) );
    }

    my @no = ( keys %p );
    if (@no) {
        $self->trace( "[E] Uncorrect association: " . join( ',', @no ) );
        $self->failed(1);
    }

}

sub annote {
    my ($self) = @_;
    return if ( !$self->{annote} );

    my $nf = $self->{temp_dir} . "/num-pdf";
    open( NUMS, ">$nf" );
    for ( @{ $self->{annote} } ) { print NUMS "$_\n"; }
    close(NUMS);

    my @args = (
        '--verdict',          $self->{verdict},
        '--verdict-question', $self->{verdict_question},
        '--position',         $self->{annote_position},
        '--text-color',       $self->{annote_color},
        '--project',          '%PROJ',
        '--data',             '%DATA',
        ( $self->{annote_ascii}
            ? "--force-ascii"
            : "--no-force-ascii" ),
        '--n-copies',              $self->{n_copies},
        '--subject',               '%PROJ/sujet.pdf',
        '--src',                   '%PROJ/' . $self->{src},
        '--with',                  $self->{tex_engine},
        '--filename-model',        $self->{model},
        '--id-file',               '%PROJ/num-pdf',
        '--darkness-threshold',    $self->{seuil},
        '--darkness-threshold-up', $self->{seuil_up},
    );
    push @args, '--names-file', '%PROJ/' . $self->{list} if ( $self->{list} );

    my $single_output = '';
    if ( $self->{annotate_single} ) {
        $single_output = $self->{annotate_single}->{filename} || "all.pdf";
        push @args, '--single-output', $single_output;
    }

    $self->amc_command( 'annotate', @args );

    my $pdf_dir = $self->{temp_dir} . '/cr/corrections/pdf';
    opendir( my $dh, $pdf_dir )
      || die "can't opendir $pdf_dir: $!";
    my @pdf = grep { /\.pdf$/i } readdir($dh);
    closedir $dh;
    if ( !$self->{blind} ) {
        for my $f (@pdf) { $self->see_file( $pdf_dir . '/' . $f ); }
    }

    if ($single_output) {
        if ( $self->{annotate_single}->{npages} ) {
            if (
                open( INFO, "-|",
                    "pdfinfo", $pdf_dir . '/' . $single_output
                )
              )
            {
                my $np = 0;
                while (<INFO>) {
                    $np = $1 if (/^Pages:\s*([0-9]+)/);
                }
                close INFO;
                if ( $np == $self->{annotate_single}->{npages} ) {
                    $self->trace("[T] Single annotated PDF: $np pages");
                } else {
                    $self->trace(
"[E] Wrong number of pages for single annotated PDF: $np instead of "
                          . $self->{annotate_single}->{npages} );
                    $self->failed(1);
                }
            } else {
                $self->trace("[E] pdfinfo failed: $!");
                $self->failed(1);
            }
        }
    }

    if ( @{ $self->{annote_files} } ) {
        my %p = map { $_ => 1 } @pdf;
        for my $f ( @{ $self->{annote_files} } ) {
            if ( !$p{$f} ) {
                $self->trace("[E] Annotated file $f has not been generated.");
                $self->failed(1);
            }
        }
        $self->trace( "[T] Annotated file names: "
              . join( ', ', @{ $self->{annote_files} } ) );
    }
}

sub ok {
    my ($self) = @_;

    $self->end;

    if($self->{additional_test}) {
        &{ $self->{additional_test} }($self);
    }

    if ( $self->{error} ) {
        $self->trace("[E] Test failed (see errors above)");
    } else {
        if ( @{ $self->{to_check} } ) {
            $self->trace( "[?] "
                  . ( 1 + $#{ $self->{to_check} } )
                  . " files to check in $self->{check_dir}:" );
            for ( @{ $self->{to_check} } ) {
                $self->trace( "    " . $_->[0] . " " . $_->[1] );
            }
            $self->failed(2) if ( !$self->{blind} );
        } else {
            $self->trace("[0] Test completed succesfully");
        }
    }
}

sub get_defects {
    my ($self) = @_;

    my $l = AMC::Data->new( $self->{temp_dir} . "/data" )->module('layout');
    $l->begin_read_transaction('test');
    my $d = { $l->defects() };
    $l->end_transaction('test');

    $l->disconnect;

    return ($d);
}

sub defects {
    my ($self) = @_;

    my $d = $self->get_defects();
    delete $d->{NO_NAME};
    my @t = ( keys %$d );
    if (@t) {
        $self->trace( "[E] Layout defects: " . join( ', ', @t ) );
        $self->failed(1);
    } else {
        $self->trace("[T] No layout defects");
    }
}

sub check_topics {
    my ($self) = @_;
    my @tests = @{ $self->{check_topics} };
    if (@tests) {
        my @checks = ();
        my @errs   = ();

        set_debug( $self->{debug_file} );

        $self->begin( "Topics test (" . @tests . " values)" );
        my $data   = AMC::Data->new( $self->{temp_dir} . "/data" );
        my $topics = AMC::Topics->new(
            project_dir => $self->{temp_dir},
            data        => $data
        );
        $data->begin_read_transaction("ttop");
        for my $test (@tests) {
            if ( $test->{-copy} && !$test->{-student} ) {
                if ( $test->{-copy} =~ /^(.*):(.*)$/ ) {
                    $test->{-student} = $1;
                    $test->{-copy}    = $2;
                } else {
                    $test->{-student} = $test->{-copy};
                    $test->{-copy}    = 0;
                }
            }
            my $id = $test->{-id};
            my ($t) = grep { $_->{id} eq $id } ( $topics->all_topics );
            if ($t) {
                my $m = $topics->student_topic_message( $test->{-student},
                                                        ($test->{-copy} || 0), $t );
                my $i = 0;
                for my $key (qw/message color/) {
                    if ( defined( $test->{ "-" . $key } ) ) {
                        push @checks,
                          [
                            $m->{$key},
                            $test->{ "-" . $key },
"Topic '$id' $key for copy ($test->{-student},$test->{-copy})"
                          ];
                        $i++;
                    }
                }
                if ( !$i ) {
                    push @errs, "[E] Empty test for topic '$id' and copy ($test->{-student},$test->{-copy})";
                }
            } else {
                push @errs, "[E] Topic not found: $id";
            }
        }
        $data->end_transaction("ttop");
        $data->disconnect("topics");

        set_debug('');

        for my $c (@checks) {
            $self->test(@$c);
        }
        for my $e (@errs) {
            $self->trace($e);
            $self->failed(1);
        }

        $self->end;
    }
}

sub check_export {
    my ($self) = @_;
    $self->check_export_csv( key => 'export_full_csv' );
    $self->check_export_csv( key => 'export_full_ods', via_ods => 1 );
}

sub check_export_csv {
    my ($self, %opts) = @_;
    my @csv = @{ $self->{$opts{key}} };
    if (@csv) {
        $self->begin( ( $opts{via_ods} ? "ODS" : "CSV" )
            . " full export test ("
              . ( 1 + $#csv )
              . " scores)" );
        my @args = (
            '--data',       '%DATA', '--association-key', $self->{list_key},
            '--option-out', 'columns=' . $self->{export_columns},
        );
        if ( $opts{via_ods} ) {
            push @args, "--module", "ods", "-o", '%PROJ/export.ods';
        } else {
            push @args,
              '--option-out', 'ticked=' . $self->{export_csv_ticked},
              '--option-out', 'decimal=' . $self->{export_csv_decimal},
              '--module',     'CSV',
              '-o',           '%PROJ/export.csv';
        }
        push @args, '--fich-noms', '%PROJ/' . $self->{list}
          if ( $self->{list} );
        $self->amc_command( 'export', @args );

        my $skip_lines = 0;

        if ( $opts{via_ods} ) {
            my $ok;
            {
                local $ENV{LANG} = 'C';
                $ok =
                  run( ["unoconv", "-f", "csv", "$self->{temp_dir}/export.ods"],
                    '2>>', '/dev/null' );
            }
            if ( !$ok ) {
                $self->trace("[E] Command `unoconv' returned with $?");
                $self->failed(1);
            }
            $skip_lines = 2;
        }

        my $c = Text::CSV->new();
        open my $fh, "<:encoding(utf-8)", $self->{temp_dir} . '/export.csv';

        if($skip_lines) {
            for my $ii (1..$skip_lines) {
                $c->getline($fh);
            }
        }
        my %heads = ();
        my $i=0;
        my $h = $c->getline($fh);
        while ( my ( $i, $h ) = each @$h ) {
            if ( defined( $heads{$h} ) ) {
                my $ni = 2;
                while ( defined( $heads{ $h . "#$ni" } ) ) {
                    $ni++;
                }
                $heads{ $h . "#$ni" } = $i;
            } else {
                $heads{$h} = $i;
            }
        }

        my $copy  = $heads{ translate_column_title('copie') };
        my $name  = $heads{ translate_column_title('nom') };

        if ( !defined($copy) && !defined($name) ) {
            $self->trace( "[E] CSV: "
                  . translate_column_title('copie') . ' or '
                  . translate_column_title('nom')
                  . " columns not found" );
            $self->failed(1);
        }
        my $irow = 0;
        while ( my $row = $c->getline($fh) ) {
            $irow++;
            for my $t (@csv) {
                my $goodrow = '';
                if (   $t->{-copy}
                    && defined($copy)
                    && $t->{-copy} eq $row->[$copy] )
                {
                    $goodrow = 'copy ' . $t->{-copy};
                }
                if (   $t->{-name}
                    && defined($name)
                    && $t->{-name} eq $row->[$name] )
                {
                    $goodrow = 'name ' . $t->{-name};
                }
                if ( $t->{-irow} && $t->{-irow} == $irow ) {
                    $goodrow = 'irow ' . $t->{-irow};
                }
                if (   $goodrow
                    && $t->{-question}
                    && defined( $heads{ $t->{-question} } )
                    && $t->{-abc} )
                {
                    $self->test(
                        $row->[ $heads{ "TICKED:" . $t->{-question} } ],
                        $t->{-abc}, "ABC for $goodrow Q=" . $t->{-question} );
                    $t->{checked} = 1;
                }
                if (   $goodrow
                    && $t->{-question}
                    && defined( $heads{ $t->{-question} } )
                    && defined( $t->{-score} ) )
                {
                    $self->test(
                        $row->[ $heads{ $t->{-question} } ],
                        $t->{-score},
                        "score for $goodrow Q=" . $t->{-question},
                        digits => $t->{-digits}
                    );
                    $t->{checked} = 1;
                }
                if (   $goodrow
                    && $t->{-aname} )
                {
                    $self->test( $row->[ $name ],
                        $t->{-aname}, "name for $goodrow" );
                    $t->{checked} = 1;
                }
            }
        }
        close $fh;
        for my $t (@csv) {
            if ( !$t->{checked} ) {
                $self->trace( "[E] CSV: line not found. "
                      . join( ', ', map { $_ . '=' . $t->{$_} } ( keys %$t ) )
                );
                $self->failed(1);
            }
        }
        $self->end;
    }

    if ( $self->{export_ods} ) {
        require OpenOffice::OODoc;

        $self->begin("ODS full export test");
        my @args = (
            '--data',            '%DATA',
            '--module',          'ods',
            '--association-key', $self->{list_key},
            '--option-out',      'columns=' . $self->{export_columns},
            '--option-out',      'stats=h',
            '-o',                '%PROJ/export.ods',
        );
        push @args, '--fich-noms', '%PROJ/' . $self->{list}
          if ( $self->{list} );
        $self->amc_command( 'export', @args );
        my $doc = OpenOffice::OODoc::odfDocument(
            file => $self->{temp_dir} . '/export.ods' );
        my %iq = ();
        my $i  = 0;

        while ( my $id = $doc->getCellValue( 1, 0, $i ) ) {
            $iq{$id} = $i;
            $i += 5;
        }
      ONEQ: for my $q ( @{ $self->{export_ods}->{stats} } ) {
            my $i = $iq{ $q->{id} };
            if ( defined($i) ) {
                $self->test( $doc->getCellValue( 1, 2, $i + 1 ),
                    $q->{total}, 'total' );
                $self->test( $doc->getCellValue( 1, 3, $i + 1 ),
                    $q->{empty}, 'empty' );
                $self->test( $doc->getCellValue( 1, 4, $i + 1 ),
                    $q->{invalid}, 'invalid' );
                for my $a ( @{ $q->{answers} } ) {
                    $self->test( $doc->getCellValue( 1, 4 + $a->{i}, $i + 1 ),
                        $a->{ticked}, 'stats:' . $q->{id} . ':' . $a->{i} );
                }
            } else {
                $self->trace(
                    "[E] Stats: question not found in stats table: $q->{id}");
                $self->failed(1);
            }
        }
        $self->end;
    }
}

sub check_zooms {
    my ($self) = @_;
    my $cz     = $self->{check_zooms};
    my @zk     = keys %$cz;
    return if ( !@zk );

    my $capture =
      AMC::Data->new( $self->{temp_dir} . "/data" )->module('capture');
    $capture->begin_read_transaction('cZOO');

    for my $p ( keys %{$cz} ) {
        $self->trace("[T] Zooms check : $p");

        my ( $student, $page, $copy );
        if ( $p =~ /^([0-9]+)-([0-9]+):([0-9]+)$/ ) {
            $student = $1;
            $page    = $2;
            $copy    = $3;
        } elsif ( $p =~ /^([0-9]+)-([0-9]+)$/ ) {
            $student = $1;
            $page    = $2;
            $copy    = 0;
        }

        my @zooms = grep { $_->{imagedata} } (
            @{
                $capture->dbh->selectall_arrayref(
                    $capture->statement('pageZonesDI'),
                    { Slice => {} },
                    $student, $page, $copy, ZONE_BOX
                )
            }
        );

        if ( 1 + $#zooms == $cz->{$p} ) {
            for (@zooms) {
                $self->see_blob(
                    "zoom-"
                      . $student . "-"
                      . $page . ":"
                      . $copy . "--"
                      . $_->{id_a} . "-"
                      . $_->{id_b} . ".png",
                    $_->{imagedata}
                );
            }
        } else {
            $self->trace( "[E] Zooms dir $p contains "
                  . ( 1 + $#zooms )
                  . " elements, but needs "
                  . $cz->{$p} );
            $self->failed(1);
        }
    }

    $capture->end_transaction('cZOO');
    $capture->disconnect;
}

sub check_textest {
    my ( $self, $tex_file ) = @_;
    if ( !$tex_file ) {
        opendir( my $dh, $self->{dir} )
          || die "can't opendir $self->{dir}: $!";
        my @tex = grep { /\.tex$/ } readdir($dh);
        closedir $dh;
        $tex_file = $tex[0] if (@tex);
    }
    $tex_file = $self->{temp_dir} . "/" . $tex_file;
    if ( -f $tex_file ) {
        my ( @value_is, @value_shouldbe );
        chomp( my $cwd = `pwd` );
        chdir( $self->{temp_dir} );
        open( TEX, "-|", $self->{tex_engine}, $tex_file );
        while (<TEX>) {
            if (/^\!/) {
                $self->trace("[E] latex error: $_");
                $self->failed(1);
            }
            if (/^SECTION\((.*)\)/) {
                $self->end();
                $self->begin($1);
            }
            if (/^TEST\(([^,]*),([^,]*)\)/) {
                $self->test( $1, $2 );
            }
            if (/^VALUEIS\((.*)\)/) {
                push @value_is, $1;
            }
            if (/^VALUESHOULDBE\((.*)\)/) {
                push @value_shouldbe, $1;
            }
        }
        close(TEX);
        chdir($cwd);
        if (@value_shouldbe) {
            for my $i ( 0 .. $#value_shouldbe ) {
                $self->test( $value_is[$i], $value_shouldbe[$i] );
            }
        }
        $self->end();
    } else {
        $self->trace("[X] TeX file not found: $tex_file");
        $self->failed(1);
    }
  }

sub check_subject {
    my ($self) = @_;
    $self->see_file( $self->{temp_dir} . "/sujet.pdf" );
}

sub data {
    my ($self) = @_;
    return ( AMC::Data->new( $self->{temp_dir} . "/data" ) );
}

sub begin {
    my ( $self, $title ) = @_;
    $self->end if ( $self->{test_title} );
    $self->{test_title} = $title;
    $self->{'n.subt'}   = 0;
}

sub end {
    my ($self) = @_;
    $self->trace( "[T] "
          . ( $self->{'n.subt'} ? "(" . $self->{'n.subt'} . ") " : "" )
          . $self->{test_title} )
      if ( $self->{test_title} );
    $self->{test_title} = '';
}

sub datadump {
    my ($self) = @_;
    if ( $self->{datamodule} && $self->{datatable} ) {
        print Dumper(
            $self->{datamodule}->dbh->selectall_arrayref(
                "SELECT * FROM $self->{datatable}",
                { Slice => {} }
            )
        );
    }
    $self->{datamodule}->end_transaction
      if ( $self->{datamodule} );
}

sub test {
    my ( $self, $x, $v, $subtest, %opts ) = @_;
    if ( !defined($subtest) ) {
        $subtest = ++$self->{'n.subt'};
    }
    if ( ref($x) eq 'ARRAY' ) {
        for my $i ( 0 .. $#$x ) {
            $self->test( $x->[$i], $v->[$i], 1, %opts );
        }
    } else {
        no warnings 'uninitialized';
        if ( defined( $opts{digits} ) && $opts{digits} ne '' ) {
            for my $z ( \$x, \$v ) {
                $$z = sprintf( "%.$opts{digits}f", $$z );
            }
        }
        if ( $x ne $v ) {
            $self->trace( "[E] "
                  . $self->{test_title}
                  . " [$subtest] : \'$x\' should be \'$v\'" );
            $self->datadump;
            $self->failed(1);
        }
    }
}

sub test_undef {
    my ( $self, $x ) = @_;
    $self->{'n.subt'}++;
    if ( defined($x) ) {
        $self->trace( "[E] "
              . $self->{test_title}
              . " [$self->{'n.subt'}] : \'$x\' should be undef" );
        $self->datadump;
        $self->failed(1);
    }
}

sub test_scoring {
    my ( $self, $question, $answers, $target_score ) = @_;

    my $data = AMC::Data->new( $self->{temp_dir} . "/data" );
    my $s    = $data->module('scoring');
    my $c    = $data->module('capture');

    $s->begin_transaction('tSCO');

    $s->clear_strategy;
    $s->clear_score;
    $s->new_question( 1, 1,
        ( $question->{multiple} ? QUESTION_MULT : QUESTION_SIMPLE ),
        0, $question->{strategy} );
    my $i      = 0;
    my $none   = 1;
    my $none_t = 1;

    for my $a (@$answers) {
        $i++ if ( !$a->{noneof} );
        $none = 0 if ( $a->{correct} );
        $s->new_answer( 1, 1, $i, $a->{correct}, $a->{strategy} );
        $none_t = 0 if ( $a->{ticked} );
        $c->set_zone_manual( 1, 1, 0, ZONE_BOX, 1, $i, $a->{ticked} );
    }
    if ( $question->{noneof_auto} ) {
        $s->new_answer( 1, 1, 0, $none, '' );
        $c->set_zone_manual( 1, 1, 0, ZONE_BOX, 1, 0, $none_t );
    }

    my $qdata = $s->student_scoring_base( 1, 0, 0.5, 1.0 );

    $s->end_transaction('tSCO');

    my $scoring = AMC::Scoring->new( data => $data );
    $scoring->set_default_strategy( $question->{default_strategy} )
      if ( $question->{default_strategy} );

    set_debug( $self->{debug_file} );

    $scoring->prepare_question( $qdata->{questions}->{1} );
    my ( $score, $why ) =
      $scoring->score_question( 1, $qdata->{questions}->{1}, 0 );

    set_debug('');

    $self->test( $score, $target_score );

    $data->disconnect;
}

sub update_sqlite {
    my ($self) = @_;
    my $d = AMC::Data->new( $self->{temp_dir} . "/data" );
    for my $m (qw/layout capture scoring association report/) {
        $d->module($m);
    }
    return ($self);
}

sub check_pages {
    my ($self) = @_;
    if ( $self->{pages} ) {
        $self->trace( "[T] Pages check : " . join( ",", @{ $self->{pages} } ) );
        my $l = AMC::Data->new( $self->{temp_dir} . "/data" )->module('layout');
        $l->begin_read_transaction('npag');
        for my $i ( 0 .. $#{ $self->{pages} } ) {
            my @p  = $l->pages_for_student( $i + 1 );
            my $mx = -1;
            for my $pp (@p) {
                $mx = $pp if $pp > $mx;
            }
            $self->test( $mx, $self->{pages}->[$i] );
        }
        $l->end_transaction('npag');
        $l->disconnect;
    }
}

sub report_hardware {
    my ($self) = @_;
    return if ( !$self->{speed} );

    my %cpus = ();
    open( CPU, "/proc/cpuinfo" );
    while (<CPU>) {
        chomp;
        if (/model name\s*:\s*(.*)/) {
            $cpus{$1}++;
        }
    }
    close CPU;
    for my $c ( keys %cpus ) {
        $self->trace("[i] $cpus{$c} × $c");
    }

    open( MEM, "/proc/meminfo" );
    while (<MEM>) {
        chomp;
        if (/MemTotal\s*:\s*(.*)/) {
            $self->trace("[i] memory: $1");
        }
    }
    close MEM;
}

sub report_uninitialized {
    my ($self) = @_;
    my $u = 0;
    open( LOG, $self->{debug_file} );
    while (<LOG>) {
        if ( /uninitialized/i && !/at \(eval [0-9]+\) line/ ) {
            $u += 1 ;
            print STDERR;
        }
    }
    close LOG;
    $self->trace("[i] uninitialized: $u") if ($u);
}

sub may_fail {
    my ($self) = @_;
    $self->trace("[I] Test fail accepted.");
}

sub default_process {
    my ($self) = @_;

    $self->prepare       if ( !$self->{skip_prepare} );
    $self->check_subject if ( $self->{check_subject} );
    $self->defects;
    $self->check_pages;
    if ( !$self->{skip_scans} ) {
        $self->analyse;
        $self->decode;
    }
    $self->check_zooms;
    $self->note;
    $self->assoc;
    $self->get_assoc;
    $self->get_marks;
    $self->check_marks;
    $self->check_perfect;
    $self->check_assoc;
    $self->annote;
    $self->check_topics;
    $self->check_export;
    $self->report_hardware;

    $self->report_uninitialized;

    $self->ok;

    return $self;
}

1;

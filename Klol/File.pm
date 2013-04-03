package Klol::File;

use Modern::Perl;
use Klol::Config;
use Klol::Run;
use Archive::Extract;
use File::Spec;

sub extract_archive {
    my ($params)     = @_;
    my $archive_path = $params->{archive_path};
    my $to           = $params->{to};
    my $archive;
    eval { $archive = Archive::Extract->new( archive => $archive_path ); };
    die "The pulled file is not a directory and not a valid archive, I don't know what I have to do! ($@)"
      if $@;
    $archive->extract( to => $to )
      or die
      "I cannot extract the archive ($archive_path) to $to ($archive->error)";
}

sub pull {
    my ($params) = @_;
    my $host     = $params->{host};
    my $user     = $params->{user};
    my $identity_file = $params->{identity_file};
    my $from     = $params->{from};
    my $to       = $params->{to};

    unless ( $to ) {
        my $config   = Klol::Config->new;
        $to = $config->{path}{tmp};
    }
    eval {
        # Don't use scp here, it follows link, what we don't want!
        Klol::Run->new(
            q{rsync -avz -e "ssh}
            . ( $identity_file ? qq{ -i $identity_file} : q{} )
            . qq{" $user\@$host:$from $to}
        );
    };
    die "I cannot pull the file $host:$from ($@)" if $@;

    my ( undef, undef, $pulled_filename ) = File::Spec->splitpath($from);
    my $abs_path = File::Spec->catfile( $to, $pulled_filename );
    return $abs_path if -e $abs_path;
    die "The file is pulled but I cannot find it in $abs_path";
}

1;

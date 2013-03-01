package Klol::Config;

use Modern::Perl;
use YAML;
use File::Basename;
use Cwd 'abs_path';

sub new {
    my ( $class, $filename ) = @_;

    $filename //= dirname( abs_path( $0 ) ) . '/etc/config.yaml';

    my $self = YAML::LoadFile($filename);
    bless( $self, $class );
}

1;

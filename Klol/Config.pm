package Klol::Config;

use Modern::Perl;
use YAML;
use File::Basename qw{ dirname };
use Cwd qw{ abs_path };

sub new {
    my ( $class, $filename ) = @_;

    $filename //= dirname( abs_path( $0 ) ) . '/etc/config.yaml';

    my $self = YAML::LoadFile($filename);
    bless( $self, $class );
}

1;

__END__

=pod

=head1 NAME

Klol::Config - Config class

=head1 DESCRIPTION

return the yaml configuration file

=head1 METHODS

=head2 new

    my $config = Config->new;
    my $config = Config->new( $filename );

Constructor, return the configuration object from an optional given file.

=head1 AUTHORS

Jonathan Druart <jonathan.druart@biblibre.com>

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.


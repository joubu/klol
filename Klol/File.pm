package Klol::File;

use Modern::Perl;
use Klol::Config;
use Klol::Run;
use File::Spec;

sub extract_archive {
    my ($params)     = @_;
    my $archive_path = $params->{archive_path};
    my $to           = $params->{to};
    my $archive;
    eval {
        Klol::Run->new(
            qq{tar zxvf $archive_path --same-permissions --same-owner -C $to}
        );
    };

    die "I cannot extract the archive ($archive_path) to $to ( $@ )"
        if $@;

    return $to;
}

sub pull {
    my ($params) = @_;
    my $host     = $params->{host};
    my $user     = $params->{user};
    my $identity_file = $params->{identity_file};
    my $from     = $params->{from};
    my $to       = $params->{to};
    my $verbose  = $params->{verbose};

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
            . ( $verbose ? q{ --progress} : q{} )
            , { verbose => $verbose }
        );
    };
    die "I cannot pull the file $host:$from ($@)" if $@;

    my ( undef, undef, $pulled_filename ) = File::Spec->splitpath($from);
    my $abs_path = File::Spec->catfile( $to, $pulled_filename );
    return $abs_path if -e $abs_path;
    die "The file is pulled but I cannot find it in $abs_path";
}

sub push {
    my ($params) = @_;
    my $host     = $params->{host};
    my $user     = $params->{user};
    my $identity_file = $params->{identity_file};
    my $from     = $params->{from};
    my $to       = $params->{to};

    unless ( $to ) {
        $to = '/tmp';
    }
    eval {
        Klol::Run->new(
            q{rsync -avz -e "ssh}
            . ( $identity_file ? qq{ -i $identity_file} : q{} )
            . qq{" $from $user\@$host:$to}
        );
    };
    die "I cannot push the file $from ($@)" if $@;
}

1

__END__

=pod

=head1 NAME

Klol::File

=head1 DESCRIPTION

Provide some routines for a file

=head1 ROUTINES

=head2 extract_archive

    my $config = File::extract_archive(
        {
            archive_path => '/path/to/the/archive.tar.gz',
            to           => '/destination/path'
        };
    );

Extract a tar.gz archive to a directory
Return the directory where files have been extracted or raise an error.

=head2 pull

    my $pulled_filepath = File::pull(
        {
            host => 'host.example.org',
            user => 'login',
            identity_file => '/home/user/.ssh/id_rsa',
            from => '/file/to/pull',
            to   => '/local/destination/path',
            verbose => 1
        }
    );

Pull a file or a directory from a remote host using rsync over ssh.
The identity_file is optional, if not given the ssh password will be requested.
If the verbose flag is set, the progress will be displayed.

Return the absolute file or directory path of the pulled stuff.

=head2 push

    File::push
        {
            host => 'host.example.org',
            user => 'login',
            identity_file => '/home/user/.ssh/id_rsa',
            from => '/file/to/push',
            to   => '/remote/destination/path',
        }
    );

Push a file or a directory to a remote host using rsync over ssh.
The identity_file is optional, if not given the ssh password will be requested.

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


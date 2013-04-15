package Klol::Config::Ssh;

use Modern::Perl;
use File::Slurp qw{ read_file write_file };

use Klol::Config;

sub add_host {
    my ( $params ) = @_;
    my $name = $params->{name};

    my $config = Klol::Config->new;
    my $user          = $config->{lxc}{containers}{user};
    my $identity_file = $config->{lxc}{containers}{identity_file};

    my $line = <<EOH;
Host $name.vm
    Hostname pro.$name.vm
    User koha
    IdentityFile $identity_file
EOH

    write_file( qq{/home/$user/.ssh/config}, {append => 1}, "\n$line" );
}

sub remove_host {
    my ( $params ) = @_;
    my $name = $params->{name};

    my $config = Klol::Config->new;
    my $user = $config->{lxc}{containers}{user};
    my $ssh_cf = qq{/home/$user/.ssh/config};

    my @lines;
    tie @lines, 'Tie::File', $ssh_cf;
    my $match;
    my @block = (
        qq{Hostname pro.$name.vm},
        qq{User koha},
        qq{IdentityFile},
    );
    for my $line ( @lines ) {
        if ( $line =~ m|^Host $name.vm$| ) {
            $match = 1;
            $line =~ s/^/#/;
        } elsif ( $line =~ m|^Host| ) {
            $match = 0;
        } elsif ( $match ) {
            for my $b ( @block ) {
                $line =~ s/^/#/
                    if $line =~ m|$b|;
            }
        }
    }
    untie @lines;
}

1;

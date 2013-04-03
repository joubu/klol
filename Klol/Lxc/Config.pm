package Klol::Lxc::Config;

use Modern::Perl;
use File::Path qw{ make_path };
use File::Basename qw{ dirname };
use File::Slurp qw{ read_file write_file};
use File::Spec;
use Tie::File;
use Klol::Config;


# FIXME IPV4 specific
sub get_next_ip {
    my $lines = shift;
    my ( $first_bit, $second_bit, $third_bit, @last_bits );
    for my $line ( split '\n', $lines ) {
        next unless $line;
        if ( $line =~ m/.*,([^,]*)$/ ) {
            my $ip = $1;
            if ( $ip =~ m/(\d+)\.(\d+)\.(\d+)\.(\d+)$/ ) {
                unless ( $first_bit ) {
                    $first_bit = $1;
                    $second_bit = $2;
                    $third_bit = $3
                } else {
                    die "I cannot get a new valid IP if IPs in the config file are not in the same network (and mask 255.255.255.0)\
First ip different is $ip"
                        if $first_bit != $1 or $second_bit != $2 or $third_bit != $3;
                }
                push @last_bits, $4
            }
        }
    }
    my @sorted = sort {$a <=> $b} @last_bits;
    my $last_bit = (pop @sorted) + 1;
    return qq{$first_bit.$second_bit.$third_bit.$last_bit};
}

sub add_host {
    my ( $params ) = @_;
    my $hostname = $params->{name};
    my $hwaddr = $params->{hwaddr};

    my $config = Klol::Config->new;
    my $dnsmasq_cf = $config->{lxc}{dnsmasq_config_file};
    die "No config file defined for dnsmasq in your yaml config file"
        unless $dnsmasq_cf;

    my $config_dir = dirname( $dnsmasq_cf );
    unless ( -d $config_dir ) {
        make_path $config_dir
            or die "I cannot create the config dir ($config_dir)for dnsmasq ($!)";
    }

    my $content;
    if ( -f $dnsmasq_cf ) {
        $content = read_file( $dnsmasq_cf )
            or die "I cannot read the dnsmasq config file ($dnsmasq_cf) ($!)";
    }

    my $ip = get_next_ip( $content );
    my $new_line = "\n$hwaddr,$hostname,$ip";

    write_file( $dnsmasq_cf, {append => 1}, $new_line );

    return $ip;
}

sub remove_host {
    my ( $params ) = @_;
    my $hostname = $params->{name};

    my $config = Klol::Config->new;
    my $dnsmasq_cf = $config->{lxc}{dnsmasq_config_file};
    die "No config file defined for dnsmasq in your yaml config file"
        unless $dnsmasq_cf;

    my $config_dir = dirname( $dnsmasq_cf );
    return unless -d $config_dir;

    my $content;
    if ( -f $dnsmasq_cf ) {
        $content = read_file( $dnsmasq_cf )
            or die "I cannot read the dnsmasq config file ($dnsmasq_cf) ($!)";
    }

    $content = join (
        "\n",
        map {
            $_ !~ m|^.*,$hostname,.*$|
                ? $_
                : ()
        } split "\n", $content
    ) . "\n";
    write_file( $dnsmasq_cf, $content );
}

# FIXME IPV4 specific
sub add_interfaces {
    my ( $params ) = @_;
    my $name = $params->{name};
    my $if = $params->{interface};
    my $config = Klol::Config->new;
    my $if_filepath = File::Spec->catfile(
        $config->{lxc}{containers}{path},
        $name,
        q{rootfs},
        q{etc}, q{network}, q{interfaces}
    );
    my @if_lines;
    tie @if_lines, 'Tie::File', $if_filepath;
    unless ( grep { /eth0/ } @if_lines ) {
        push @if_lines, qq{auto $if};
        push @if_lines, qq{iface $if inet dhcp};
    }
    untie @if_lines;
}

# It should be useless, lxc.utsname should do the job but it is not the case
sub update_hostname {
    my ( $params ) = @_;
    my $name = $params->{name};
    my $config = Klol::Config->new;
    my $hn_filepath = File::Spec->catfile(
        $config->{lxc}{containers}{path},
        $name,
        q{rootfs},
        q{etc}, q{hostname}
    );
    write_file( $hn_filepath, $name );
}

sub add_ssh_pubkey {
    my ( $params ) = @_;
    my $name = $params->{name};
    my $identity_file = $params->{identity_file};
    unless ( -f "$identity_file.pub" ) {
        die "I don't know the public key for $identity_file";
    }
    my $config = Klol::Config->new;
    my $ssh_filepath = File::Spec->catfile(
        $config->{lxc}{containers}{path},
        $name,
        q{rootfs},
        q{home}, q{koha}, q{.ssh}
    );
    my $ak_filepath = File::Spec->catfile( $ssh_filepath, q{authorized_keys} );
    unless ( -d $ssh_filepath ) {
        make_path $ssh_filepath;
        chown 1000, 1000, $ssh_filepath; # FIXME I suppose koha is 1000
        chmod 0700, $ssh_filepath;
    };
    my $pubkey = read_file( "$identity_file.pub" );
    write_file( $ak_filepath, {append => 1, perms => 600}, $pubkey );
    chown 1000, 1000, $ak_filepath; # FIXME I suppose koha is 1000
    chmod 0600, $ak_filepath;
}

1;

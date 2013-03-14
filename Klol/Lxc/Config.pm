package Klol::Lxc::Config;

use Modern::Perl;
use File::Path qw{ make_path };
use File::Basename qw{ dirname };
use File::Slurp qw{ read_file write_file};
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
    my $new_line = "\ndhcp-host=$hwaddr,$hostname,$ip";

    write_file( $dnsmasq_cf, {append => 1}, $new_line );

    return $ip;
}

1;

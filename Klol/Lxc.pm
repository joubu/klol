package Klol::Lxc;

use Klol::Run;

use Modern::Perl;
use File::Basename qw{ basename };
use File::Path qw{ make_path remove_tree };
use Tie::File;


sub check_config {

    unless ( -f q{/usr/bin/lxc-version} ) {
        die "The lxc binary file lxc-version is missing, is lxc installed?"
    }

    my $cmd = q{/usr/bin/lxc-version};
    my $r = Klol::Run->new( $cmd );

    return ["your lxc-version does not return success"]
        unless $r->success;
    my @stdout = $r->stdout;
    if ( @stdout and $stdout[0] =~ 'lxc version: (\d+\.\d+).*\s*' ) {
        my $version = $1;
        chomp $version;
        if ( $version < '0.8' ) {
            die "Your lxc version is too old";
        }
    }

    $cmd = q{/usr/bin/lxc-checkconfig};
    $r = Klol::Run->new( $cmd );
    my @errors;
    for my $line ( $r->full ) {
        chomp $line;
        push @errors, $line 
            if $line =~ /missing/
                or $line =~ /required/;
    }

    return @errors ? \@errors : $r->{success};
}

sub is_vm {
    my $vm_name = shift;
    return 0 unless $vm_name;
    return 1 if grep {$_ eq $vm_name} list_vms();
    return 0;
}

sub list_vms {
    my $cmd = q{/usr/bin/lxc-ls};
    my $r = Klol::Run->new( $cmd );

    my @vms;
    for my $line ( $r->stdout ) {
        $line =~ s|^\s*(.*)\s*$|$1|;
        push @vms, $line;
    }
    return @vms;
}

sub is_started {
    my $vm_name = shift;
    my $cmd = qq{lxc-info -n $vm_name | grep state | awk '{print \$2}'};
    my $r = Klol::Run->new( $cmd );
    return 1 if $r->stdout eq q{RUNNING};
}

sub start {
    my $vm_name = shift;
    my $cmd = qq{/usr/bin/lxc-start -n $vm_name -d};
    my $r = Klol::Run->new( $cmd );
    return $r->success;
}

# From lxc-ip http://sourceforge.net/users/gleber/
sub ip {
    my $vm_name = shift;
    my $r = Klol::Run->new(
        qq{/usr/bin/lxc-info -n $vm_name -p | awk '{print \$2}'}
    );
    my $pid = $r->stdout;
    $r = Klol::Run->new( q{mktemp -u --tmpdir=/run/netns/} );
    my $dst = $r->stdout;
    my $name = basename $dst;
    chomp $name;
    unless ( -d q{/run/netns} ) {
        make_path q{/run/netns}
            or die "I cannot create /run/netns";
    }
    Klol::Run->new( qq{ln -s /proc/$pid/ns/net $dst} );
    $r = Klol::Run->new(
        qq{/bin/ip netns exec $name ip -4 addr show scope global | grep inet | awk  '{print \$2}' | cut -d '/' -f1}
    );
    my $ip = $r->stdout;
    remove_tree $dst;

    return $ip;
}

sub destroy {
    my $vm_name = shift;
    my $cmd = qq{/usr/bin/lxc-destroy -n $vm_name};
    my $r = Klol::Run->new( $cmd );
    return $r->success;
}

sub build_config_file {
    my ($params)        = @_;
    my $container_name  = $params->{container_name};
    my $lxc_config_path = $params->{lxc_config_path};
    my $config_template = $params->{config_template};
    my @config_lines;
    tie @config_lines, 'Tie::File', $lxc_config_path;
    @config_lines = split '\n', $config_template;
    my $new_hwaddr = generate_hwaddr();
    for my $line (@config_lines) {
        if ( $line =~ m|lxc\.network\.hwaddr\s*=\s*(.*)$| ) {
            my $hwaddr     = $1;
            $line =~ s|(lxc\.network\.hwaddr\s*=\s*)$hwaddr$|$1$new_hwaddr|;
        }
        elsif ( $line =~ m|lxc.utsname\s*=\s*(.*)$| ) {
            my $old_name = $1;
            $line =~ s|(lxc.utsname\s*=\s*)$old_name|$1$container_name|;
        }
        elsif ( $line =~ m|lxc\.rootfs\s*=\s*(.*)$| ) {
            my $old_path = $1;
            $line =~
              s|(lxc\.rootfs\s*=\s*)$old_path|$1/dev/lxc/$container_name|;
        }
    }
    untie @config_lines;

    return {
        hwaddr => $new_hwaddr
    }
}

sub generate_hwaddr {
    my @hwaddr;
    push @hwaddr, q{02};    # The first octet must contain an even number
    for ( 0 .. 4 ) {
        push @hwaddr, sprintf( "%02X", int( rand(255) ) );
    }
    return join ':', @hwaddr;
}

1;

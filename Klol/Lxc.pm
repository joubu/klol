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

sub stop {
    my $vm_name = shift;
    my $cmd = qq{/usr/bin/lxc-stop -n $vm_name};
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

__END__

=pod

=head1 NAME

Klol::Lxc - Lxc tools box

=head1 DESCRIPTION

This module provides some routines for Lxc management.

=head1 ROUTINES

=head2 check_config

    Lxc::check_config;

Check the if Lxc is willing to be used: Lxc is installed, Lxc version > 0.8, lxc-checkconfig.
Return 1 or arrayref containing errors.

=head2 is_vm

    Lxc::is_vm( 'container_name' );

Return 1 if the container exists else 0.

=head2 list_vms

    Lxc::list_vms;

Return a array containing a list of Lxc containers' name.

=head2 is_started

    Lxc::is_started( 'container_name' );

Return 1 if the container is currently running.

=head2 start

    Lxc::start( 'container_name' );

Start a container calling lxc-start.

=head2 stop

    Lxc::stop( 'container_name' );

Stop a container calling lxc-stop.

=head2 ip

    Lxc::ip( 'container_name' );

Return the LXC container's IP.

=head2 destroy

    Lxc::destroy( 'container_name' );

Destroy a container. Return 1 if it's done.
/!\ Destructive routine.

=head2 build_config_file

    Lxc::build_config_file((
        {
            container_name => 'container_name',
            lxc_config_path => '/var/lib/lxc/container_name/config',
            config_template => 'config contains',
        }
    );

Build the specific config file for a container.
This routine modifies 3 lines in the given config template:

=over 4

=item I<hwaddr>

Generate a random hardware address.

=item I<utsname>

Set the container's name to the given name.

=item I<rootfs>

Specify the rootfs directory (will be in /dev/lxc).

=back

Return a hashref with a hwaddr key containing the generated hardware address.

=head2 generate_hwaddr

    Lxc::generate_hwaddr;

Generate a valid hardware address.


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


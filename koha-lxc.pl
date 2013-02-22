#!/usr/bin/perl

use Modern::Perl;

use KLL::Config;
use KLL::LVM;
use KLL::Lxc;
use Getopt::Long;
use Pod::Usage;
use File::Spec;
use File::Path;
use File::Copy;
use Archive::Extract;
use Tie::File;
use Net::OpenSSH;
use Data::Dumper; # FIXME DELETEME

my ($help, $man, $verbose, $name, $orig_name, $snapshot);
GetOptions(
    'help|?'    => \$help,
    'man'       => \$man,
    'verbose|v' => \$verbose,
    'n:s'       => \$name,
    'o:s'       => \$orig_name,
    's'         => \$snapshot,
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -verbose => 2 ) if $man;

pod2usage(1) if @ARGV < 1;

my $action = $ARGV[0];

my $is_launched_as_root = (getpwuid $>) eq 'root';

check();

given ( $action ) {
    when ( /create/ ) {
        pod2usage({message => "must run as root"}) unless $is_launched_as_root;
        eval {
            create({
                name => $name,
                verbose => $verbose,
            });
        };
        if ($@) {
            clean();
            die $@;
        }
    }
    when ( /clone/ ) {
        pod2usage({message => "must run as root"}) unless $is_launched_as_root;
        clone({
            orig_name => $orig_name,
            name => $name,
            snapshot => $snapshot,
            verbose => $verbose,
        });
    }
    default {
        pod2usage({message => "This action ($action) is not known"}) unless $is_launched_as_root;
    }
}

# TODO
sub clean {

}

sub check {
    my $return;
    $return = KLL::Lxc::check_config;
    if ( ref($return) ) {
        die "LXC configuration is wrong:\n".join '\n', @$return;
    } elsif ( $return != 1 ) {
        die "LXC Configuration is wrong, check your lxc-checkconfig command, it returns something != 1";
    }

    $return = KLL::LVM::check_config;
}

sub pull_container {
    my ( $params ) = @_;
    my $host     = $params->{host};
    my $user     = $params->{user};
    my $pwd      = $params->{pwd};
    my $from     = $params->{from};
    my $to       = $params->{to};
    my $lxc_path = $params->{lxc_path};
    my $verbose  = $params->{verbose};
    warn "$user @ $host";
    my $ssh = Net::OpenSSH->new($user . ":$pwd".'@' . $host.':22');
    $ssh->scp_get({quiet => 0, verbose => 1, stderr_to_stdout => 1}, $from, $to) or die $ssh->error;

    my $lxc_rootfs_path = File::Spec->catfile(
        $lxc_path,
        q{rootfs}
    );
    my ( undef, undef, $pulled_filename ) = File::Spec->splitpath( $from );
    my $pulled_filepath = File::Spec->catfile( $to, $pulled_filename );

    print "Trying to make directories $lxc_rootfs_path..." if $verbose;
    mkpath $lxc_rootfs_path;
    say "ok" if $verbose;

    if ( -d $pulled_filepath ) {
        print "Trying to move the directory to the container..." if $verbose;
        move( $pulled_filepath, $lxc_rootfs_path )
            or die "I cannot move $pulled_filepath to $lxc_rootfs_path ($!)";
    } else {
        print "Trying to extract the archive to the container..." if $verbose;
        my $archive;
        eval {
            $archive = Archive::Extract->new( archive => $pulled_filepath );
        };
        die "The pulled file is not a directory and not a valid archive, I don't know what I have to do! ($@)" if $@;
        $archive->extract( to => $lxc_rootfs_path )
            or die "I cannot extract the archive ($pulled_filepath) to $lxc_rootfs_path ($archive->error)";
    }
}

sub build_config_file {
    my ( $params ) = @_;
    my $container_name  = $params->{container_name};
    my $lxc_config_path = $params->{lxc_config_path};
    my $config_template = $params->{config_template};
    my @config_lines;
    tie @config_lines, 'Tie::File', $lxc_config_path;
    @config_lines = split '\n', $config_template;
    for my $line ( @config_lines ) {
        if ( $line =~ m|lxc\.network\.hwaddr\s*=\s*(.*)$| ) {
            my $hwaddr = $1;
            my $new_hwaddr = generate_hwaddr();
            $line =~ s|(lxc\.network\.hwaddr\s*=\s*)$hwaddr$|$1$new_hwaddr|;
        } elsif ( $line =~ m|lxc.utsname\s*=\s*(.*)$| ) {
            my $old_name = $1;
            $line =~ s|(lxc.utsname\s*=\s*)$old_name|$1$container_name|;
        } elsif ( $line =~ m|lxc\.rootfs\s*=\s*/dev/lxc/(.*)$| ) {
            my $old_name = $1;
            $line =~ s|(lxc\.rootfs\s*=\s*/dev/lxc/)$old_name|$1$container_name|;
        }
    }
    untie @config_lines;

}

sub create {
    my ($params) = @_;
    my $name     = $params->{name};
    my $verbose  = $params->{verbose};
    my $config   = KLL::Config->new;
    my $tmp_path = q{/tmp};

    my $user = $config->{server}{login};
    my $host = $config->{server}{host};
    my $pwd  = $config->{server}{pwd};
    my $remote_path = $config->{server}{container_path};

    die "This vm ($name) already exists!"
        if KLL::Lxc::is_vm($name);

    my $lxc_path = File::Spec->catfile(
        $config->{lxc}{containers}{path},
        $name
    );
    my $lxc_config_path = File::Spec->catfile(
        $lxc_path,
        q{config}
    );

    print "Trying to pull the file ${user} @ ${host} : $remote_path to $tmp_path..."
        if $verbose;
    eval {
        pull_container( {
            user        => $user,
            host        => $host,
            pwd         => $pwd,
            from        => $remote_path,
            to          => $tmp_path,
            lxc_path    => $lxc_path,
            verbose     => $verbose,
        } );
    };
    die "Error pulling the file using scp: $@" if $@;
    say "ok" if $verbose;

    print "Trying to generate the container config file $lxc_config_path..." if $verbose;
    build_config_file({
        container_name  => $name,
        config_template => $config->{lxc}{containers}{config},
    });
    say "ok" if $verbose;


}

sub clone {
    die "clone is not implemented yet";
}

sub generate_hwaddr {
    my @hwaddr;
    for ( 0 .. 5 ) {
        push @hwaddr, sprintf("%02X", int(rand(255)));
    }
    return join '-', @hwaddr;
}


__END__

=head1 NAME

koha_lxc.pl - lxc tools for Koha

=head1 SYNOPSIS

perl koha_lxc.pl -h

=head1 DESCRIPTION

This script provides some actions for managing Koha installations in a lxc container.

=cut


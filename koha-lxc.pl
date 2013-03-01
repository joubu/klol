#!/usr/bin/perl

use Modern::Perl;

use Klol::Config;
use Klol::LVM;
use Klol::Lxc;
use Klol::Lxc::Templates;
use Getopt::Long;
use Pod::Usage;
use File::Spec;
use File::Path;
use File::Copy;
use Archive::Extract;
use Tie::File;
use Net::OpenSSH;
use Data::Dumper;    # FIXME DELETEME

my ( $help, $man, $verbose, $name, $orig_name, $snapshot, $template );
GetOptions(
    'help|?'    => \$help,
    'man'       => \$man,
    'verbose|v' => \$verbose,
    'n:s'       => \$name,
    'o:s'       => \$orig_name,
    's'         => \$snapshot,
    't:s'       => \$template,
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -verbose => 2 ) if $man;

pod2usage(1) if @ARGV < 1;

my $action = $ARGV[0];

my $is_launched_as_root = ( getpwuid $> ) eq 'root';

check( { action => $action } );

given ($action) {
    when (/create/) {
        eval {
            create(
                {
                    name     => $name,
                    verbose  => $verbose,
                    template => $template,
                }
            );
        };
        if ($@) {
            clean($name);
            die $@;
        }
    }
    when (/clone/) {
        clone(
            {
                orig_name  => $orig_name,
                name       => $name,
                snapshot   => $snapshot,
                verbose    => $verbose,
            }
        );
    }
    when (/destroy/) {
        clean( $name );
    }
    when (/list/) {
        print_list( $ARGV[1] );
    }
    default {
        pod2usage(
            {
                message => "This action ($action) is not known"
            }
        ) unless $is_launched_as_root;
    }
}

sub clean {
    my $name = shift;
    eval {
        Klol::Lxc::destroy( $name );
        Klol::LVM::lv_remove( $name )
            if Klol::LVM::is_lv( $name );
    };
}

sub print_list {
    my $entity = shift // "";
    given ( $entity ) {
        when (/templates/) {
            my $templates = Klol::Lxc::Templates->new;
            say $templates;
        }
        when ("") {
            my @containers = Klol::Lxc::list_vms;
            say "List of LXC containers:";
            say "\t$_" for @containers;
        }
        default {
            say "I don't know what I have to list";
        }
    }
}

sub check {
    my ($params) = @_;
    my $action = $params->{action};
    pod2usage( { message => "There is no action defined" } ) unless $action;

    pod2usage( { message => "Must run as root" } )
      if $action ~~ [qw/create clone/]
          and not $is_launched_as_root;

    return if $action ~~ [qw/list/];
    my $return;
    $return = Klol::Lxc::check_config;
    if ( ref($return) ) {
        die "LXC configuration is wrong:\n" . join '\n', @$return;
    }
    elsif ( $return != 1 ) {
        die "LXC Configuration is wrong, check your lxc-checkconfig command, it returns something != 1";
    }

    $return = Klol::LVM::check_config;
}

sub pull_container {
    my ($params) = @_;
    my $host     = $params->{host};
    my $user     = $params->{user};
    my $pwd      = $params->{pwd};    # FIXME : not used with rsync
    my $from     = $params->{from};
    my $to       = $params->{to};

    eval {

#my $ssh = Net::OpenSSH->new($user . ":$pwd".'@' . $host.':22');
#$ssh->scp_get({quiet => 1, recursive => 1, verbose => 0, stderr_to_stdout => 1}, $from, $to) or die $ssh->error;
        qx{rsync -avz -e ssh $user\@$host:$from $to};
    };
    die "I cannot pull the file $host:$from ($@)" if $@;
}

sub build_config_file {
    my ($params)        = @_;
    my $container_name  = $params->{container_name};
    my $lxc_config_path = $params->{lxc_config_path};
    my $config_template = $params->{config_template};
    my @config_lines;
    tie @config_lines, 'Tie::File', $lxc_config_path;
    @config_lines = split '\n', $config_template;
    for my $line (@config_lines) {

        if ( $line =~ m|lxc\.network\.hwaddr\s*=\s*(.*)$| ) {
            my $hwaddr     = $1;
            my $new_hwaddr = generate_hwaddr();
            $line =~ s|(lxc\.network\.hwaddr\s*=\s*)$hwaddr$|$1$new_hwaddr|;
        }
        elsif ( $line =~ m|lxc.utsname\s*=\s*(.*)$| ) {
            my $old_name = $1;
            $line =~ s|(lxc.utsname\s*=\s*)$old_name|$1$container_name|;
        }
        elsif ( $line =~ m|lxc\.rootfs\s*=\s*/dev/lxc/(.*)$| ) {
            my $old_name = $1;
            $line =~
              s|(lxc\.rootfs\s*=\s*/dev/lxc/)$old_name|$1$container_name|;
        }
    }
    untie @config_lines;

}

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

sub create {
    my ($params) = @_;
    my $name     = $params->{name};
    my $template = $params->{template};
    my $verbose  = $params->{verbose};
    my $config   = Klol::Config->new;
    my $tmp_path = q{/tmp};

    my $user        = $config->{server}{login};
    my $host        = $config->{server}{host};
    my $pwd         = $config->{server}{pwd};
    my $remote_path = $config->{server}{container_path};

    die "This vm ($name) already exists!"
      if Klol::Lxc::is_vm($name);

    die "This logical volume (/dev/lxc/$name) already exists!"
      if Klol::LVM::is_lv(qq{/dev/lxc/$name});

    my $lxc_path =
      File::Spec->catfile( $config->{lxc}{containers}{path}, $name );
    my $lxc_config_path = File::Spec->catfile( $lxc_path, q{config} );
    my $lxc_rootfs_path = File::Spec->catfile( $lxc_path, q{rootfs} );

    say "- Creating the Logical Volume /dev/lxc/$name..."
      if $verbose;
    my $size   = $config->{lvm}{size};
    my $fstype = $config->{lvm}{fstype};
    print "\t* Creating the logical volume $name(size=$size)..."
      if $verbose;
    Klol::LVM::lv_create(
        {
            name => $name,
            size => $size,
        }
    );
    say "OK" if $verbose;

    print "\t* Formatting the logical volume $name in $fstype..."
      if $verbose;
    Klol::LVM::lv_format(
        {
            name   => $name,
            fstype => $fstype,
        }
    );
    say "OK" if $verbose;

    print "\t* Making directories $lxc_rootfs_path..." if $verbose;
    mkpath $lxc_rootfs_path;
    say "OK" if $verbose;

    say "\t* Mounting the volume in $config->{lxc}{containers}{path}/$name/rootfs..."
      if $verbose;
    Klol::LVM::lv_mount(
        {
            name     => $name,
            fstype   => $fstype,
            lxc_root => $config->{lxc}{containers}{path},
        }
    );

    print "- Pulling the file ${user} @ ${host} : $remote_path to $tmp_path...\n"
      if $verbose;
    pull_container(
        {
            user => $user,
            host => $host,
            pwd  => $pwd,
            from => $remote_path,
            to   => $tmp_path,
        }
    );
    say "OK" if $verbose;

    my ( undef, undef, $pulled_filename ) = File::Spec->splitpath($remote_path);
    my $pulled_filepath = File::Spec->catfile( $tmp_path, $pulled_filename );

    if ( -d $pulled_filepath ) {
        print "- Moving the directory to the container..." if $verbose;
        move( $pulled_filepath, $lxc_rootfs_path )
          or die "I cannot move $pulled_filepath to $lxc_rootfs_path ($!)";
    }
    else {
        print "- Extracting the archive to the container to $lxc_rootfs_path..."
          if $verbose;
        extract_archive(
            {
                archive_path => $pulled_filepath,
                to           => $lxc_rootfs_path
            }
        );
    }
    say "OK" if $verbose;

    print "- Generating the container config file $lxc_config_path..."
      if $verbose;
    eval {
        build_config_file(
            {
                container_name  => $name,
                config_template => $config->{lxc}{containers}{config},
                lxc_config_path => $lxc_config_path,
            }
        );
    };
    die "I cannot generate the config file ($@)" if $@;
    say "OK" if $verbose;

}

sub clone {
    die "clone is not implemented yet";
}

sub generate_hwaddr {
    my @hwaddr;
    push @hwaddr, q{02};    # The first octet must contain an even number
    for ( 0 .. 4 ) {
        push @hwaddr, sprintf( "%02X", int( rand(255) ) );
    }
    return join ':', @hwaddr;
}

__END__

=head1 NAME

koha_lxc.pl - lxc tools for Koha

=head1 SYNOPSIS

perl koha_lxc.pl -h

=head1 DESCRIPTION

This script provides some actions for managing Koha installations in a lxc container.

=cut


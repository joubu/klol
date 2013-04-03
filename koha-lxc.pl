#!/usr/bin/perl

use Modern::Perl;

use Klol::Config;
use Klol::File;
use Klol::LVM;
use Klol::Lxc;
use Klol::Lxc::Config;
use Klol::Lxc::Templates;
use Getopt::Long;
use Pod::Usage;
use File::Spec;
use File::Path;
use File::Copy qw{ move };
use File::Slurp qw{ read_file };
use File::Basename qw{ basename };
use Data::Dumper;    # FIXME DELETEME

my ( $help, $man, $verbose, $name, $orig_name, $snapshot, $template_name );
GetOptions(
    'help|?'    => \$help,
    'man'       => \$man,
    'verbose|v' => \$verbose,
    'n:s'       => \$name,
    'o:s'       => \$orig_name,
    's'         => \$snapshot,
    't:s'       => \$template_name,
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -verbose => 2 ) if $man;

pod2usage(1) if @ARGV < 1;

my $action = $ARGV[0];

my $is_launched_as_root = ( getpwuid $> ) eq 'root';

check( { action => $action, name => $name } );

given ($action) {
    when (/create/) {
        eval {
            create(
                {
                    name     => $name,
                    verbose  => $verbose,
                }
            );
        };
        if ($@) {
            say "CALL CLEAN";
            my $error = $@;
            clean($name);
            die $error;
        }
        exit 0 unless $template_name;
        eval {
            apply_template(
                {
                    name => $name,
                    verbose => $verbose,
                    template_name => $template_name,
                }
            );
        };
        if ($@) {
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
        $| = 1;
        print "Are you sure you want to delete the container $name? (y/N)";
        chomp( $_ = <STDIN> );
        exit unless (/^y/i);
        clean( $name, 1 );
    }
    when (/list/) {
        print_list( $ARGV[1] );
    }
    when (/apply/) {
        pod2usage(
            {
                message => "No template to apply, specify a -t option"
            }
        ) unless $template_name;
        apply_template(
            {
                name => $name,
                verbose => $verbose,
                template_name => $template_name,
            }
        )
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
    my ($name, $verbose) = @_;
    my @err;
    eval{
        Klol::LVM::lv_umount( {name => $name} );
    };
    push @err, $@ if $@;
    eval {
        Klol::Lxc::destroy( $name );
    };
    push @err, $@ if $@;
    eval {
        Klol::LVM::lv_remove( {name => $name} )
            if Klol::LVM::is_lv( {name => $name} );
    };
    push @err, $@ if $@;
    eval {
        Klol::Lxc::Config::remove_host( { name => $name } );
    };
    die @err if @err and $verbose;
}

sub print_list {
    my $entity = shift // "all";
    if ( $entity =~ /templates|all/ ) {
        say "\nList of available templates:";
        my $templates = Klol::Lxc::Templates->new;
        say $templates;
    }
    if ( $entity =~ /lxc|containers|all/ ) {
        my @containers = Klol::Lxc::list_vms;
        say "\nList of LXC containers:";
        say "\t$_" for @containers;
    }
}

sub check {
    my ($params) = @_;
    my $action = $params->{action};
    my $name = $params->{name};

    pod2usage( { message => "There is no action defined" } ) unless $action;

    return unless defined $action
        and $action ~~ [qw/create clone destroy apply/];

    pod2usage( { message => "Must run as root" } )
          unless $is_launched_as_root;

    die "The container name is not defined"
        unless $name;

    die "The container name cannot contain underscore (_), prefer dash (-)"
        if $name =~ m/_/;

    my $return = Klol::Lxc::check_config;
    if ( ref($return) ) {
        die "LXC configuration is wrong:\n" . join '\n', @$return;
    }
    elsif ( $return != 1 ) {
        die "LXC Configuration is wrong, check your lxc-checkconfig command, it returns something != 1";
    }

    $return = Klol::LVM::check_config;
}



sub apply_template {
    my ($params) = @_;
    my $name = $params->{name};
    my $template_name = $params->{template_name};
    my $verbose = $params->{verbose};

    die "The Lxc container $name does not exist"
        unless Klol::Lxc::is_vm( $name );
    my $templates = Klol::Lxc::Templates->new;
    my $template = $templates->get_template($template_name);

    die "The template '$template_name' is not know, please use 'list templates'"
        unless $template;

    unless ( Klol::Lxc::is_started( $name ) ) {
        say "The container is stopped, I will start it..." if $verbose;
        Klol::Lxc::start( $name );
        sleep(3);
    }

    my $ip = Klol::Lxc::ip( $name );
    for my $i ( 1 .. 10 ) {
        last if $ip;
        sleep(1);
        $ip = Klol::Lxc::ip( $name );
    }
    die "I cannot get the ip for $name"
        unless $ip;

    my $from = File::Spec->catfile( $template->{root_path}, $template->{filename} );
    print "Pulling the sql file from $template->{login}\@$template->{host}:$from "
        if $verbose;
    my $bdd_filepath = Klol::File::pull(
        {
            host => $template->{host},
            user => $template->{login},
            identity_file => $template->{identity_file},
            from => $from,
            verbose => $verbose,
        }
    );
    say "OK" if $verbose;

    my $config = Klol::Config->new;
    my $identity_file = $config->{lxc}{containers}{identity_file};

    Klol::File::push(
        {
            from => $bdd_filepath,
            host => $ip,
            login => 'koha',
            identity_file => $identity_file,
            to => '/tmp',
        }
    );
    my $bdd_filename = basename $bdd_filepath;
    Klol::Run->new(
        qq{ssh koha\@$ip -i $identity_file '/usr/bin/mysql < /tmp/$bdd_filename'}
    );

}

sub pidof {
    my $process_name = shift;
    my $r = eval { Klol::Run->new(qq{/bin/pidof $process_name}) }
        or die "I cannot get pid of $process_name, please check that it is running";
    my $pid = $r->stdout;
    die "Several process named $process_name are running, I cannot continue (pids=$pid)"
        if $pid =~ /\D/;
    return $pid;
}

sub create {
    my ($params) = @_;
    my $name     = $params->{name};
    my $template = $params->{template};
    my $verbose  = $params->{verbose};
    my $config   = Klol::Config->new;
    my $tmp_path = $config->{path}{tmp};

    my $user        = $config->{server}{login};
    my $host        = $config->{server}{host};
    my $identity_file = $config->{server}{identity_file};
    my $remote_path = $config->{server}{container_path};

    if ( Klol::Lxc::is_vm($name) ) {
        say "This vm ($name) already exists!";
        exit 1;
    }

    if ( Klol::LVM::is_lv({name => qq{$name}}) ) {
        say "This logical volume (/dev/lxc/$name) already exists!";
        exit 1;
    }

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

    print "\t* Mounting the volume in $config->{lxc}{containers}{path}/$name/rootfs..."
      if $verbose;
    Klol::LVM::lv_mount(
        {
            name     => $name,
            fstype   => $fstype,
            lxc_root => $config->{lxc}{containers}{path},
        }
    );
    say "OK" if $verbose;

    print "- Pulling the file ${user} @ ${host} : $remote_path to $tmp_path...\n"
      if $verbose;
    my $pulled_filepath = Klol::File::pull(
        {
            user => $user,
            host => $host,
            identity_file => $identity_file,
            from => $remote_path,
            to   => $tmp_path,
            verbose => $verbose,
        }
    );
    say "OK" if $verbose;

    if ( -d $pulled_filepath ) {
        print "- Moving the directory to the container..." if $verbose;
        Klol::Run->new( qq{mv --no-clobber $pulled_filepath/\* $lxc_rootfs_path} );
    }
    else {
        print "- Extracting the archive to the container ($lxc_rootfs_path)..."
          if $verbose;
        Klol::File::extract_archive(
            {
                archive_path => $pulled_filepath,
                to           => $lxc_rootfs_path
            }
        );
    }
    say "OK" if $verbose;

    print "- Generating the config file for the container into lxc_config_path..."
      if $verbose;
    my $hwaddr = eval {
        my $r = Klol::Lxc::build_config_file(
            {
                container_name  => $name,
                config_template => $config->{lxc}{containers}{config},
                lxc_config_path => $lxc_config_path,
            }
        );
        $r->{hwaddr};
    };
    die "I cannot generate the config file ($@)" if $@;
    say "OK" if $verbose;

    print "- Adding the eth0 interface as dhcp IPv4..."
        if $verbose;
    Klol::Lxc::Config::add_interfaces(
        {
            name => $name,
            interface => q{eth0}
        }
    );
    say "OK" if $verbose;

    print "- Updating the hostname file in the container..."
        if $verbose;
    Klol::Lxc::Config::update_hostname(
        {
            name => $name
        }
    );
    say "OK" if $verbose;

    print "- Adding the public key to the authorized keys..."
        if $verbose;
    Klol::Lxc::Config::add_ssh_pubkey(
        {
            name => $name,
            identity_file => $config->{lxc}{containers}{identity_file},
        }
    );
    say "OK" if $verbose;

    print "- Adding this new host to the dnsmasq configuration file..."
        if $verbose;
    my $ip = eval {
        Klol::Lxc::Config::add_host(
            {
                name => $name,
                hwaddr => $hwaddr
            }
        );
    };
    die "I cannot adding this host to dnsmasq ($@)" if $@;
    say "OK" if $verbose;

    print "- Reloading dnsmasq configuration..."
        if $verbose;
    my $pid = pidof( "dnsmasq" );
    Klol::Run->new(qq{/bin/kill -1 $pid});
    say "OK" if $verbose;

    say "+=============================================================+";
    say " To complete, add the following line to your /etc/hosts file ";
    say " $ip catalogue.$name.local                                   ";
    say " $ip pro.$name.local                                         ";
    say "+=============================================================+";

}

sub clone {
    die "clone is not implemented yet";
}



__END__

=head1 NAME

koha_lxc.pl - lxc tools for Koha

=head1 SYNOPSIS

perl koha_lxc.pl [-h|--help|--man] action options [-v]

=head1 DESCRIPTION

This script provides some actions for managing Koha installations in a lxc container.

Its allows to create a lxc container containing all Koha stuffs on LVM with a simple command line.

=head2 Config

    The config file (etc/config.yaml) is where you configure all this tools box.
    The following shortly describes the different entries:

=head3 server

    Contains connection information to the remove server where are the rootfs for the default container.
    The rootfs can be a directory or an archive (a lot of format supported).
    This archive should be created e.g.
        /var/lib/lxc/koha/rootfs $ tar cvf ../rootfs.tar .
    If no ssh identity file is given, the password will be request.

=head3 lxc

    Contains all information about your lxc configuration.

    The dnmasq_config_file entry should be your... dnsmaq config file. It will be filled with lines formatted like:
        hwaddr,container_name,ip
    containers::path is the path where lxc manage yours containers (default is /var/lib/lxc).
    containers::identity_file is the ssh public key used to connect to yours containers.
    containers::config is the config file (/var/lib/lxc/NAME/config) used for each container.
        lxc.network.hwaddr, lxc.utsname and lxc.rootfs are automatically replaced on creation.

=head3 template

    Contains all information about your templates.

    server contains connection information to your templates server. root_path is the directory where templates are stored. If no ssh identity file is given, the password will be request.
    availables: list of all available templates. filename contains the filename of the database file (relative to server::root_path). searchengine is the search engine to enable on this container (could be Solr or Zebra).

=head3 lvm

    Size and fs type for logical volumes.

=head3 path

    tmp: absolute path to a temporary directory (change it if you encounter a space problem)

=head1 Parameters

=head2 Actions

=head3 create

    koha-lxc.pl create -n koha [-t template_name]

    Create a new lxc container named koha with the template template_name.
    If no template is given, the database will be the default one.

=head3 clone

    koha-lxc.pl clone -n new_koha -o koha [-s]

    Same as the lxc command. Clone a container from another one.
    Only make a snapshot if the -s flag is given.

=head3 destroy

    koha-lxc.pl destroy -n koha

    Destructive action! It destroys your lxc container named koha and your logical volume named koha (in the lxc volume group).

=head3 list

    koha-lxc.pl list [what]

    what can be "templates", "containers" or "all".
    List all available templates and/or all lxc containers present on the system.

=head3 apply

    koha-lxc.pl apply -n koha -t template_name

    Apply a template on a lxc container named koha

=head2 Others options

=head3 h|help|man

    Display the help

=head3 verbose|v

    Verbose mode

=cut

package Klol;

use Modern::Perl;

use Klol::Config;
use Klol::File;
use Klol::LVM;
use Klol::Lxc;
use Klol::Lxc::Config;
use Klol::Lxc::Templates;
use Klol::Process;

use File::Spec;
use File::Path;
use File::Copy qw{ move };
use File::Slurp qw{ read_file };
use File::Basename qw{ basename };

sub clean {
    my ($name, $verbose) = @_;
    die "I cannot destroy $name, it is currently running"
        if Klol::Lxc::is_started( $name );
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
    my $is_launched_as_root = $params->{is_launched_as_root};

    pod2usage( { message => "There is no action defined" } ) unless $action;

    return unless defined $action
        and $action ~~ [qw/create clone destroy apply start stop/];

    pod2usage( { message => "Must run as root" } )
          unless $is_launched_as_root;

    die "The container name is not defined"
        unless $name;

    die "The container name cannot contain underscore (_), prefer dash (-)"
        if $name =~ m/_/
            and $action ~~ [qw/create clone/];

    die "This container does not exist"
        if not Klol::Lxc::is_vm( $name )
            and $action ~~ [qw/apply start stop/];

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
    eval {
        Klol::Lxc::Config::add_host(
            {
                name => $name,
                hwaddr => $hwaddr
            }
        );
    };
    die "I cannot add this host to dnsmasq ($@)" if $@;
    say "OK" if $verbose;

    print "- Reloading dnsmasq configuration..."
        if $verbose;
    my $pid = Klol::Process::pidof( 'dnsmasq', 'dhcp-hostsfile' );
    Klol::Run->new(qq{/bin/kill -1 $pid});
    say "OK" if $verbose;
}

sub clone {
    die "clone is not implemented yet";
}

sub start {
    my ( $params ) = @_;
    my $name = $params->{name};
    Klol::Lxc::start( $name );
}

sub stop {
    my ( $params ) = @_;
    my $name = $params->{name};
    Klol::Lxc::stop( $name );
}

1;

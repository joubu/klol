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
#use Net::OpenSSH;
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

check( { action => $action } );

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
            warn Data::Dumper::Dumper $@;
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
        clean( $name );
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
    my $name = shift;
    eval {
        Klol::LVM::lv_umount( {name => $name} );
        Klol::Lxc::destroy( $name );
        Klol::LVM::lv_remove( {name => $name} )
            if Klol::LVM::is_lv( {name => $name} );
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

    return unless defined $action
        and $action ~~ [qw/create clone/];

    pod2usage( { message => "Must run as root" } )
          unless $is_launched_as_root;

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

sub pull_file {
    my ($params) = @_;
    my $host     = $params->{host};
    my $user     = $params->{user};
    my $pwd      = $params->{pwd};    # FIXME : not used with rsync, only ssh key
    my $identity_file = $params->{identity_file};
    my $from     = $params->{from};
    my $to       = $params->{to};

    unless ( $to ) {
        my $config   = Klol::Config->new;
        $to = $config->{path}{tmp};
    }
    eval {

#my $ssh = Net::OpenSSH->new($user . ":$pwd".'@' . $host.':22');
#$ssh->scp_get({quiet => 1, recursive => 1, verbose => 0, stderr_to_stdout => 1}, $from, $to) or die $ssh->error;
        # Don't use scp here, it follows link, what we don't want!
        my $cmd = q{rsync -avz -e "ssh} . ( $identity_file ? qq{ -i $identity_file} : q{} ) . qq{" $user\@$host:$from $to};
        warn $cmd;
        qx{$cmd};
    };
    die "I cannot pull the file $host:$from ($@)" if $@;

    my ( undef, undef, $pulled_filename ) = File::Spec->splitpath($from);
    my $abs_path = File::Spec->catfile( $to, $pulled_filename );
    return $abs_path if -e $abs_path;
    die "The file is pulled but I cannot find it in $abs_path";
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
        sleep(10);
    }
    my $ip = Klol::Lxc::ip( $name );
    die "I cannot get the ip for $ip"
        unless $ip;

    my $from = File::Spec->catfile( $template->{root_path}, $template->{filename} );
    say "Pulling the sql file from $template->{login}\@$template->{host}:$from"
        if $verbose;
    my $bdd_filepath = pull_file(
        {
            host => $template->{host},
            user => $template->{login},
            identity_file => $template->{identity_file},
            from => $from,
        }
    );
    say "OK" if $verbose;

    my $config = Klol::Config->new;
    my $identity_file = $config->{lxc}{containers}{identity_file};

    my $cmd = q{rsync -avz -e "ssh} . ( $identity_file ? qq{ -i $identity_file} : q{} ) . qq{" $bdd_filepath koha\@$ip:/tmp};
    qx{$cmd};
    my $bdd_filename = qx{basename $bdd_filepath};
    chomp $bdd_filename;
    say qq{ssh koha\@$ip -i $identity_file '/usr/bin/mysql < /tmp/$bdd_filename'};
    qx{ssh koha\@$ip -i $identity_file '/usr/bin/mysql < /tmp/$bdd_filename'};

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
    my $tmp_path = $config->{path}{tmp};

    my $user        = $config->{server}{login};
    my $host        = $config->{server}{host};
    my $pwd         = $config->{server}{pwd};
    my $identity_file = $config->{server}{identity_file};
    my $remote_path = $config->{server}{container_path};

    die "This vm ($name) already exists!"
      if Klol::Lxc::is_vm($name);

    die "This logical volume (/dev/lxc/$name) already exists!"
      if Klol::LVM::is_lv({name => qq{$name}});

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
    my $pulled_filepath = pull_file(
        {
            user => $user,
            host => $host,
            identity_file => $identity_file,
            from => $remote_path,
            to   => $tmp_path,
        }
    );
    say "OK" if $verbose;

    if ( -d $pulled_filepath ) {
        print "- Moving the directory to the container..." if $verbose;
        move( $pulled_filepath, $lxc_rootfs_path )
          or die "I cannot move $pulled_filepath to $lxc_rootfs_path ($!)";
    }
    else {
        print "- Extracting the archive to the container ($lxc_rootfs_path)..."
          if $verbose;
        extract_archive(
            {
                archive_path => $pulled_filepath,
                to           => $lxc_rootfs_path
            }
        );
    }
    say "OK" if $verbose;

    print "- Generating the config file for the container into lxc_config_path..."
      if $verbose;
    eval {
        Klol::Lxc::build_config_file(
            {
                container_name  => $name,
                config_template => $config->{lxc}{containers}{config},
                lxc_config_path => $lxc_config_path,
            }
        );
    };
    die "I cannot generate the config file ($@)" if $@;
    say "OK" if $verbose;

    # TODO Add an ip into /etc/dnsmasq.d/lxc_dhcp_reservations and restart dnsmasq or kill + launch the same command
}

sub clone {
    die "clone is not implemented yet";
}



__END__

=head1 NAME

koha_lxc.pl - lxc tools for Koha

=head1 SYNOPSIS

perl koha_lxc.pl -h

=head1 DESCRIPTION

This script provides some actions for managing Koha installations in a lxc container.

=cut


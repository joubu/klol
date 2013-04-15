#!/usr/bin/perl

use Modern::Perl;

use Getopt::Long;
use Pod::Usage;

use lib 'lib';

use Klol;

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

Klol::check( {
    action => $action,
    name => $name,
    is_launched_as_root => $is_launched_as_root,
} );

given ($action) {
    when (/create/) {
        eval {
            Klol::create(
                {
                    name     => $name,
                    verbose  => $verbose,
                }
            );
        };
        if ($@) {
            say "CALL CLEAN";
            my $error = $@;
            Klol::clean($name);
            die $error;
        }
        exit 0 unless $template_name;
        eval {
            Klol::apply_template(
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
        Klol::clone(
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
        Klol::clean( $name, 1 );
    }
    when (/list/) {
        Klol::print_list( $ARGV[1] );
    }
    when (/start/) {
        Klol::start( { name => $name } )
    }
    when (/stop/) {
        Klol::stop( { name => $name } )
    }
    when (/apply/) {
        pod2usage(
            {
                message => "No template to apply, specify a -t option"
            }
        ) unless $template_name;
        Klol::apply_template(
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
    The rootfs can be a directory or an archive (only .tar.gz supported).
    This archive should be created e.g.
        /var/lib/lxc/koha/rootfs $ tar cxvf ../rootfs.tar.gz .
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

=head1 OPTIONS

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


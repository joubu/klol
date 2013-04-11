package Klol::Process;

use Modern::Perl;
use File::Slurp qw{ read_file };
use Klol::Run;

sub pidof {
    my ( $process_name, @args ) = @_;
    my $args_string;
    $args_string = qq{ | grep '$_'} for @args;

    my $r = eval { Klol::Run->new(
            qq{/bin/ps -ef | grep '$process_name' $args_string | grep -v grep | cut -c9-14 | sort | uniq}
    ) }
        or die "I cannot get pid of $process_name, please check that it is running";
    my $pid = $r->stdout;
    $pid =~ s/^\s*//;
    die "Several process named $process_name are running, I cannot continue (pids=$pid)"
        if $pid =~ /\D/;
    return $pid;
}

sub cmdline {
    my ( $process_name, @args ) = @_;
    my $pid = pidof( $process_name, @args );
    my $cmdline = read_file( qq{/proc/$pid/cmdline} );
    return $cmdline;
}

1;

__END__

=pod

=head1 NAME

Klol::Process - Toolbox for processes

=head1 DESCRIPTION

This module contains utils for processes

=head1 ROUTINES

=head2 pidof

    my $pid = Process::pidof( $process_name );

Return the pid for a given process name.
Raise an error if several processes are running with this name.

=head2 cmdline

    my $cmdline = Process::cmdline( $process_name );

Return the command line for a given process name.
Raise an error if several processes are running with this name.

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


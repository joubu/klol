package Klol::Run;

use Modern::Perl;
use IPC::Cmd qw[run];
sub new {
    my ( $class, $cmd, $opts ) = @_;

    my $dont_die = $opts->{no_die};
    my $verbose = $opts->{verbose} || 0;

    my ( $success, $error, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => $verbose );

    my $self = {
        success => $success,
        error => $error,
        full => $full_buf,
        stdout => $stdout_buf,
        stderr => $stderr_buf
    };

    bless ( $self, $class );

    unless ( $success or $dont_die) {
        my $msg = qq{\nThe command "$cmd" fails with the following error: $error};
        $msg .= qq{\nThe error message is: \n\t} . $self->stderr;
            $self->stderr;
        die $msg
    }

    return $self;
}

sub success {
    my $self = shift or return;
    return $self->{success};
}

sub error {
    my $self = shift or return;
    return $self->{error};
}

sub full {
    my $self = shift or return;
    return wantarray
        ? ref( $self->{full} ) eq 'ARRAY'
            ? map { split ('\n', $_) } @{$self->{full}}
            : join ('\n', map {chomp $_; $_} @{$self->{full}})
        : join ('\n', map {chomp $_; $_} @{$self->{full}})
}

sub stdout {
    my $self = shift or return;
    return wantarray
        ? ref( $self->{stdout} ) eq 'ARRAY'
            ? map { split ('\n', $_) } @{$self->{stdout}}
            : join ('\n', map {chomp $_; $_} @{$self->{stdout}})
        : join ('\n', map {chomp $_; $_} @{$self->{stdout}})
}

sub stderr {
    my $self = shift or return;
    return wantarray
        ? ref( $self->{stderr} ) eq 'ARRAY'
            ? map { split ('\n', $_) } @{$self->{stderr}}
            : join ('\n', map {chomp $_; $_} @{$self->{stderr}})
        : join ('\n', map {chomp $_; $_} @{$self->{stderr}})
}

1;

__END__

=pod

=head1 NAME

Klol::Run - Run system commands

=head1 DESCRIPTION

Run system commands using IPC::Cmd.
It formats and manage error like I want.

=head1 METHODS

=head2 new

    my $run = Run->new(
        $cmd
        {
            no_die => 0,
            verbose => 0,
        }
    );

Construct a new object and launch the system command given in parameter.
If an error occured, an error message is raised unless no_die is given.
The verbose_mode allows to run the command and #TRAD gerber# the output.

=head2 success

    my $success = $run->success;

Return the success value returned by the command.

=head2 error

    my $error_code = $run->error;

Return the error code returned by the command.

=head full

    my @full = $run->full;
    my $full = $run->full;

Return an array or a string of the full buffer returned by the command.

=head stdout

    my @stdout = $run->stdout;
    my $stdout = $run->stdout;

Return an array or a string of the stdout buffer returned by the command.

=head stderr

    my @stderr = $run->stderr;
    my $stderr = $run->stderr;

Return an array or a string of the stderr buffer returned by the command.

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


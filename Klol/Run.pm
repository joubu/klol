package Klol::Run;

use Modern::Perl;
use IPC::Cmd qw[run];
sub new {
    my ( $class, $cmd ) = @_;

    my ( $success, $error, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => 0 );
    die "The $cmd command fails with the following error: $error"
        unless $success;

    my $self = {
        success => $success,
        error => $error,
        full => $full_buf,
        stdout => $stdout_buf,
        stderr => $stderr_buf
    };

    bless ( $self, $class );
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
            ? map {chomp $_; $_} @{$self->{full}}
            : join ('\n', map {chomp $_; $_} @{$self->{full}})
        : join ('\n', map {chomp $_; $_} @{$self->{full}})
}

sub stdout {
    my $self = shift or return;
    return wantarray
        ? ref( $self->{stdout} ) eq 'ARRAY'
            ? map {chomp $_; $_} @{$self->{stdout}}
            : join ('\n', map {chomp $_; $_} @{$self->{stdout}})
        : join ('\n', map {chomp $_; $_} @{$self->{stdout}})
}

sub stderr {
    my $self = shift or return;
    return wantarray
        ? ref( $self->{stderr} ) eq 'ARRAY'
            ? map {chomp $_; $_} @{$self->{stderr}}
            : join ('\n', map {chomp $_; $_} @{$self->{stderr}})
        : join ('\n', map {chomp $_; $_} @{$self->{stderr}})
}

1;

package Klol::Lxc;

use Modern::Perl;
use IPC::Cmd qw[run];

sub check_config {

    unless ( -f q{/usr/bin/lxc-version} ) {
        die "The lxc binary file lxc-version is missing, is lxc installed?"
    }

    my $cmd = q{/usr/bin/lxc-version};
    my ( $success, $error_code, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => 0 );
    return ["your lxc-version does not return success"]
        unless $success;
    if ( @$stdout_buf and @$stdout_buf[0] =~ 'lxc version: (\d+\.\d+).*\s*' ) {
        my $version = $1;
        chomp $version;
        if ( $version < '0.8' ) {
            die "Your lxc version is too old";
        }
    }

    $cmd = q{/usr/bin/lxc-checkconfig};
    ( $success, $error_code, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => 0 );
    my @errors;
    for my $line ( @$full_buf ) {
        chomp $line;
        push @errors, $line 
            if $line =~ /missing/
                or $line =~ /required/;
    }

    return @errors ? \@errors : $success;
}

sub is_vm {
    my $vm_name = shift;
    return 1 if grep {$_ eq $vm_name} list_vms();
    return 0;
}

sub list_vms {
    my $cmd = q{/usr/bin/lxc-ls};
    my ( $success, $error, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => 0 );
    die "The lxc-ls command fails with the following error: $error"
        unless $success;

    my @vms;
    for my $line ( @$stdout_buf ) {
        $line =~ s|^\s*(.*)\s*$|$1|;
        push @vms, $line;
    }
    return @vms;
}

sub destroy {
    my $vm_name = shift;
    my $cmd = qq{/usr/bin/lxc-destroy -n $vm_name};
    my ( $success, $error, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => 0 );
    die "The lxc-destroy command fails with the following error: $error"
        unless $success;
}

1;

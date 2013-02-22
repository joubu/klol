package KLL::LVM;

use Modern::Perl;
use IPC::Cmd qw(can_run run);

sub check_config {
    for my $binfile ( qw(/sbin/vgdisplay /sbin/lvdisplay /sbin/lvs /sbin/pvdisplay ) ) {
        unless ( -f $binfile ) {
            die "The LVM binary file $binfile is missing, is LVM2 installed?"
        }
    }
    unless ( is_vg('lxc') ) {
        die "The Volume Group 'lxc' does not exist!";
    }
}

sub is_vg {
    my $vg_name = shift;
    my $vgs = list_vgs($vg_name);
    return $vgs->{$vg_name};
}

sub list_vgs {
    my $vg_name = shift;
    my $cmd = qq{/sbin/vgdisplay -c $vg_name};
    my ( $success, $error, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => 0 );
    unless ( $success ) {
        return if @$full_buf and @$full_buf[0] =~ q{Volume group .* not found};
        die "The vgdisplay command fails with the following error: $error";
    }
    my %vgs;
    for my $line ( @$full_buf ) {
        $line =~ s|^\s*(.*)\s*$|$1|;
        next unless $line;
        my %vg;
        @vg{qw(
            name access status vgid maxlvs curlvs openlvs maxlvsize maxpvs
            curpvs numpvs vgsize pesize totalpe allocpe freepe uuid)}
            = split( /:/, $line );
        $vgs{$vg{name}} = \%vg;
    }
    return \%vgs;
}

1;

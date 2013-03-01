package Klol::LVM;

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

sub is_lv {
    my $lv_name = shift;
    my $lvs = list_lvs($lv_name);
    return $lvs->{$lv_name};
}

sub list_lvs {
    my $lv_name = shift;
    my $cmd = qq{/sbin/lvdisplay -c $lv_name};
    my ( $success, $error, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => 0 );
    unless ( $success ) {
        return if @$full_buf and @$full_buf[0] =~ q{One or more specified logical volume\(s\) not found};
        die "The lvdisplay command fails with the following error: $error";
    }
    my %lvs;
    for my $line ( @$full_buf ) {
        $line =~ s|^\s*(.*)\s*$|$1|;
        next unless $line;
        my %lv;
        @lv{qw(
            name vg_name access status lvnum open_count lv_size cur_logic_extend_assoc
            alloc_logic_extend alloc_pol r_a_sect maj_dev_num min_dev_num
        )} = split( /:/, $line );
        $lvs{$lv{name}} = \%lv;
    }
    return \%lvs;
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
            curpvs numpvs vgsize pesize totalpe allocpe freepe uuid
        )} = split( /:/, $line );
        $vgs{$vg{name}} = \%vg;
    }
    return \%vgs;
}

sub lv_create {
    my $params = shift;
    my $name = $params->{name};
    my $size = $params->{size};
    return unless $name or $size;
    my $cmd = qq{/sbin/lvcreate -L $size -n $name lxc};
    my ( $success, $error, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => 0 );
    return $success if $success;
    die join ('\n', map { chomp; $_} @$stderr_buf);
}

sub lv_format {
    my $params = shift;
    my $name = $params->{name};
    my $fstype = $params->{fstype};
    return unless $name or $fstype;
    my $cmd = qq{/sbin/mkfs -t $fstype /dev/lxc/$name};
    my ( $success, $error, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => 0 );
    return $success if $success;
    die join ('\n', map { chomp; $_} @$stderr_buf);
}

sub lv_mount {
    my $params = shift;
    my $name = $params->{name};
    my $fstype = $params->{fstype};
    my $lxc_root = $params->{lxc_root} || q{/var/lib/lxc};
    return unless $name or $fstype;
    my $cmd = qq{/bin/mount -t $fstype /dev/lxc/$name $lxc_root/$name/rootfs};
    my ( $success, $error, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => 0 );
    return $success if $success;
    die join ('\n', map { chomp; $_} @$stderr_buf);
}

sub lv_remove {
    my $name = shift;
    my $cmd = qq{/sbin/lv-remove /dev/lxc/$name};
    my ( $success, $error, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $cmd, verbose => 0 );
    die "The lxc-destroy command fails with the following error: $error"
        unless $success;
}

1;

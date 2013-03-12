package Klol::LVM;

use Klol::Run;

use Modern::Perl;

sub check_config {
    for my $binfile ( qw(/sbin/vgdisplay /sbin/lvdisplay /sbin/lvs /sbin/pvdisplay ) ) {
        unless ( -f $binfile ) {
            die "The LVM binary file $binfile is missing, is LVM2 installed?"
        }
    }
    unless ( is_vg({ name => q{lxc} }) ) {
        die "The Volume Group 'lxc' does not exist!";
    }
}

sub is_lv {
    my $params = shift;
    my $lv_name = $params->{name};
    my $lvs = list_lvs($lv_name);
    return $lvs->{"/dev/lxc/$lv_name"};
}

sub list_lvs {
    my $lv_name = shift;
    my $cmd = qq{/sbin/lvdisplay -c /dev/lxc/$lv_name};
    my $r = Klol::Run->new( $cmd );

    my @full = $r->full;
    unless ( $r->success ) {
        return if @full and $full[0] =~ q{One or more specified logical volume\(s\) not found};
        return {} if @full and $full[0] =~ qq{Volume group "$lv_name" not found};
        die "The lvdisplay command fails with the following error: $r->error";
    }
    my %lvs;
    for my $line ( @full ) {
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
    my $params = shift;
    my $vg_name = $params->{name};
    my $vgs = list_vgs($vg_name);
    return $vgs->{$vg_name};
}

sub list_vgs {
    my $vg_name = shift;
    my $cmd = qq{/sbin/vgdisplay -c $vg_name};
    my $r = Klol::Run->new( $cmd );
    my @full = $r->full;
    unless ( $r->success ) {
        return if @full and $full[0] =~ q{Volume group .* not found};
        die "The vgdisplay command fails with the following error: $r->error";
    }
    my %vgs;
    for my $line ( @full ) {
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
    my $r = Klol::Run->new( $cmd );
    return $r->success if $r->success;
    die $r->stderr;
}

sub lv_format {
    my $params = shift;
    my $name = $params->{name};
    my $fstype = $params->{fstype};
    return unless $name or $fstype;
    my $cmd = qq{/sbin/mkfs -t $fstype /dev/lxc/$name};
    my $r = Klol::Run->new( $cmd );
    return $r->success if $r->success;
    die $r->stderr;
}

sub lv_mount {
    my $params = shift;
    my $name = $params->{name};
    my $fstype = $params->{fstype};
    my $lxc_root = $params->{lxc_root} || q{/var/lib/lxc};
    return unless $name or $fstype;
    my $cmd = qq{/bin/mount -t $fstype /dev/lxc/$name $lxc_root/$name/rootfs};
    my $r = Klol::Run->new( $cmd );
    return $r->success if $r->success;
    die $r->stderr;
}

sub lv_umount {
    my $params = shift;
    my $name = $params->{name};
    my $lxc_root = $params->{lxc_root} || q{/var/lib/lxc};
    return unless $name;
    my $cmd = qq{/bin/umount /dev/lxc/$name};
    my $r = Klol::Run->new( $cmd );
    return $r->success if $r->success;
    die $r->stderr;
}

sub lv_remove {
    my $params = shift;
    my $name = $params->{name};
    my $cmd = qq{/sbin/lvremove /dev/lxc/$name -f};
    my $r = Klol::Run->new( $cmd );
    die "The lxc-destroy command fails with the following error: $r->error"
        unless $r->success;
}

1;

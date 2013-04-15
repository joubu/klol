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
    my $lvs = list_lvs('lxc');
    return $lvs->{"/dev/lxc/$lv_name"};
}

sub list_lvs {
    my $vg_name = shift || q{};
    my $cmd = qq{/sbin/lvdisplay -c $vg_name};

    my $r = Klol::Run->new( $cmd, { no_die => 1 } );

    my @full = $r->full;
    unless ( $r->success ) {
        return if @full and $full[0] =~ q{One or more specified logical volume\(s\) not found};
        die "The lvdisplay command fails with the following error:" . $r->error;
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
    my $r = eval{ Klol::Run->new( $cmd, { no_die => 1 } ) };
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
    return $r->success;
}

sub lv_format {
    my $params = shift;
    my $name = $params->{name};
    my $fstype = $params->{fstype};
    return unless $name or $fstype;
    my $cmd = qq{/sbin/mkfs -t $fstype /dev/lxc/$name};
    my $r = Klol::Run->new( $cmd );
    return $r->success;
}

sub lv_mount {
    my $params = shift;
    my $name = $params->{name};
    my $fstype = $params->{fstype};
    my $lxc_root = $params->{lxc_root} || q{/var/lib/lxc};
    return unless $name or $fstype;
    my $cmd = qq{/bin/mount -t $fstype /dev/lxc/$name $lxc_root/$name/rootfs};
    my $r = Klol::Run->new( $cmd );
    return $r->success;
}

sub lv_umount {
    my $params = shift;
    my $name = $params->{name};
    return unless $name;
    my $cmd = qq{/bin/umount /dev/lxc/$name};
    my $r = Klol::Run->new( $cmd );
    return $r->success;
}

sub lv_remove {
    my $params = shift;
    my $name = $params->{name};
    my $cmd = qq{/sbin/lvremove /dev/lxc/$name -f};
    my $r = Klol::Run->new( $cmd );
    return $r->success;
}

1;

__END__

=pod

=head1 NAME

Klol::LVM - LVM tools box

=head1 DESCRIPTION

This module provides some routines for LVM

=head1 ROUTINES

=head2 check_config

    LVM::check_config;

Check the if LVM is willing to be used: LVM is installed and VG 'lxc' exists.

=head2 is_lv

    LVM::is_lv( { name => 'lv_name' } );

Return logical volume information if exists.
If not, return an undefined value.

=head2 list_lvs

    LVM::list_lvs( 'vg_name' );

Return hashref representing logical volumes.
If a volume group name is given, return LV of this VG.

=head2 is_vg

    LVM::is_vg( 'vg_name' );

Return hashref representing the volume group with a name given in parameter, else undef.

=head2 list_vgs

    LVM::list_vgs( 'vg_name' );

Return hashref representing volume groups.
If a volume group name is given, return only the matching one.

=head2 lv_create

    LVM::lv_create(
        {
            name => 'lv_name',
            size => '10G',
        }
    );

Create a logical volume with a given name and size.
The logical volume will be create in the volume group 'lxc'.

=head2 lv_format

    LVM::lv_format(
        {
            name => 'lv_name',
            fstype => 'ext4',
        }
    );

Format the logical volume with the given file system type.

=head2 lv_mount

    LVM::lv_mount(
        {
            name => 'lv_name',
            fstype => 'ext4',
            lxc_root => '/var/lib/lxc',
        }
    );

Mount a logical volume on the rootfs's lxc container.

=head2 lv_umount

    LVM::lv_umount(
        {
            name => 'lv_name',
        }
    );

Umount a logical volume.

=head2 lv_remove

    LVM::lv_remove(
        {
            name => 'lv_name',
        }
    );

Remove a logical volume.
/!\ Destructive routine!

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


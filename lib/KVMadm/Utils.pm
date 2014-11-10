package KVMadm::Utils;

use strict;
use warnings;

use Illumos::SMF;

my $FMRI     = 'svc:/system/kvm';
my $ZFS      = '/usr/sbin/zfs';
my $QEMU_KVM = '/usr/bin/qemu-system-x86_64';
my $DLADM    = '/usr/sbin/dladm';

my %vcpuOptions = (
    sockets => undef,
    cores   => undef,
    threads => undef,
    maxcpus => undef,
);    

my %diskCacheOptions = (
    none         => undef,
    writeback    => undef,
    writethrough => undef,
);

my %shutdownOptions = (
    acpi        => undef,
    kill        => undef,
    acpi_kill   => undef,
);

# public methods
sub boolean {
    return shift =~ /^(?:true|false)$/i;
}

sub numeric {
    return shift =~ /^\d+$/;
}

sub alphanumeric {
    return shift =~ /^[-\w]+$/;
}

sub disk_model {
    return grep { $_[0] eq $_ } qw(ide virtio);
}

sub disk_path {
    my $path = shift;
    my $disk = shift;

    if (exists $disk->{media} && $disk->{media} eq 'cdrom'){
        -f $path || die "ERROR: cdrom image '$path' does not exist\n";
    }
    else{
        $path =~ s|^/dev/zvol/rdsk/||;

        -e "/dev/zvol/rdsk/$path" || do {
            my @cmd = ($ZFS, qw(create -p -V), ($disk->{disk_size} // '10G'),
                $path);

            print STDERR "-> zvol $path does not exist. creating it...\n";
            system(@cmd) && die "ERROR: cannot create zvol '$path'\n";
        };
    }
    return 1;
}

sub disk_media {
    return grep { $_[0] eq $_ } qw(disk cdrom);
}

sub disk_size {
    return shift =~ /^\d+[bkmgtp]$/i;
}

sub disk_cache {
    my $diskCache = shift;
    return exists $diskCacheOptions{$diskCache};
}

sub nic_name {
    my $nicName = shift;
    my $nic = shift;

    my @cmd = ($DLADM, qw(show-vnic -p -o link));

    open my $vnics, '-|', @cmd or die "ERROR: cannot get vnics\n";

    my @vnics = <$vnics>;
    chomp(@vnics);
    close $vnics;

    grep { $nicName eq $_ } @vnics or do {
        #get first physical link if over is not given
        exists $nic->{over} || do {
            @cmd = ($DLADM, qw(show-phys -p -o link));

            open my $nics, '-|', @cmd or die "ERROR: cannot get nics\n";

            chomp($nic->{over}  = <$nics>);
            close $nics;
        };
             
        @cmd = ($DLADM, qw(create-vnic -l), $nic->{over}, $nicName);
        print STDERR "-> vnic '$nicName' does not exist. creating it...\n";
        system(@cmd) && die "ERROR: cannot create vnic '$nicName'\n";
    };

    return 1;
}

sub time_base {
    return grep { $_[0] eq $_ } qw(utc localtime);
}

sub vcpu {
    my $vcpu = shift;

    return 1 if numeric($vcpu);

    my @vcpu = split ',', $vcpu;

    shift @vcpu if numeric($vcpu[0]);
    
    for my $vcpuConf (@vcpu){
        my @vcpuConf = split '=', $vcpuConf, 2;
        exists $vcpuOptions{$vcpuConf[0]} && numeric($vcpuConf[1])
            or return 0;
    }

    return 1;
}

sub cpu_type {
    my $cpu_type = shift;
    my @cmd = ($QEMU_KVM, qw(-cpu ?));

    open my $types, '-|', @cmd or die "ERROR: cannot get cpu types\n";
    my @types = <$types>;
    chomp(@types);
    close $types;

    return grep { /\[?$cpu_type\]?$/ } @types;
}

sub vnc {
    my $vnc = shift;

    return numeric($vnc) || $vnc =~ /^sock(?:et)?$/i;
}

sub serial_name {
    my $name = shift;

    return 1 if alphanumeric($name) && $name !~ /^(?:pid|vnc|monitor)$/;
}

sub shutdown_type {
    my $shutdownType = shift;
    return exists $shutdownOptions{$shutdownType}
}

1;

__END__

=head1 NAME

KVMadm::Utils - kvmadm helper module

=head1 SYNOPSIS

use KVMadm::Utils;

=head1 DESCRIPTION

methods to check kvmadm configuration

=head1 FUNCTIONS

=head2 boolean

checks if the argument is boolean

=head2 numeric

checks if the argument is numeric

=head2 alphanumeric

checks if the argument is alphanumeric

=head2 disk_model

checks if the disk model is 'ide' or 'virtio'

=head2 disk_path

checks if a zvol/image exists, tries to create it if not

=head2 disk_media

checks if the disk media is 'disk' or 'cdrom'

=head2 disk_size

checks if the disk size is valid

=head2 disk_cache

checks if the argument is a valid disk cache option

=head2 nic_name

checks if a vnic exists, tires to create it if not

=head2 serial_name

checks if serial_name is not one of the reserved names

=head2 time_base

checks if timebase is 'utc' or 'localtime'

=head2 vcpu

checks if a vcpu setting is valid

=head2 cpu_type

checks if a cpu_type is supported by qemu

=head2 vnc

checks if the argument is either numeric or 'sock'

=head2 shutdown_type

checks if the argument is a valid schutdown type

=head1 COPYRIGHT

Copyright (c) 2014 by OETIKER+PARTNER AG. All rights reserved.

=head1 LICENSE

This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see L<http://www.gnu.org/licenses/>.

=head1 AUTHOR

S<Dominik Hassler E<lt>hadfl@cpan.orgE<gt>>,
S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

2014-10-07 had Initial Version

=cut

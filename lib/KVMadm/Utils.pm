package KVMadm::Utils;

use strict;
use warnings;

use Text::ParseWords qw(shellwords);

my $FMRI     = 'svc:/system/kvm';
my $ZFS      = '/usr/sbin/zfs';
my $QEMU_KVM = '/usr/bin/qemu-system-x86_64';
my $DLADM    = '/usr/sbin/dladm';
my $IFCONFIG = '/usr/sbin/ifconfig';
my $ISAINFO  = '/usr/bin/isainfo';
my $TEST     = '/usr/bin/test';

my %vcpuOptions = (
    sockets => undef,
    cores   => undef,
    threads => undef,
    maxcpus => undef,
);    

my %shutdownOptions = (
    acpi        => undef,
    kill        => undef,
    acpi_kill   => undef,
);

# constructor
sub new {
    my $class = shift;
    my $self = { @_ };

    return bless $self, $class
}

# private methods
my $numeric = sub {
    return shift =~ /^\d+$/;
};

my $alphanumeric = sub {
    return shift =~ /^[-\w]+$/;
};

my $calcBlkSize = sub {
    my $blkSize = shift;
    
    my ($val, $suf) = $blkSize =~ /^(\d+)(k?)$/i
        or return undef;
    
    return $suf ? $val * 1024 : $val;
};

# public methods
sub file {
    my $self = shift;
    my $op = shift;
    my $msg = shift;

    return sub {
        my $file = shift;
        return open (my $fh, $op, $file) ? undef : "$msg $file: $!";
    }
}

sub cmd {
    my $self = shift;
    my $msg  = shift;

    return sub {
        my $cmd = shift;
        my @cmd = ($TEST, '-x', (shellwords($cmd))[0]);
        return !system (@cmd) ? undef : "$msg $cmd: $!";
    }
}

sub zonePath {
    my $self = shift;

    return sub {
        my $path = shift;
        return $path =~ /^\/[-\w\/]+$/ ? undef : "zonepath '$path' is not valid";
    }
}

sub regexp {
    my $self = shift;
    my $rx = shift;
    my $msg = shift;

    return sub {
        my $value = shift;
        return $value =~ /$rx/ ? undef : "$msg ($value)";
    }
}

sub elemOf {
    my $self = shift;
    my $elems = [ @_ ];

    return sub {
        my $value = shift;
        return (grep { $_ eq $value } @$elems) ? undef
            : 'expected a value from the list: ' . join(', ', @$elems);
    }
}

sub diskPath {
    my $self = shift;

    return sub {
        my ($path, $disk) = @_;

        if (exists $disk->{media} && $disk->{media} eq 'cdrom'){
            -f $path || die "ERROR: cdrom image '$path' does not exist\n";
        }
        else{
            $path =~ s|^/dev/zvol/rdsk/||;

            if (-e "/dev/zvol/rdsk/$path") {
                return undef if !$disk->{block_size};

                my @cmd = ($ZFS, qw(get -H -o value volblocksize), $path);    
                open my $blks, '-|', @cmd or die "ERROR: cannot get volblocksize property of '$path'\n";
                chomp (my $blkSize = <$blks>);
        
                $calcBlkSize->($blkSize) != $calcBlkSize->($disk->{block_size}) && do {
                    # reset volblocksize and warn
                    $disk->{block_size} = $blkSize;
                    print STDERR "WARNING: volblocksize property of '$path' cannot be changed after creation!\n"
                               . "If you want to change the block_size property create a new zvol manually\n"
                               . "and 'dd' the old zvol contents to the new.\n\n";
                };
            }
            else {
                my @cmd = ($ZFS, qw(create -p),
                    ($disk->{block_size} ? ('-o', "volblocksize=$disk->{block_size}") : ()),
                    '-V', ($disk->{disk_size} // '10G'), $path);

                print STDERR "-> zvol $path does not exist. creating it...\n";
                system(@cmd) && die "ERROR: cannot create zvol '$path'\n";
            }
        }
        return undef;
    }
}

sub blockSize {
    my $self = shift;

    return sub {
        my $blkSize = shift;

        my $val = $calcBlkSize->($blkSize)
            or die "ERROR: block_size '$blkSize' not valid\n";

        $val >= 512
            or die "ERROR: block_size '$blkSize' not valid. Must be greater or equal than 512.\n";
        $val <= 128 * 1024
            or die "ERROR: block_size '$blkSize' not valid. Must be less or equal than 128k.\n";
        ($val & ($val - 1))
            and die "ERROR: block_size '$blkSize' not valid. Must be a power of 2.\n";

        return undef;
    }
}

sub nicName {
    my $self = shift;
    my $isGZ = shift;

    return sub {
        my ($nicName, $nic) = @_;

        #use string for 'link,over,vid' as perl will warn otherwise
        my @cmd = ($DLADM, qw(show-vnic -p -o), 'link,over,vid');

        open my $vnics, '-|', @cmd or die "ERROR: cannot get vnics\n";

        while (<$vnics>){
            chomp;
            my @nicProps = split ':', $_, 3;
            next if $nicProps[0] ne $nicName;

            $nic->{over} && $isGZ && $nic->{over} ne $nicProps[1]
                && die "ERROR: vnic specified to be over '" . $nic->{over}
                    . "' but is over '" . $nicProps[1] . "' in fact\n";

            $nic->{vlan_id} && $nic->{vlan_id} ne $nicProps[2]
                && die "ERROR: vlan id specified to be '" . $nic->{vlan_id}
                    . "' but is '" . $nicProps[2] . "' in fact\n";

            #reset mtu size in case it has been changed
            exists $nic->{mtu} && $isGZ && do {
                @cmd = ($DLADM, qw(set-linkprop -p), "mtu=$nic->{mtu}", $nicName);
                system(@cmd)
                    && die "ERROR: cannot set mtu to '$nic->{mtu}' on vnic '$nicName'\n";
            };

            return undef;
        };
        close $vnics;

        #only reach here if vnic does not exist
        #get first physical link if over is not given
        exists $nic->{over} || do {
            @cmd = ($DLADM, qw(show-phys -p -o link));

            open my $nics, '-|', @cmd or die "ERROR: cannot get nics\n";

            chomp($nic->{over} = <$nics>);
            close $nics;
        };

        @cmd = ($DLADM, qw(create-vnic -l), $nic->{over},
            $nic->{vlan_id} ? ('-v', $nic->{vlan_id}, $nicName) : $nicName);
        print STDERR "-> vnic '$nicName' does not exist. creating it...\n";
        system(@cmd) && die "ERROR: cannot create vnic '$nicName'\n";

        exists $nic->{mtu} && do {
            @cmd = ($DLADM, qw(set-linkprop -p), "mtu=$nic->{mtu}", $nicName);
            system(@cmd)
                && die "ERROR: cannot set mtu to '$nic->{mtu}' on vnic '$nicName'\n";
        };

        return undef;
    }
}

sub vcpu {
    my $self = shift;

    return sub {
        my $vcpu = shift;

        return undef if $numeric->($vcpu);

        my @vcpu = split ',', $vcpu;

        shift @vcpu if $numeric->($vcpu[0]);
    
        for my $vcpuConf (@vcpu){
            my @vcpuConf = split '=', $vcpuConf, 2;
            exists $vcpuOptions{$vcpuConf[0]} && $numeric->($vcpuConf[1])
                or return "ERROR: vcpu setting not valid";
        }

        return undef;
    }
}

sub cpuType {
    my $self = shift;

    return sub {
        my $cpu_type = shift;
        my @cmd = ($QEMU_KVM, qw(-cpu ?));

        open my $types, '-|', @cmd or die "ERROR: cannot get cpu types\n";
        my @types = <$types>;
        chomp(@types);
        close $types;

        @cmd = ($ISAINFO, qw(-x));

        open my $inst, '-|', @cmd or die "ERROR: cannot get cpu instruction sets\n";
        chomp(my $instSet = <$inst>);
        close $inst;
        $instSet =~ s/^amd64:\s+//;
        my @inst = map { "+$_" } split /\s+/, $instSet;

        my @cpu_type = split ',', $cpu_type;

        return "ERROR: vcpu type not valid" if !grep { /\[?$cpu_type[0]\]?$/ } @types;
        shift @cpu_type;

        for my $feature (@cpu_type){
            return "ERROR: vcpu type feature not valid" if !grep { $_ eq $feature } @inst;
        }

        return undef;
    }
}

sub vnc {
    my $self = shift;

    return sub {
        my $vnc = shift;
        my $cfg = shift;

        return undef if $vnc =~ /^sock(?:et)?$/i;

        my ($ip, $port) = $vnc =~ /^(?:(\d{1,3}(?:\.\d{1,3}){3}):)?(\d+)$/i;
        $ip //= '127.0.0.1';
        return "ERROR: vnc port not valid" if !defined $port;

        $cfg->{zone} && do {
            print STDERR "\nWARNING: you are going to use VNC bound to $ip:$port within a zone.\n"
                       . "           you have to manually add a vnic to the zone and set it up properly within the zone.\n"
                       . "           to avoid this, use \"vnc\" : \"socket\" in your configuration and 'kvmadm vnc' to forward it to IP.\n\n"; 

            return undef;
        };

        my @ips = qw(0.0.0.0);
        open my $inetAddr, '-|', $IFCONFIG or die "ERROR: cannot get IP addresses\n";
        while (<$inetAddr>){
            chomp;
            next if !/inet\s+(\d{1,3}(?:\.\d{1,3}){3})/;
            push @ips, $1;
        };
        close $inetAddr;

        return $numeric->($port) && (grep { $ip eq $_ } @ips)
            ? undef : "ERROR: vnc setting not valid. check bind_addr and port values"; 
    }
}

sub vncPwFile {
    my $self = shift;

    return sub {
        my $pwFile = shift;

        -f $pwFile or die "ERROR: vnc password file '$pwFile' does not exist\n";

        open my $fh, '<', $pwFile or die "ERROR: cannot open vnc password file $pwFile: $!\n";
        chomp(my $password = do { local $/; <$fh>; });
        close $fh;

        return length($password) <= 8 ? undef
            : "ERROR: password must be less or equal than 8 characters";
    }
}

sub serialName {
    my $self = shift;

    return sub {
        my $name = shift;

        return $alphanumeric->($name) && $name !~ /^(?:pid|vnc|monitor)$/
            ? undef : "ERROR: serial device name not valid";
    }
}

sub uuid {
    my $self = shift;

    return sub {
        return shift =~ /^[\da-f]{8}-[\da-f]{4}-[1-5][\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/i
            ? undef : "ERROR: uuid is not a valid version 4 uuid";
    }
}

sub purgeVnic {
    my $self = shift;
    my $config = shift;

    for my $nic (@{$config->{nic}}){
        my @cmd = ($DLADM, qw(delete-vnic), $nic->{nic_name});
        system(@cmd) && die "ERROR: cannot delete vnic '$nic->{nic_name}'\n";
    }
}

sub purgeZvol {
    my $self = shift;
    my $config = shift;

    for my $zvol (@{$config->{disk}}){
        #do not remove cdrom images
        next if $zvol->{media} && $zvol->{media} eq 'cdrom';

        $zvol->{disk_path} =~ s|^/dev/zvol/rdsk/||;
        my @cmd = ($ZFS, qw(destroy), $zvol->{disk_path});
        system(@cmd) && die "ERROR: cannot destroy zvol '$zvol->{disk_path}'\n";
    }
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

checks if the disk model is 'ide', 'scsi' or 'virtio'

=head2 disk_path

checks if a zvol/image exists, tries to create it if not

=head2 disk_media

checks if the disk media is 'disk' or 'cdrom'

=head2 disk_size

checks if the disk size is valid

=head2 disk_cache

checks if the argument is a valid disk cache option

=head2 nic_model

checks if the nic model is 'virtio', 'e1000' or 'rtl8139'

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

=head2 vnc_pw_file

checks if the file exists and contains a pw which is <= 8 characters long

=head2 shutdown_type

checks if the argument is a valid schutdown type

=head2 uuid

checks if a uuid is valid

=head2 nocheck

returns true

=head2 purge_vnic

deletes all vnic attached to the config

=head2 purge_zvol

deletes all zvols attached to the config

=head1 COPYRIGHT

Copyright (c) 2015 by OETIKER+PARTNER AG. All rights reserved.

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

2015-04-28 had Zone support
2014-10-07 had Initial Version

=cut

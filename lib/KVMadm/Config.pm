package KVMadm::Config;

use strict;
use warnings;

use Illumos::SMF;
use KVMadm::Utils;

# constants/programs
my $QEMU_KVM = '/usr/bin/qemu-system-x86_64';
my $DLADM    = '/usr/sbin/dladm';
my $FMRI     = 'svc:/system/kvm';
my $PGRP     = 'kvmadm';
my $RUN_PATH = '/var/run/kvm';
my $VIRTIO_TXTIMER_DEFAULT = 200000;
my $VIRTIO_TXBURST_DEFAULT = 128;

# globals
my $smf;
my $kvmTemplate = {
    vcpus       => 4,
    ram         => 1024,
    vnc         => 0,
    time_base   => 'utc',
    boot_order  => 'cd',
    disks       => [
        {
            boot        => 'true',
            model       => 'virtio',
            disk_path  => '',
            disk_size  => '10G',
            index       => '0',
        }
    ],
    nics        => [
        {
            nic_name    => '',
            over        => '',
            model       => 'virtio',
            index       => '0',
        }
    ],
    serials     => [
        {
            serial_name => 'console',
            index       => '0',
        }
    ],
};

my $kvmProperties = {
    mandatory => {
        vnc         => \&KVMadm::Utils::vnc,
    },
    optional  => {
        vcpus       => \&KVMadm::Utils::vcpu,
        ram         => \&KVMadm::Utils::numeric,
        time_base   => \&KVMadm::Utils::time_base,
        boot_order  => \&KVMadm::Utils::alphanumeric,
        hpet        => \&KVMadm::Utils::boolean,
        usb_tablet  => \&KVMadm::Utils::boolean,
        cpu_type    => \&KVMadm::Utils::cpu_type,
        shutdown    => \&KVMadm::Utils::shutdown_type,
        cleanup     => \&KVMadm::Utils::boolean,
    },
    sections  => {
        #section names must end with an 's'
        disks   => {
            mandatory => {
                model       => \&KVMadm::Utils::disk_model,
                disk_path   => \&KVMadm::Utils::disk_path,
                index       => \&KVMadm::Utils::numeric,
            },
            optional  => {
                boot        => \&KVMadm::Utils::boolean,
                media       => \&KVMadm::Utils::disk_media,
                disk_size   => \&KVMadm::Utils::disk_size,
                cache       => \&KVMadm::Utils::disk_cache,
            },
        },
        nics    => {
            mandatory => {
                model       => \&KVMadm::Utils::alphanumeric,
                nic_name    => \&KVMadm::Utils::nic_name,
                index       => \&KVMadm::Utils::numeric,
            },
            optional  => {
                over        => \&KVMadm::Utils::alphanumeric,
                txtimer     => \&KVMadm::Utils::numeric,
                txburst     => \&KVMadm::Utils::numeric,
            },
        },
        serials => {
            mandatory => {
                serial_name => \&KVMadm::Utils::serial_name,
                index       => \&KVMadm::Utils::numeric,
            },
            optional  => {
            },
        },
    },
};

# private methods
my $getMAC = sub {
    my $vnicName = shift;

    my @cmd = ($DLADM, qw(show-vnic -po macaddress), $vnicName);
    open my $macAddr, '-|', @cmd
        or die "ERROR: cannot get mac address of vnic $vnicName\n";
    
    my $mac = <$macAddr>;
    close $macAddr;
    $mac or die "ERROR: cannot get mac address of vnic $vnicName\n";
    chomp $mac;
    $mac =~ s/(?<![\da-f])([\da-f])(?![\da-f])/0$1/gi;
    return $mac;
};

# constructor
sub new {
    my $class = shift;
    my $self = { @_ };

    $smf = Illumos::SMF->new(debug => $self->{debug});
    return bless $self, $class
}

# public methods
sub getTemplate {
    return $kvmTemplate;
}

sub removeKVM {
    my $self = shift;
    my $kvmName = shift;

    $smf->deleteFMRI("$FMRI:$kvmName");
}

sub checkConfig {
    my $self = shift;
    my $config = shift;
    my $configLayout = $_[0] // $kvmProperties;

    #check if mandatory options are set
    for my $mandOpt (keys %{$configLayout->{mandatory}}){
        exists $config->{$mandOpt}
            or die "ERROR: mandatory option $mandOpt not set\n";
    }
    
    #check options
    OPT_LBL: for my $opt (keys %$config){
        exists $configLayout->{sections}->{$opt} && do {
            for my $item (@{$config->{$opt}}){
                $self->checkConfig($item, $configLayout->{sections}->{$opt});
            }
            next OPT_LBL;
        };

        for my $section (qw(mandatory optional)){
            exists $configLayout->{$section}->{$opt} && do {
                $configLayout->{$section}->{$opt}->($config->{$opt}, $config)
                    or die "ERROR: value '$config->{$opt}' for  property '$opt' not correct.\n";

                next OPT_LBL;
            };
        }

        die "ERROR: don't know the property '$opt'.\n";
    }

    return 1;
}

sub writeConfig {
    my $self = shift;
    my $kvmName = shift;
    my $config = shift;

    $self->checkConfig($config);
    
    #create instance if it does not exist
    $smf->addInstance($FMRI, $kvmName)
        if !$smf->fmriExists("$FMRI:$kvmName");

    #delete property group to wipe off existing config
    $smf->deletePropertyGroup("$FMRI:$kvmName", $PGRP)
        if $smf->propertyExists("$FMRI:$kvmName", $PGRP);

    $smf->addPropertyGroup("$FMRI:$kvmName", $PGRP);
    
    $smf->refreshFMRI("$FMRI:$kvmName");

    #write section configs
    for my $section (keys $kvmProperties->{sections}){
        my $counter = 0;
        my ($devName) = $section =~ /^(.+)s$/;

        for my $dev (@{$config->{$section}}){
            %$dev = (map { "$PGRP/$devName" . $counter . '_' . $_ => $dev->{$_} } keys %$dev);
            $smf->setProperties("$FMRI:$kvmName", $dev);
            $counter++;
        }
        delete $config->{$section};
    }

    #write general kvm config
    %$config = (map { $PGRP . '/' . $_ => $config->{$_} } keys %$config);
    $smf->setProperties("$FMRI:$kvmName", $config);

    $smf->refreshFMRI("$FMRI:$kvmName");

    return 1;
}

sub readConfig {
    my $self = shift;
    my $kvmName = shift;

    my $config = {};
    
    $smf->fmriExists("$FMRI:$kvmName") or die "ERROR: KVM instance '$kvmName' does not exist\n";

    my $properties = $smf->getProperties("$FMRI:$kvmName", $PGRP);

    my $sectRE = join '|', map { /^(.+)s$/; $1 } keys $kvmProperties->{sections};

    for my $prop (keys %$properties){
        my $value = $properties->{$prop};
        $prop =~ s|^$PGRP/||;

        for ($prop){
            /^($sectRE)(\d+)_(.+)$/ && do {
                my $sect  = $1 . 's';
                my $index = $2;
                my $key   = $3;

                exists $config->{$sect} or $config->{$sect} = [];
                while ($#{$config->{$sect}} < $index){
                    push @{$config->{$sect}}, {};
                }

                $config->{$sect}->[$index]->{$key} = $value;
                last;
            };
            
            $config->{$prop} = $value;
        }
    }
    return $config;
}

sub listKVM {
    my $self = shift;
    my $kvmName = shift;

    my $fmri = $FMRI . ($kvmName ? ":$kvmName" : '');
    my @fmris = $smf->listFMRI($fmri);

    my %instances;

    for my $instance (@fmris){
        $instance =~ s/^$FMRI://;
        my $config = $self->readConfig($instance);
        $instances{$instance} = $config;
    }

    return \%instances;
}

sub getKVMCmdArray {
    my $self = shift;
    my $kvmName = shift;

    my $config = $self->readConfig($kvmName);
    $self->checkConfig($config);

    my @cmdArray = ($QEMU_KVM);
    push @cmdArray, ('-name', $kvmName);
    push @cmdArray, qw(-enable-kvm -vga std);
    push @cmdArray, '-no-hpet' if !exists $config->{hpet} || $config->{hpet} !~ /^true$/i;
    push @cmdArray, ('-m', $config->{ram} // '1024');
    push @cmdArray, ('-cpu', $config->{cpu_type} // 'host');
    push @cmdArray, ('-smp', $config->{vcpus} // '1');
    push @cmdArray, ('-rtc', 'base=' . ($config->{time_base} // 'utc') . ',driftfix=slew');
    push @cmdArray, ('-pidfile', $RUN_PATH . '/' . $kvmName . '.pid');
    push @cmdArray, ('-monitor', 'unix:' . $RUN_PATH . '/' . $kvmName . '.monitor,server,nowait,nodelay');

    if ($config->{vnc} =~ /^sock(?:et)?$/i){
        push @cmdArray, ('-vnc', 'unix:' . $RUN_PATH . '/' . $kvmName . '.vnc'); 
    }
    else{
        $config->{vnc} -= 5900 if $config->{vnc} >= 5900;
        push @cmdArray, ('-vnc', '0.0.0.0:' . $config->{vnc} . ',console');
    }

    for my $disk (@{$config->{disks}}){
        $disk->{disk_path} = '/dev/zvol/rdsk/' . $disk->{disk_path}
            if (!exists $disk->{media} || $disk->{media} ne 'cdrom')
                && $disk->{disk_path} !~ m|^/dev/zvol/rdsk/|;

        push @cmdArray, ('-drive',
              'file='   . $disk->{disk_path}
            . ',if='    . ($disk->{model} // 'ide')
            . ',media=' . ($disk->{media} // 'disk')
            . ',index=' . $disk->{index}
            . ',cache=' . ($disk->{cache} // 'none')
            . ($disk->{boot} ? ',boot=on' : ''));
    }
    push @cmdArray, ('-boot', 'order=' . ($config->{boot_order} ? $config->{boot_order} : 'cd'));

    for my $nic (@{$config->{nics}}){
        my $mac = $getMAC->($nic->{nic_name});

        if ($nic->{model} eq 'virtio'){
            push @cmdArray, ('-device',
                  'virtio-net-pci'
                . ',mac=' . $mac
                . ',tx=timer'
                . ',x-txtimer=' . ($nic->{txtimer} // $VIRTIO_TXTIMER_DEFAULT)
                . ',x-txburst=' . ($nic->{txburst} // $VIRTIO_TXBURST_DEFAULT)
                . ',vlan=' . $nic->{index});
        }
        else{
            push @cmdArray, ('-net', 'nic,vlan=' . $nic->{index} . ',name='
                . $nic->{nic_name} . ',model=' . $nic->{model} . ',macaddr=' . $mac);
        }

        push @cmdArray, ('-net', 'vnic,vlan=' . $nic->{index} . ',name='
            . $nic->{nic_name} . ',ifname=' . $nic->{nic_name});
    }

    for my $serial (@{$config->{serials}}){
        push @cmdArray, ('-chardev', 'socket,id=serial' . $serial->{index}
            . ',path=' . $RUN_PATH . '/' . $kvmName . '.' . $serial->{serial_name} . ',server,nowait');
        push @cmdArray, ('-serial', 'chardev:serial' . $serial->{index});
    }

    push @cmdArray, qw(-usb -usbdevice tablet)
        if $config->{usb_tablet} && $config->{usb_tablet} =~ /^true$/i;

    push @cmdArray, qw(-daemonize);

    return \@cmdArray;
}

sub getKVMShutdown {
    my $self = shift;
    my $kvmName = shift;

    my $config = $self->readConfig($kvmName);
    $self->checkConfig($config);

    return ($config->{cleanup} && $config->{cleanup} eq 'true', $config->{shutdown} // 'acpi');
}


1;

__END__

=head1 NAME

KVMadm::Config - kvmadm config class

=head1 SYNOPSIS

use KVMadm::Config;
...
my $config = KVMadm::config->new(debug=>0);
...

=head1 DESCRIPTION

reads and writes kvmadm configuration

=head1 ATTRIBUTES

=head2 debug

print debug information to STDERR

=head1 METHODS

=head2 removeKVM

removes a KVM instance from SMF

=head2 checkConfig

checks if a KVM configuration is valid

=head2 writeConfig

writes a KVM property set to SMF

=head2 readConfig

reads a KVM property set from SMF

=head2 listKVM

returns a list of instances and their property set from SMF

=head2 getKVMCmdArray

returns the qemu command array

=head2 getKVMShutdown

returns the shutdown mechanism for a KVM instance. defaults to 'acpi'

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

2014-10-03 had Initial Version

=cut

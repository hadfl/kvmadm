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
    vnc_port    => 5090,
    time_base   => 'utc',
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
            nic_tag     => '',
            model       => 'virtio',
            index       => '0',
        }
    ],
};

my $kvmProperties = {
    mandatory => {
        hostname    => \&KVMadm::Utils::alphanumeric,
        vnc_port    => \&KVMadm::Utils::numeric,
    },
    optional  => {
        vcpus       => \&KVMadm::Utils::numeric,
        ram         => \&KVMadm::Utils::numeric,
        time_base   => \&KVMadm::Utils::time_base,
    },
    sections  => {
        disks   => {
            mandatory => {
                model       => \&KVMadm::Utils::disk_model,
                disk_path   => undef,
                disk_size   => \&KVMadm::Utils::disk_size,
                index       => \&KVMadm::Utils::numeric,
            },
            optional  => {
                boot        => \&KVMadm::Utils::boolean,
                media       => \&KVMadm::Utils::disk_media,
            },
        },
        nics    => {
            mandatory => {
                model       => \&KVMadm::Utils::alphanumeric,
                nic_tag     => \&KVMadm::Utils::alphanumeric,
                index       => \&KVMadm::Utils::numeric,
            },
            optional  => {
                txtimer     => \&KVMadm::Utils::numeric,
                txburst     => \&KVMadm::Utils::numeric,
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

sub createKVM {
    my $self = shift;
    my $kvmName = shift;
    my $config = shift;

    $smf->addInstance($FMRI, $kvmName);
    $self->writeConfig($kvmName, $config);
}

sub removeKVM {
    my $self = shift;
    my $kvmName = shift;

    $smf->deleteFMRI("$FMRI:$kvmName");
}

sub checkConfig {
    my $self = shift;
    my $config = shift;

    #check if mandatory options are set
    for my $mandOpt (keys %{$kvmProperties->{mandatory}}){
        exists $config->{$mandOpt}
            or die "ERROR: mandatory option $mandOpt not set\n";
    }
    
    #check options
    OPT_LBL: for my $opt (keys %$config){
        next if exists $kvmProperties->{sections}->{$opt};

        for my $mandOpt (qw(mandatory optional)){
            exists $kvmProperties->{$mandOpt}->{$opt} && do {
                $kvmProperties->{$mandOpt}->{$opt}->($config->{$opt})
                    or die "ERROR: property $opt not correct. check the manual\n";

                next OPT_LBL;
            };
        }

        die "ERROR: don't know the option $opt. check the manual\n";
    }

    #set a reference to the disks section
    my $section = $kvmProperties->{sections}->{disks};
    for my $disk (@{$config->{disks}}){
        $section->{mandatory}->{disk_path}
            = exists $disk->{media} && $disk->{media} eq 'cdrom'
            ? sub { return -f $_[0]; } : \&KVMadm::Utils::zvolExists;

        for my $mandOpt (keys %{$section->{mandatory}}){
            exists $disk->{$mandOpt}
                or die "ERROR: mandatory option $mandOpt not set for disk\n";
        }

        OPT_LBL: for my $opt (keys $disk){
            for my $mandOpt (qw(mandatory optional)){
                exists $section->{$mandOpt}->{$opt} && do {
                    $section->{$mandOpt}->{$opt}->($disk->{$opt})
                        or die "ERROR: property $opt not correct. check the manual\n";

                    next OPT_LBL;
                };
            }

            die "ERROR: don't know the disk option $opt. check the manual\n";
        }
    }
    
    $section = $kvmProperties->{sections}->{nics};
    for my $nic (@{$config->{nics}}){
        for my $mandOpt (keys %{$section->{mandatory}}){
            exists $nic->{$mandOpt}
                or die "ERROR: mandatory option $mandOpt not set for nic\n";
        }

        OPT_LBL: for my $opt (keys $nic){
            for my $mandOpt (qw(mandatory optional)){
                $section->{$mandOpt}->{$opt} && do {
                    $section->{$mandOpt}->{$opt}->($nic->{$opt})
                        or die "ERROR: property $opt not correct. check the manual\n";

                    next OPT_LBL;
                };
            }

            die "ERROR: don't know the nic option $opt. check the manual\n";
        }
    }
    
    return 1;
}

sub writeConfig {
    my $self = shift;
    my $kvmName = shift;
    my $config = shift;

    $self->checkConfig($config);

    #add property group if it does not exist
    $smf->addPropertyGroup("$FMRI:$kvmName", $PGRP)
        if !$smf->propertyExists("$FMRI:$kvmName", $PGRP);

    #write disk configs
    my $counter = 0;
    for my $disk (@{$config->{disks}}){
        %$disk = (map { "$PGRP/disk$counter" . '_' . $_ => $disk->{$_} } keys %$disk);
        $smf->setProperties("$FMRI:$kvmName", $disk);
        $counter++;
    }
    delete $config->{disks};

    #write nic configs
    $counter = 0;
    for my $nic (@{$config->{nics}}){
        %$nic = (map { "$PGRP/nic$counter" . '_' . $_ => $nic->{$_} } keys %$nic);
        $smf->setProperties("$FMRI:$kvmName", $nic);
        $counter++;
    }
    delete $config->{nics};

    #write general kvm config
    %$config = (map { $PGRP . '/' . $_ => $config->{$_} } keys %$config);
    $smf->setProperties("$FMRI:$kvmName", $config);

    return 1;
}

sub readConfig {
    my $self = shift;
    my $kvmName = shift;

    my $config = {};
    
    my $properties = $smf->getProperties("$FMRI:$kvmName", $PGRP);

    for my $prop (keys %$properties){
        my $value = $properties->{$prop};
        $prop =~ s|^$PGRP/||;

        for ($prop){
            /disk(\d+)_(.+)$/ && do {
                my $index = $1;
                my $key   = $2;

                exists $config->{disks} or $config->{disks} = [];
                while ($#{$config->{disks}} < $index){
                    push @{$config->{disks}}, {};
                }

                $config->{disks}->[$index]->{$key} = $value;
                last;
            };
            
            /nic(\d+)_(.+)$/ && do {
                my $index = $1;
                my $key   = $2;

                exists $config->{nics} or $config->{nics} = [];
                while ($#{$config->{nics}} < $index){
                    push @{$config->{nics}}, {};
                }

                $config->{nics}->[$index]->{$key} = $value;
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
    my @cmdArray = ($QEMU_KVM);

    push @cmdArray, ('-name', $kvmName);
    push @cmdArray, qw(-enable-kvm -no-hpet -vga std);
    push @cmdArray, ('-m', $config->{mem} // '1024');
    push @cmdArray, ('-cpu', $config->{cpu_type} // 'host');
    push @cmdArray, ('-smp', $config->{vcpus} // 1);
    push @cmdArray, ('-rtc', 'base=' . ($config->{time_base} // 'utc') . ',driftfix=slew');
    push @cmdArray, ('-pidfile', $RUN_PATH . '/' . $kvmName . '.pid');
    push @cmdArray, ('-monitor', 'unix:' . $RUN_PATH . '/' . $kvmName . '.monitor,server,nowait,nodelay');
    push @cmdArray, ('-vnc', '0.0.0.0:' . ($config->{vnc_port} // 5900) . ',console');

    for my $disk (@{$config->{disks}}){
        push @cmdArray, ('-drive',
              'file=/dev/zvol/rdsk/'   . $disk->{disk_path}
            . ',if='    . $disk->{model} // 'ide'
            . ',media=' . $disk->{media} // 'disk' 
            . ',index=' . $disk->{disk_index});
    }

    for my $nic (@{$config->{nics}}){
        my $mac = $getMAC->($nic->{nic_tag});

        if ($nic->{model} eq 'virtio'){
            push @cmdArray, ('-device',
                  'virtio-net-pci'
                . ',mac=' . $mac
                . ',tx=timer'
                . ',x-txtimer=' . $nic->{txtimer} // $VIRTIO_TXTIMER_DEFAULT
                . ',x-txburst=' . $nic->{txburst} // $VIRTIO_TXBURST_DEFAULT
                . ',vlan=0');
        }
        else{
            push @cmdArray, ('-net', 'nic,vlan=0,name=net0,model='
                . $nic->{model} . ',macaddr=' . $mac);
        }

        push @cmdArray, ('-net', 'vnic,vlan=0,name=net0,ifname='
            . $nic->{nic_tag} . ',macaddr=' . $mac);
    }

    push @cmdArray, qw(-daemonize);

    return \@cmdArray;
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

=head2 createKVM

creates a new KVM instance in SMF

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

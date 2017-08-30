package KVMadm::Config;

use strict;
use warnings;

use File::Path qw(make_path);
use File::Basename qw(dirname);
use Illumos::SMF;
use Illumos::Zones;
use KVMadm::Utils;
use KVMadm::Progress;
use Data::Processor;

use FindBin;
my ($BASEDIR)   = dirname($FindBin::RealBin);

# constants/programs
my $QEMU_KVM = '/usr/bin/qemu-system-x86_64';
my $DLADM    = '/usr/sbin/dladm';
my $FMRI     = 'svc:/system/kvm';
my $PGRP     = 'kvmadm';
my $RUN_PATH = "/var$BASEDIR/run";
my $VIRTIO_TXTIMER_DEFAULT = 200000;
my $VIRTIO_TXBURST_DEFAULT = 128;

my $RESOURCES = {
    fs  => [
        {
            dir     => $BASEDIR,
            special => $BASEDIR,
            type    => 'lofs',
            options => '[ro,nodevices]',
        },
    ],
    device  => [
        {
            match   => '/dev/kvm',
        },
    ],
};

# globals
my $kvmTemplate = {
    vcpus       => 4,
    ram         => 1024,
    vnc         => 0,
    time_base   => 'utc',
    boot_order  => 'cd',
    disk        => [
        {
            boot        => 'true',
            model       => 'virtio',
            disk_path  => '',
            disk_size  => '10G',
            index       => '0',
        }
    ],
    nic         => [
        {
            nic_name    => '',
            over        => '',
            model       => 'virtio',
            index       => '0',
        }
    ],
    serial      => [
        {
            serial_name => 'console',
            index       => '0',
        }
    ],
    zone        => {
        zonepath  => '',
        'ip-type' => 'exclusive',
        brand     => 'lipkg',
    },
};

my $SCHEMA = sub {
    my $sv   = KVMadm::Utils->new();
    my $zone = Illumos::Zones->new();

    return {
    vnc     => {
        optional    => 1,
        description => "vnc setting. can either be [bind addr]:port or 'socket",
        example     => '"vnc" : "0.0.0.0:5900"',
        validator   => $sv->vnc(),
    },
    vnc_pw_file => {
        optional    => 1,
        description => 'vnc password file',
        example     => '"vnc_pw_file" : "/etc/opt/oep/kvmadm/vncpw"',
        validator   => $sv->vncPwFile(),
    },
    vcpus   => {
        optional    => 1,
        description => 'qemu cpu configuration',
        example     => '"vcpus" : "4"',
        default     => 1,
        validator   => $sv->vcpu(),
    },
    ram     => {
        optional    => 1,
        description => 'qemu ram configuration',
        example     => '"ram" : "1024"',
        default     => 1024,
        validator   => $sv->regexp(qr/^\d+$/),
    },
    time_base   => {
        optional    => 1,
        description => 'KVM time base (utc|localtime)',
        example     => '"time_base" : "utc"',
        default     => 'utc',
        validator   => $sv->elemOf(qw(utc localtime)),
    },
    boot_order  => {
        optional    => 1,
        description => 'boot order',
        example     => '"boot_order" : "cd"',
        validator   => $sv->regexp(qr/^[a-z]+$/),
    },
    hpet        => {
        optional    => 1,
        description => 'enable/disable hpet',
        example     => '"hpet" : "false"',
        default     => 'false',
        validator   => $sv->elemOf(qw(true false)),
    },
    usb_tablet  => {
        optional    => 1,
        description => 'enable/disable USB tablet',
        example     => '"usb_tablet" : "true"',
        validator   => $sv->elemOf(qw(true false)),
    },
    kb_layout   => {
        optional    => 1,
        description => 'keyboard layout',
        example     => '"kb_layout" : "en"',
        validator   => $sv->regexp(qr/^[-\w]+$/),
    },
    uuid        => {
        optional    => 1,
        description => 'KVM uuid',
        example     => '"uuid" : "e24c1c27-33ab-4ca1-ae25-1c98ff2e3c3d"',
        validator   => $sv->uuid(),
    },
    cpu_type    => {
        optional    => 1,
        description => 'qemu cpu type (host|qemu64)',
        example     => '"cpu_type" : "qemu64,+aes,+sse4.2,+sse4.1,+ssse3"',
        validator   => $sv->cpuType(),
    },
    shutdown    => {
        optional    => 1,
        description => 'shutdown type of KVM (acpi kill acpi_kill)',
        example     => '"shutdown" : "acpi"',
        validator   => $sv->elemOf(qw(acpi kill acpi_kill)),
    },
    cleanup => {
        optional    => 1,
        description => 'clean up run directory (i.e. sockets, pid-file, ...) after shutdown',
        example     => '"cleanup" : "false"',
        validator   => $sv->elemOf(qw(true false)),
    },
    qemu_extra_opts => {
        optional    => 1,
        description => 'extra options passed to qemu',
        validator   => sub { return undef },
    },
    disk   => {
        optional    => 1,
        array       => 1,
        description => 'disks for the KVM',
        members     => {
            model   => {
                description => 'disk model (ide|virtio|scsi)',
                example     => '"model" : "virtio"',
                default     => 'virtio',
                validator   => $sv->elemOf(qw(ide virtio scsi)),
            },
            disk_path   => {
                description => 'path of disk image',
                example     => '"disk_path" : "tank/kvms/mykvm/drivec"',
                validator   => $sv->diskPath(),
            },
            index   => {
                description => 'index of disk',
                example     => '"index" : "0"',
                validator   => $sv->regexp(qr/^\d+$/),
            },
            boot    => {
                optional    => 1,
                description => 'set disk as boot device',
                example     => '"boot" : "true"',
                validator   => $sv->elemOf(qw(true false)),
            },
            media   => {
                optional    => 1,
                description => 'disk media. can be "disk" or "cdrom"',
                example     => '"media" : "disk"',
                validator   => $sv->elemOf(qw(disk cdrom)),
            },
            disk_size   => {
                optional    => 1,
                description => 'zvol disk size. according to zfs syntax',
                example     => '"disk_size" : "10G"',
                validator   => $sv->regexp(qr/^\d+[bkmgtp]$/i),
            },
            block_size  => {
                optional    => 1,
                description => 'zvol block size',
                example     => '"block_size" : "128k"',
                validator   => $sv->blockSize(),
            },
            cache   => {
                optional    => 1,
                description => 'disk cache. can be "none", "writeback" or  "writethrough"',
                example     => '"cache" : "none"',
                default     => 'none',
                validator   => $sv->elemOf(qw(none writeback writethrough)),
            },
        },
    },
    nic    => {
        optional    => 1,
        array       => 1,
        description => 'nics for the KVM',
        members     => {
            model   => {
                description => 'nic model. can be "virtio" "e1000" or "rtl8139"',
                example     => '"model" : "virtio"',
                default     => 'virtio',
                validator   => $sv->elemOf(qw(virtio e1000 rtl8139)),
            },
            nic_name    => {
                description => 'name of the vnic. will be created if it does not exist',
                example     => '"nic_name" : "mykvm0"',
                validator   => $sv->nicName(Illumos::Zones->isGZ),
            },
            index   => {
                description => 'index of the vnic',
                example     => '"index" : "0"',
                validator   => $sv->regexp(qr/^\d+$/),
            },
            over    => {
                optional    => 1,
                description => 'physical nic where vnic traffic goes over',
                example     => '"over" : "physnic0"',
                validator   => $sv->regexp(qr/^[-\w]+$/),
            },
            vlan_id => {
                optional    => 1,
                description => 'vlan id for the vnic',
                example     => '"vlan_id" : "12"',
                validator   => $sv->regexp(qr/^\d+$/),
            },
            mtu => {
                optional    => 1,
                description => 'sets the mtu of the vnic. must be supportet by physical nic',
                example     => '"mtu" : "1500"',
                validator   => $sv->regexp(qr/^\d+$/),
            },
            txtimer => {
                optional    => 1,
                description => 'txtimer for virtio-net-pci',
                example     => '"txtimer" : "200000"',
                validator   => $sv->regexp(qr/^\d+$/),
            },
            txburst => {
                optional    => 1,
                description => 'txburst for virtio-net-pci',
                example     => '"txburst" : "128"',
                validator   => $sv->regexp(qr/^\d+$/),
            },
        },
    },
    serial => {
        optional    => 1,
        array       => 1,
        description => 'serial ports for the KVM',
        members     => {
            serial_name => {
                description => 'name of the serial port. alphanumeric but not "pid", "vnc" or "monitor"',
                example     => '"serial_name" : "serial0"',
                validator   => $sv->serialName(),
            },
            index   => {
                description => 'index of the serial port',
                example     => '"index" : "0"',
                validator   => $sv->regexp(qr/^\d+$/),
            },
        },
    },
    zone    => {
        optional    => 1,
        description => 'zone config for the KVM',
        members => $zone->schema(),
    },
    pre_start_cmd => {
        optional    => 1,
        description => 'command to run before starting qemu',
        example     => '/usr/bin/sleep 300',
        validator   => $sv->cmd('cannot execute'),
    },
    }
};

my $SECTIONS = sub {
    my $schema = $SCHEMA->();
    return [ map { $schema->{$_}->{array} ? $_ : () } keys %$schema ];
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

my $insertZone = sub {
    my $kvmName = shift;
    my $zone    = shift;
    return $zone ? { zonename => $kvmName } : {};
};

my $writeArray = sub {
    my $self    = shift;
    my $kvmName = shift;
    my $prefix  = shift;
    my $array   = shift;
    my $zConf   = shift;

    my $counter = 0;
    for my $dev (@$array){
        $self->{prog}->progress;
        %$dev = map { "$PGRP/$prefix$counter" . '_' . $_ => $dev->{$_} } keys %$dev;
        $self->{smf}->setProperties("$FMRI:$kvmName", $dev, $insertZone->($kvmName, $zConf));
        $counter++;
    }
};

my $getOwnResources = sub {
    my $cfg     = shift;
    my $kvmName = shift;
    # make a copy, not to modify global $RESOURCES
    my $res = { map { $_ => [ @{$RESOURCES->{$_}} ] } keys %$RESOURCES };

    # add run path
    push @{$res->{fs}}, {
        dir     => "$RUN_PATH/$kvmName",
        special => "$RUN_PATH/$kvmName",
        type    => 'lofs',
        options => '[nodevices]',
    };

    for my $disk (@{$cfg->{disk}}) {
        my $path = $disk->{disk_path};
        $path =~ s|^/dev/zvol/rdsk/||;

        if ($disk->{media} && $disk->{media} eq 'cdrom') {
            push @{$res->{fs}}, {
                dir     => $path,
                special => $path,
                type    => 'lofs',
                options => '[ro,nodevices]',
            };
        }
        else {
            push @{$res->{device}}, {
                match    => "/dev/zvol/rdsk/$path",
            };
        }
    }

    push @{$res->{net}}, {
        physical    => $_->{nic_name},
    } for @{$cfg->{nic}};

    return $res;
};

my $addOwnResources = sub {
    my $cfg     = shift;
    my $kvmName = shift;
    my $resources = $getOwnResources->($cfg, $kvmName);

    # don't add nics if network stack is not exclusive
    delete $resources->{net} if $cfg->{zone}->{'ip-type'} ne 'exclusive';

    for my $resGrp (keys %$resources) {
        for my $res (@{$resources->{$resGrp}}) {
            push @{$cfg->{zone}->{$resGrp}}, $res;
        }
    }
};

my $hashEqual = sub {
    my $hash1 = shift;
    my $hash2 = shift;
                
    return keys %$hash1 == keys %$hash2
        && keys %$hash1 == map { $hash1->{$_} && $hash2->{$_}
        && $hash1->{$_} eq $hash2->{$_} ? undef : () } keys %$hash1;
};

my $removeOwnResources = sub {
    my $cfg     = shift;
    my $kvmName = shift;
    my $resources = $getOwnResources->($cfg, $kvmName);

    for my $resGrp (keys %$resources) {
        for (my $i = $#{$cfg->{zone}->{$resGrp}}; $i >= 0; $i--) {
            for my $res (@{$resources->{$resGrp}}) {
                splice @{$cfg->{zone}->{$resGrp}}, $i, 1
                    if $hashEqual->($res, $cfg->{zone}->{$resGrp}->[$i]);
            }
        }
        # remove empty resources from config
        delete $cfg->{zone}->{$resGrp} if !@{$cfg->{zone}->{$resGrp}};
    }
};    

# constructor
sub new {
    my $class = shift;
    my $self = { @_ };

    $self->{smf}  = Illumos::SMF->new(zonesupport => 1, debug => $self->{debug});
    $self->{zone} = Illumos::Zones->new(debug => $self->{debug});
    $self->{prog} = KVMadm::Progress->new();
    # remove zonename as that will be set to kvm name
    my $schema = $SCHEMA->();
    delete $schema->{zone}->{members}->{zonename};

    $self->{cfg}  = Data::Processor->new($schema);
    return bless $self, $class
}

# public methods
sub runPath {
    return $RUN_PATH;
}

sub fmri {
    return $FMRI;
}

sub getTemplate {
    my $self = shift;

    my $zoneTemplate = $self->{zone}->template;
    delete $zoneTemplate->{zonename};

    return { %$kvmTemplate, zone => $zoneTemplate }; 
}

sub removeKVM {
    my $self    = shift;
    my $kvmName = shift;
    my $opts    = shift;

    my $config = $self->readConfig($kvmName);
    my $util   = KVMadm::Utils->new();

    my $zoneState = $self->{zone}->zoneState($kvmName);
    # don't purge zone if KVM was not set up in zone
    exists $config->{zone} || delete $opts->{zone};

    exists $opts->{zone} && $zoneState eq 'running'
        and die "ERROR: zone '$kvmName' still running. use 'kvmadm stop $kvmName' to stop it first...\n";

    for (keys %$opts) {
        /^vnic$/ && do {
            $util->purgeVnic($config);
            next;
        };
        /^zvol$/ && do {
            $util->purgeZvol($config);
            next;
        };
    }
    # purge zone last...
    if (exists $opts->{zone}) {
        $zoneState ne 'configured' && $self->{zone}->uninstallZone($kvmName);
        $self->{zone}->deleteZone($kvmName);
    }

    # no need to delete the FMRI if zone has been purged
    $opts->{zone} || $self->{smf}->deleteFMRI("$FMRI:$kvmName", $insertZone->($kvmName, $config->{zone}));
}

sub checkConfig {
    my $self = shift;
    my $config = shift;

    my $ec = $self->{cfg}->validate($config);
    $ec->count and die join ("\n", map { $_->stringify } @{$ec->{errors}}) . "\n";

    return 1;
}

sub writeConfig {
    my $self = shift;
    my $kvmName = shift;
    my $config = shift;

    $self->checkConfig($config);

    # check if run directory exists
    -d "$RUN_PATH/$kvmName" || make_path("$RUN_PATH/$kvmName", { mode => 0700 })
        or die "Cannot create directory $RUN_PATH/$kvmName\n";

    my $zConf = $config->{zone} ? 1 : 0;
    # set up zone
    if ($zConf) {
        $config->{zone}->{zonename} = $kvmName;

        # remove SMF instance from GZ if it was setup there
        $self->{smf}->deleteFMRI("$FMRI:$kvmName")
            if $self->{smf}->fmriExists("$FMRI:$kvmName");

        # add own resources
        $addOwnResources->($config, $kvmName);

        $self->{zone}->setZoneProperties($kvmName, $config->{zone});
    }
    else {
        my $zone = $self->{zone}->isGZ ? $self->{zone}->getZoneProperties($kvmName) : {};
        $self->{smf}->deleteFMRI("$FMRI:$kvmName", $insertZone->($kvmName, %$zone))
            if $zone->{zonename} && $self->{smf}->fmriExists("$FMRI:$kvmName", $insertZone->($kvmName, %$zone));
    }
    # set up system/kvm SMF template
    $zConf && !$self->{smf}->fmriExists($FMRI, $insertZone->($kvmName, $zConf)) && do {
        print "setting up system/kvm within zone. this might take a while...\n";

        my $smfTemplate = $self->{smf}->getFMRIProperties($FMRI);
        $self->{smf}->setFMRIProperties($FMRI, $smfTemplate, $insertZone->($kvmName, $zConf));
        # delete manifestfile as this will cause system/svc/restarter to delete system/kvm since file not present in zone
        $self->{smf}->deletePropertyGroup($FMRI, 'manifestfiles', $insertZone->($kvmName, $zConf));
    };

    $zConf && print "setting up SMF instance within zone. this might take a while...\n";
    $self->{prog}->init;
    $self->{prog}->progress;    

    #create instance if it does not exist
    $self->{smf}->addInstance($FMRI, $kvmName, { %{$insertZone->($kvmName, $zConf)}, enabled => $zConf })
        if !$self->{smf}->fmriExists("$FMRI:$kvmName", $insertZone->($kvmName, $zConf));

    delete $config->{zone};
    
    $self->{prog}->progress;
    #delete property group to wipe off existing config
    $self->{smf}->deletePropertyGroup("$FMRI:$kvmName", $PGRP, $insertZone->($kvmName, $zConf))
        if $self->{smf}->propertyGroupExists("$FMRI:$kvmName", $PGRP, $insertZone->($kvmName, $zConf));
    $self->{prog}->progress;
    $self->{smf}->addPropertyGroup("$FMRI:$kvmName", $PGRP, undef, $insertZone->($kvmName, $zConf));
    $self->{prog}->progress;
    $self->{smf}->refreshFMRI("$FMRI:$kvmName", $insertZone->($kvmName, $zConf));

    # write section configs
    for my $section (@{$SECTIONS->()}) {
        $self->$writeArray($kvmName, $section, $config->{$section}, $config);
        delete $config->{$section};
    }

    #write general kvm config
    $config = { map { $PGRP . '/' . $_ => $config->{$_} } keys %$config };
    $self->{prog}->progress;
    $self->{smf}->setProperties("$FMRI:$kvmName", $config, $insertZone->($kvmName, $zConf));

    $self->{smf}->refreshFMRI("$FMRI:$kvmName", $insertZone->($kvmName, $zConf));
    $self->{prog}->done;

    return 1;
}

sub readConfig {
    my $self = shift;
    my $kvmName = shift;

    my $config = {};
    my $zone   = $self->{zone}->isGZ ? $self->{zone}->getZoneProperties($kvmName) : {};
    my $properties = {};
    $config->{zone} = $zone if %$zone;

    $self->{smf}->fmriExists("$FMRI:$kvmName", $insertZone->($kvmName, %$zone)) or do {
       delete $config->{zone};
       $zone = {};
       $self->{smf}->fmriExists("$FMRI:$kvmName");
    } or die "ERROR: KVM instance '$kvmName' does not exist\n";
            
    $properties = $self->{smf}->getProperties("$FMRI:$kvmName", $PGRP,
        $insertZone->($kvmName, %$zone));

    my $sectRE = join '|', @{$SECTIONS->()};

    for my $prop (keys %$properties){
        my $value = $properties->{$prop};
        $prop =~ s|^$PGRP/||;

        for ($prop){
            /^($sectRE)(\d+)_(.+)$/ && do {
                my $sect  = $1;
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

    $config->{zone} && $removeOwnResources->($config, $kvmName);

    return $config;
}

sub listKVM {
    my $self = shift;
    my $kvmName = shift;

    my $fmris = [];
    if ($kvmName) {
        $fmris = [ "$FMRI:$kvmName" ];
    }
    else {
        my $zones = $self->{zone}->listZones;
        for my $zone (@$zones) {
            push @$fmris, @{$self->{smf}->listFMRI($FMRI, { zonename => $zone->{zonename} ne 'global'
                ? $zone->{zonename} : undef, instancesonly => 1 })};
        }
    }

    my %instances;

    for my $instance (@$fmris){
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
    push @cmdArray, '-enable-kvm';
    push @cmdArray, '-no-hpet' if !exists $config->{hpet} || $config->{hpet} !~ /^true$/i;
    push @cmdArray, ('-m', $config->{ram} // '1024');
    push @cmdArray, ('-cpu', $config->{cpu_type} // 'qemu64');
    push @cmdArray, ('-smp', $config->{vcpus} // '1');
    push @cmdArray, ('-rtc', 'base=' . ($config->{time_base} // 'utc') . ',driftfix=slew');
    push @cmdArray, ('-pidfile', "$RUN_PATH/$kvmName/$kvmName.pid");
    push @cmdArray, ('-monitor', 'unix:' . "$RUN_PATH/$kvmName/$kvmName" . '.monitor,server,nowait,nodelay');
    push @cmdArray, ('-uuid', $config->{uuid}) if $config->{uuid};
    push @cmdArray, ('-k', $config->{kb_layout}) if $config->{kb_layout};

    if (!defined $config->{vnc}){
        push @cmdArray, qw(-vga none -nographic);
    }
    elsif ($config->{vnc} =~ /^sock(?:et)?$/i){
        push @cmdArray, (qw(-vga std -vnc), 'unix:' . "$RUN_PATH/$kvmName/$kvmName.vnc"
            . ($config->{vnc_pw_file} ? ',password' : '')); 
    }
    else{
        my ($ip, $port) = $config->{vnc} =~ /^(?:(\d{1,3}(?:\.\d{1,3}){3}):)?(\d+)$/i;
        $port -= 5900 if $port >= 5900;
        push @cmdArray, (qw(-vga std -vnc), ($ip ? "$ip:" : '127.0.0.1:') . $port . ',console'
            . ($config->{vnc_pw_file} ? ',password' : '')); 
    }

    for my $disk (@{$config->{disk}}){
        $disk->{disk_path} = '/dev/zvol/rdsk/' . $disk->{disk_path}
            if (!exists $disk->{media} || $disk->{media} ne 'cdrom')
                && $disk->{disk_path} !~ m|^/dev/zvol/rdsk/|;

        push @cmdArray, ('-drive',
              'file='   . $disk->{disk_path}
            . ',if='    . ($disk->{model} // 'ide')
            . ',media=' . ($disk->{media} // 'disk')
            . ',index=' . $disk->{index}
            . ',cache=' . ($disk->{cache} // 'none')
            . ($disk->{boot} && $disk->{boot} eq 'true' ? ',boot=on' : ''));
    }
    push @cmdArray, ('-boot', 'order=' . ($config->{boot_order} ? $config->{boot_order} : 'cd'));

    for my $nic (@{$config->{nic}}){
        my $mac = $getMAC->($nic->{nic_name});

        if ($nic->{model} eq 'virtio'){
            push @cmdArray, ('-device',
                  'virtio-net-pci'
                . ',mac=' . $mac
                . ',tx=timer'
                . ',x-txtimer=' . ($nic->{txtimer} // $VIRTIO_TXTIMER_DEFAULT)
                . ',x-txburst=' . ($nic->{txburst} // $VIRTIO_TXBURST_DEFAULT)
                . ',vlan=' . ($nic->{vlan_id} // '0'));
        }
        else{
            push @cmdArray, ('-net', 'nic,vlan=' . ($nic->{vlan_id} // '0') . ',name=net'
                . $nic->{index} . ',model=' . $nic->{model} . ',macaddr=' . $mac);
        }

        push @cmdArray, ('-net', 'vnic,vlan=' . ($nic->{vlan_id} // '0') . ',name=net'
            . $nic->{index} . ',ifname=' . $nic->{nic_name});
    }

    for my $serial (@{$config->{serial}}){
        push @cmdArray, ('-chardev', 'socket,id=serial' . $serial->{index}
            . ',path=' . "$RUN_PATH/$kvmName/$kvmName" . '.' . $serial->{serial_name} . ',server,nowait');
        push @cmdArray, ('-serial', 'chardev:serial' . $serial->{index});
    }

    push @cmdArray, qw(-usb -usbdevice tablet)
        if $config->{usb_tablet} && $config->{usb_tablet} =~ /^true$/i;

    push @cmdArray, split /\s+/, $config->{qemu_extra_opts} if $config->{qemu_extra_opts};

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

sub getVNCPassword {
    my $self = shift;
    my $kvmName = shift;

    my $config = $self->readConfig($kvmName);
    $self->checkConfig($config);

    return undef if !exists $config->{vnc_pw_file};

    open my $fh, '<', $config->{vnc_pw_file}
        or die 'ERROR: cannot open vnc password file ' . $config->{vnc_pw_file} . ": $!\n";
    chomp (my $password = do { local $/; <$fh>; });
    close $fh;

    return $password;
}

sub getPreStartCmd {
    my $self = shift;
    my $kvmName = shift;

    my $config = $self->readConfig($kvmName);
    $self->checkConfig($config);

    return $config->{pre_start_cmd};
}

sub getPid {
    my $self = shift;
    my $kvmName = shift;

    my $pidfile = "$RUN_PATH/$kvmName/$kvmName.pid";

    return undef if !-f $pidfile;
    open my $fh, '<', $pidfile or return undef;
    chomp (my $pid = <$fh>);
    close $fh;

    return int($pid);
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

=head2 getVNCPassword

returns the VNC password

=head2 getPreStartCmd

return the pre_start_cmd

=head2 getPid

returns the pid of the qemu process

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

2016-02-05 had pre start cmd added
2015-04-28 had Zone support
2014-10-03 had Initial Version

=cut

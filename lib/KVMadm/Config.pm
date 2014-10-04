package KVMadm::Config;

use strict;
use warnings;

use Illumos::SMF;

# constants
my $FMRI = 'svc:/system/kvm';
my $PGRP = 'kvmadm';

#globals
my $smf;
my $kvmTemplate = {
    vcpus       => 4,
    ram         => 1024,
    time_base   => 'utc',
    disks       => [
        {
            boot        => 'true',
            model       => 'virtio',
            image_path  => '...',
            image_size  => '10G',
        }
    ],
    nics        => [
        {
            nic_tag     => '...',
            model       => 'virtio',
        }
    ],
};

sub new {
    my $class = shift;
    my $self = { @_ };

    $smf = Illumos::SMF->new(debug => $self->{debug});
    return bless $self, $class
}

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

}

sub writeConfig {
    my $self = shift;
    my $kvmName = shift;
    my $config = shift;

    $self->checkConfig;

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

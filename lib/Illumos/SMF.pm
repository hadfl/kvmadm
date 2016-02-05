package Illumos::SMF;

use strict;
use warnings;

# version
our $VERSION = '0.1.6';

# commands
my $SVCS   = '/usr/bin/svcs';
my $SVCCFG = '/usr/sbin/svccfg';
my $SVCADM = '/usr/sbin/svcadm';
my $ZLOGIN = '/usr/sbin/zlogin';

# constructor
sub new {
    my $class = shift;
    my $self = { @_ };

    # add Illumos::Zone instance if zone support is required
    $self->{zonesupport} && do {
        eval {
            require Illumos::Zones;
        };
        if ($@) {
            die "ERROR: Unable to load package Illumos::Zones.";
        }

        $self->{zone} = Illumos::Zones->new(debug => $self->{debug});
    };
    
    return bless $self, $class
}
# private methods
my $svcAdm = sub {
    my $self = shift;
    my $cmd  = shift;
    my $fmri = shift;

    my @cmd = ($SVCADM, $cmd, $fmri);

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot $cmd '$fmri'\n";
};

my $zoneCmd = sub {
    my $self     = shift;
    my $zoneName = shift;

    print STDERR "WARNING: zonename specified but 'zonesupport' not enabled for Illumos::SMF\n"
        . "use 'Illumos::SMF(zonesupport => 1)' to enable zone support\n" if $zoneName && !$self->{zone};

    return { cmd => [], shellquote => q{"} } if !$zoneName || !$self->{zone};

    my $zone = $self->{zone}->listZone($zoneName);
    if ($zone && $zone->{state} eq 'running') {
        return { cmd => [ $ZLOGIN, $zoneName ], shellquote => q{'"'} };
    }
    else {
        return { cmd => [], zpath => $zone->{zonepath}, shellquote => q{"} };
    }

    # just in case, should never reach here...
    return { cmd => [], shellquote => q{"} };
};

# public methods
sub refreshFMRI {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};
    
    my $zcmd = $self->$zoneCmd($opts->{zonename});
    my @cmd  = @{$zcmd->{cmd}};
    local $ENV{SVCCFG_REPOSITORY} = $zcmd->{zpath}
        . '/root/etc/svc/repository.db' if $zcmd->{zpath};

    push @cmd, ($SVCCFG, '-s', $fmri, 'refresh');

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot refresh FMRI '$fmri'\n";
    
    return 1;
}

sub listFMRI {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};
    my @fmris;
    
    my $zcmd = $self->$zoneCmd($opts->{zonename});
    my @cmd  = @{$zcmd->{cmd}};
    local $ENV{SVCCFG_REPOSITORY} = $zcmd->{zpath}
        . '/root/etc/svc/repository.db' if $zcmd->{zpath};
    
    $fmri ||= '*';
   
    # remove leading 'svc:/'
    $fmri =~ s/^svc:\///;

    my @cmd1 = (@cmd, $SVCCFG, 'list', $fmri);

    print STDERR '# ' . join(' ', @cmd1) . "\n" if $self->{debug};
    open my $fmris, '-|', @cmd1
        or die "ERROR: cannot get list of FMRI\n";

    while (my $elem = <$fmris>) {
        chomp $elem;
        push @fmris, "svc:/$elem" if !$opts->{instancesonly};
        
        my @cmd2 = (@cmd, $SVCCFG, '-s', $elem, 'list');

        open my $instances, '-|', @cmd2
            or die "ERROR: cannot get instances of '$elem'\n";

        while (<$instances>) {
            chomp;
            next if /:properties/;
            push @fmris, "svc:/$elem:$_";
        }
        close $instances;
    }

    return [ @fmris ];
}

sub fmriExists {
    my $self = shift;
    my $fmri = shift;
    my $opts = shift;

    # remove instance name
    my ($baseFmri) = $fmri =~ /^((?:svc:)?[^:]+)/;

    return grep { $fmri eq $_ } @{$self->listFMRI($baseFmri, $opts)};
}

sub fmriState {
    my $self = shift;
    my $fmri = shift;
    my $opts = shift;

    my @cmd = ($SVCS, $opts->{zonename} ? ('-z', $opts->{zonename}) : (), qw(-H -o state), $fmri);

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    open my $fmris, '-|', @cmd
        or die "ERROR: cannot get list of FMRI\n";

    chomp(my $state = <$fmris>);
    return $state;
}

sub fmriOnline {
    my $self = shift;
    
    return $self->fmriState(shift, shift) eq 'online';
}

sub enable {
    my $self = shift;
    my $fmri = shift;

    $self->$svcAdm('enable', $fmri);
}

sub disable {
    my $self = shift;
    my $fmri = shift;

    $self->$svcAdm('disable', $fmri);
}

sub restart {
    my $self = shift;
    my $fmri = shift;

    $self->$svcAdm('restart', $fmri);
}

sub addFMRI {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};

    my $zcmd = $self->$zoneCmd($opts->{zonename});
    my @cmd  = @{$zcmd->{cmd}};
    local $ENV{SVCCFG_REPOSITORY} = $zcmd->{zpath}
        . '/root/etc/svc/repository.db' if $zcmd->{zpath};

    # remove leading 'svc:/'
    $fmri =~ s/^svc:\///;

    push @cmd, ($SVCCFG, 'add', $fmri);

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot add '$fmri'\n";
}

sub deleteFMRI {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};

    my $zcmd = $self->$zoneCmd($opts->{zonename});
    my @cmd  = @{$zcmd->{cmd}};
    local $ENV{SVCCFG_REPOSITORY} = $zcmd->{zpath}
        . '/root/etc/svc/repository.db' if $zcmd->{zpath};

    push @cmd, ($SVCCFG, 'delete', $fmri);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot delete $fmri\n";
}

sub addInstance {
    my $self = shift;
    my $fmri = shift;
    my $instance = shift;
    my $opts = $_[0] // {};

    my $zcmd = $self->$zoneCmd($opts->{zonename});
    my @cmd  = @{$zcmd->{cmd}};
    local $ENV{SVCCFG_REPOSITORY} = $zcmd->{zpath}
        . '/root/etc/svc/repository.db' if $zcmd->{zpath};

    push @cmd, ($SVCCFG, '-s', $fmri, 'add', $instance);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot add instance '$instance' to $fmri\n";

    $self->addPropertyGroup("$fmri:$instance", 'general', 'framework', $opts);
    $self->setProperty("$fmri:$instance", 'general/complete', $instance, undef, $opts);
    $self->setProperty("$fmri:$instance", 'general/enabled',
        $opts->{enabled} ? 'true' : 'false', undef, $opts);
}

sub getPropertyGroups {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};

    my $zcmd = $self->$zoneCmd($opts->{zonename});
    my @cmd  = @{$zcmd->{cmd}};
    local $ENV{SVCCFG_REPOSITORY} = $zcmd->{zpath}
        . '/root/etc/svc/repository.db' if $zcmd->{zpath};

    my $pg = [];
    push @cmd, ($SVCCFG, '-s', $fmri, 'listpg');

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    open my $props, '-|', @cmd
        or die "ERROR: cannot get property group of FMRI '$fmri'\n";

    while (my $prop = <$props>){
        chomp $prop;
        my ($name, $type) = split /\s+/, $prop, 2;
        push @$pg, $name; 
    }
    
    return $pg;
}

sub propertyExists {
    my $self = shift;
    my $fmri = shift;
    my $property = shift;
    my $opts = shift;
    
    # extract property group
    my ($pg) = $property =~ /^([^\/]+)/;

    return grep { $property eq $_ } keys %{$self->getProperties($fmri, $pg, $opts)};
}

sub propertyGroupExists {
    my $self = shift;
    my $fmri = shift;
    my $pg   = shift;
    my $opts = shift;

    return grep { $pg eq $_ } @{$self->getPropertyGroups($fmri, $opts)};
}

sub addPropertyGroup {
    my $self = shift;
    my $fmri = shift;
    my $pg   = shift;
    my $type = shift;
    my $opts = $_[0] // {};
    
    my $zcmd = $self->$zoneCmd($opts->{zonename});
    my @cmd  = @{$zcmd->{cmd}};
    local $ENV{SVCCFG_REPOSITORY} = $zcmd->{zpath}
        . '/root/etc/svc/repository.db' if $zcmd->{zpath};
    
    # set type to application if not specified
    $type //= 'application';

    return if $self->propertyGroupExists($fmri, $pg, $opts);

    push @cmd, ($SVCCFG, '-s', $fmri, 'addpg', $pg, $type);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot add property group to $fmri\n";
}

sub deletePropertyGroup {
    my $self = shift;
    my $fmri = shift;
    my $pg   = shift;
    my $opts = $_[0] // {};
    
    my $zcmd = $self->$zoneCmd($opts->{zonename});
    my @cmd  = @{$zcmd->{cmd}};
    local $ENV{SVCCFG_REPOSITORY} = $zcmd->{zpath}
        . '/root/etc/svc/repository.db' if $zcmd->{zpath};
        
    push @cmd, ($SVCCFG, '-s', $fmri, 'delpg', $pg);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot delete property group from $fmri\n";
}

sub setProperty {
    my $self = shift;
    my $fmri = shift;
    my $property = shift;
    my $value = shift;
    my $type  = shift;
    my $opts = $_[0] // {};
    
    my $zcmd = $self->$zoneCmd($opts->{zonename});
    my @cmd  = @{$zcmd->{cmd}};
    local $ENV{SVCCFG_REPOSITORY} = $zcmd->{zpath}
        . '/root/etc/svc/repository.db' if $zcmd->{zpath};

    # guess property type if not provided
    $type || do {
        $type = 'astring';

        for ($value){
            /^\d+$/ && do {
                $type = 'count';
                last;
            };

            /^(?:true|false)$/i && do {
                $type = 'boolean';
                last;
            };
        }
    };

    push @cmd, $self->propertyExists($fmri, $property, $opts) ?
        ($SVCCFG, '-s', $fmri, 'setprop', $property, '=',
            $zcmd->{shellquote} . $value . $zcmd->{shellquote})
        : ($SVCCFG, '-s', $fmri, 'addpropvalue', $property, "$type:",
            $zcmd->{shellquote} . $value . $zcmd->{shellquote});
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot set property $property of $fmri\n";
}

sub setProperties {
    my $self = shift;
    my $fmri = shift;
    my $properties = shift;
    my $opts = shift;

    for my $key (keys %$properties){
        $self->setProperty($fmri, $key, $properties->{$key}, undef, $opts)
    }
}

sub getProperties {
    my $self = shift;
    my $fmri = shift;
    my $pg   = shift;
    my $opts = $_[0] // {};
    
    my $zcmd = $self->$zoneCmd($opts->{zonename});
    my @cmd  = @{$zcmd->{cmd}};
    local $ENV{SVCCFG_REPOSITORY} = $zcmd->{zpath}
        . '/root/etc/svc/repository.db' if $zcmd->{zpath};

    my $properties = {};

    push @cmd, ($SVCCFG, '-s', $fmri, 'listprop', $pg);

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    open my $props, '-|', @cmd
        or die "ERROR: cannot get properties of FMRI '$fmri'\n";

    while (<$props>){
        chomp;
        my ($name, $type, $value) = split /\s+/, $_, 3;
        next if $name eq $pg;
        #remove quotes
        $value =~ s/^"|"$//g;
        $properties->{$name} = $value;

    }
    
    return $properties;
}

sub setFMRIProperties {
    my $self       = shift;
    my $fmri       = shift;
    my $properties = shift;
    my $opts = $_[0] // {};
    
    $self->addFMRI($fmri, $opts) if !$self->fmriExists($fmri, $opts);
    # extract property groups
    my @pg = map { $properties->{$_}->{members} ? $_ : () } keys %$properties;

    for my $pg (@pg) {
        $self->addPropertyGroup($fmri, $pg, $properties->{$pg}->{type}, $opts);
        for my $prop (keys %{$properties->{$pg}->{members}}) {
            $self->setProperty($fmri, "$pg/$prop",
                $properties->{$pg}->{members}->{$prop}->{value},
                $properties->{$pg}->{members}->{$prop}->{type},
                $opts);
        }
        delete $properties->{$pg};
    }

    for my $prop (keys %$properties) {
        $self->setProperty($fmri, $prop,
            $properties->{$prop}->{value},
            $properties->{$prop}->{type},
            $opts);
    }
}

sub getFMRIProperties {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};
    
    my $zcmd = $self->$zoneCmd($opts->{zonename});
    my @cmd  = @{$zcmd->{cmd}};
    local $ENV{SVCCFG_REPOSITORY} = $zcmd->{zpath}
        . '/root/etc/svc/repository.db' if $zcmd->{zpath};

    my $properties = {};

    push @cmd, ($SVCCFG, '-s', $fmri, 'listprop');

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    open my $props, '-|', @cmd
        or die "ERROR: cannot get properties of FMRI\n";

    while (<$props>) {
        chomp;
        my ($pg, $prop, $type, $value) = /^(?:([-\w]+)\/)?([-\w]+)\s+([-\w]+)(?:\s+(.+))?$/;
        next if !$prop || !$type;
        # remove quotes from $value
        $value =~ s/^"|"$//g if $value;
        if ($pg) {
            $properties->{$pg}->{members}->{$prop}->{type} = $type;
            $properties->{$pg}->{members}->{$prop}->{value} = $value;
        }
        else {
            $properties->{$prop}->{type} = $type;
            $properties->{$prop}->{value} = $value // '';
        }
    }

    return $properties;
}

1;

__END__

=head1 NAME

Illumos::SMF - SMF control object

=head1 SYNOPSIS

 use Illumos::SMF;
 ...
 my $smf = Illumos::SMF->new(zonesupport => 1, debug => 0);
 ...

=head1 DESCRIPTION

object to manage SMF

=head1 ATTRIBUTES

=head2 zonesupport

if enabled, SMF can handle FMRI in zones (requires C<Illumos::Zones>)

=head2 debug

print debug information to STDERR

=head1 METHODS

=head2 refreshFMRI

refreshs the instance

 $smf->refreshFMRI();

=head2 listFMRI

lists all child entities of a FMRI. lists instances only if 'instancesonly' is set.

 $smf->listFMRI($fmri, { zonename => $zone, instancesonly => 1 });
 $smf->listFMRI($fmri, { instancesonly => 1 });

=head2 fmriExists

checks if the FMRI exists

 $smf->fmriExists($fmri, { zonename => $zone }); 
 $smf->fmriExists($fmri);

=head2 fmriState

returns the state of the FMRI

 $smf->fmriState($fmri, { zonename => $zone });
 $smf->fmriState($fmri);

=head2 fmriOnline

checks if the FRMI is online

 $smf->fmriOnline($fmri, { zonename => $zone });
 $smf->fmriOnline($fmri);

=head2 enable

enables the FMRI

 $smf->enable($fmri, { zonename => $zone });
 $smf->enable($fmri);

=head2 disable

disables the FMRI

 $smf->disable($fmri, { zonename => $zone });
 $smf->disable($fmri);

=head2 restart

restarts the FMRI

 $smf->restart($fmri, { zonename => $zone });
 $smf->restart($fmri);

=head2 addFMRI

adds an FMRI to SFM

 $smf->addFMRI($fmri, { zonename => $zone });
 $smf->addFMRI($fmri);

=head2 deleteFMRI

removes an FMRI from SMF

 $smf->deleteFMRI($fmri, { zonename => $zone });
 $smf->deleteFMRI($fmri);

=head2 addInstance

adds an instance to an existing FMRI

 $smf->addInstance($fmri, $instance, { zonename => $zone });
 $smf->addInstance($fmri, $instance);

=head2 getPropertyGroups

returns a list of property groups

 $smf->getPropertyGroups($fmri, { zonename => $zone });
 $smf->addInstance($fmri);

=head2 propertyExists

returns whether a property exists or not

 $smf->propertyExists($fmri, $prop, { zonename => $zone });
 $smf->propertyExists($fmri, $prop);

=head2 propertyGroupExists

returns whether a property group exists or not

 $smf->propertyGroupExists($fmri, $pg, { zonename => $zone });
 $smf->propertyGroupExists($fmri, $pg);

=head2 addPropertyGroup

adds a property group to a FMRI. C<$type> defaults to 'application'
if not given.

 $smf->addPropertyGroup($fmri, $pg, $type, { zonename => $zone });
 $smf->addPropertyGroup($fmri, $pg, $type);

=head2 deletePropertyGroup

deletes a property group from a FMRI

 $smf->deletePropertyGroup($fmri, $pg, { zonename => $zone });
 $smf->deletePropertyGroup($fmri, $pg);

=head2 setProperty

sets a property of a FMRI. C<$type> is guessed if not given.

 $smf->setProperty($fmri, $prop, $value, $type, { zonename => $zone });
 $smf->setProperty($fmri, $prop, $value, $type);

=head2 setProperties

sets a set of properties of a property group of a FMRI

 $smf->setProperties($fmri, { %props }, { zonename => $zone });
 $smf->setProperties($fmri, { %props }, $type);

=head2 getProperties

gets the set of properties of a property group of a FMRI

 $smf->getProperties($fmri, $pg, { zonename => $zone });
 $smf->getProperties($fmri, $pg, $type);

=head2 setFMRIProperties

sets all properties of a FMRI

 $smf->setFMRIProperties($fmri, { %props }, { zonename => $zone });
 $smf->setFMRIProperties($fmri, { %props });

=head2 getFMRIProperties

gets all properties of a FMRI

 $smf->getFMRIProperties($fmri, { zonename => $zone });
 $smf->getFMRIProperties($fmri);

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

2015-05-07 had Initial Version

=cut

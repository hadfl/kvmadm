package Illumos::SMF;

use strict;
use warnings;

# commands
my $SVCS    = '/usr/bin/svcs';
my $SVCCFG  = '/usr/sbin/svccfg';

# constructor
sub new {
    my $class = shift;
    my $self = { @_ };
    return bless $self, $class
}

# public methods
sub refreshFMRI {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};
    
    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};

    my @cmd = ($SVCCFG, '-s', $fmri, 'refresh');

    system(@cmd) and die "ERROR: cannot refresh FMRI '$fmri'\n";
    
    return 1;
}

sub listFMRI {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};
    my @fmris;
    
    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};
    
    $fmri ||= '*';
   
    # remove leading 'svc:/'
    $fmri =~ s/^svc:\///;

    my @cmd = ($SVCCFG, 'list', $fmri);

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    open my $fmris, '-|', @cmd
        or die "ERROR: cannot get list of FMRI\n";

    while (my $elem = <$fmris>) {
        chomp $elem;
        push @fmris, "svc:/$elem" if !$opts->{instancesonly};
        
        my @cmd2 = ($SVCCFG, '-s', $elem, 'list');

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

sub addFMRI {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};

    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};

    # remove leading 'svc:/'
    $fmri =~ s/^svc:\///;

    my @cmd = ($SVCCFG, 'add', $fmri);

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot add '$fmri'\n";
}

sub deleteFMRI {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};

    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};

    my @cmd = ($SVCCFG, 'delete', $fmri);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot delete $fmri\n";
}

sub addInstance {
    my $self = shift;
    my $fmri = shift;
    my $instance = shift;
    my $opts = $_[0] // {};

    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};

    my @cmd = ($SVCCFG, '-s', $fmri, 'add', $instance);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot add instance '$instance' to $fmri\n";

    $self->addPropertyGroup("$fmri:$instance", 'general', 'framework');
    $self->setProperty("$fmri:$instance", 'general/complete', $instance);
    $self->setProperty("$fmri:$instance", 'general/enabled',
        $opts->{enabled} ? 'true' : 'false');
}

sub getPropertyGroups {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};

    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};

    my $pg = [];
    my @cmd = ($SVCCFG, '-s', $fmri, 'listpg');

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
    
    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};
    
    # set type to application if not specified
    $type //= 'application';

    return if $self->propertyGroupExists($fmri, $pg, $opts);

    my @cmd = ($SVCCFG, '-s', $fmri, 'addpg', $pg, $type);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot add property group to $fmri\n";
}

sub deletePropertyGroup {
    my $self = shift;
    my $fmri = shift;
    my $pg   = shift;
    my $opts = $_[0] // {};
    
    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};
        
    my @cmd = ($SVCCFG, '-s', $fmri, 'delpg', $pg);
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
    
    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};

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

    my @cmd = $self->propertyExists($fmri, $property, $opts) ?
        ($SVCCFG, '-s', $fmri, 'setprop', $property, '=', "\"$value\"")
        : ($SVCCFG, '-s', $fmri, 'addpropvalue', $property, "$type:", "\"$value\"");
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
    
    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};

    my $properties = {};

    my @cmd = ($SVCCFG, '-s', $fmri, 'listprop', $pg);

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

sub getSMFProperties {
    my $self = shift;
    my $fmri = shift;
    my $opts = $_[0] // {};
    
    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};

    my $properties = {};

    my @cmd = ($SVCCFG, '-s', $fmri, 'listprop');

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

sub setSMFProperties {
    my $self       = shift;
    my $fmri       = shift;
    my $properties = shift;
    my $opts = $_[0] // {};
    
    local $ENV{SVCCFG_REPOSITORY} = $opts->{zonepath}
        . '/root/etc/svc/repository.db' if $opts->{zonepath};

    $self->addFMRI($fmri, $opts) if !$self->fmriExists($fmri, $opts);
    # extract property groups
    my @pg = map { $properties->{$_}->{members} ? $_ : () } keys $properties;

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

1;

__END__

=head1 NAME

Illumos::SMF - SMF control object

=head1 SYNOPSIS

use Illumos::SMF;
...
my $smf = Illumos::SMF->new(debug=>0);
...

=head1 DESCRIPTION

object to manage SMF

=head1 ATTRIBUTES

=head2 debug

print debug information to STDERR

=head1 METHODS

=head2 refreshFMRI

refreshs the instance

=head2 listFMRI

lists instances of a FMRI

=head2 fmriExists

checks if the FMRI exists

=head2 fmriState

returns the state of the FMRI

=head2 fmriOnline

checks if the FRMI is online

=head2 propertyExists

checks whether a property or property group exists or not

=head2 addInstance

adds an instance to an existing FMRI

=head2 deleteFMRI

removes an FMRI from SMF

=head2 addPropertyGroup

adds a property group to a FMRI

=head2 deletePropertyGroup

deletes a property group from a FMRI

=head2 setProperty

sets a property of a FMRI

=head2 setProperties

sets a set of properties of a property group of a FMRI

=head2 getProperty

gets a property value of a FMRI

=head2 getProperties

gets a set of properties of a property group of a FMRI

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

2015-04-26 had zone support added
2014-12-15 had FMRI online/state added
2014-10-03 had Initial Version

=cut

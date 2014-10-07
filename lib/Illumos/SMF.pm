package Illumos::SMF;

use strict;
use warnings;

# commands
my $SVCS    = '/usr/bin/svcs';
my $SVCADM  = '/usr/sbin/svcadm';
my $SVCCFG  = '/usr/sbin/svccfg';
my $SVCPROP = '/usr/bin/svcprop'; 

# constructor
sub new {
    my $class = shift;
    my $self = { @_ };
    return bless $self, $class
}

# private methods
my $refreshFMRI = sub {
    my $self = shift;
    my $fmri = shift;

    my @cmd = ($SVCADM, 'refresh', $fmri);

    system(@cmd) and die "ERROR: cannot refresh FMRI '$fmri'\n";
    
    return 1;
};

# public methods
sub listFMRI {
    my $self = shift;
    my $fmri = shift;

    my @cmd = ($SVCS, qw(-H -o fmri), $fmri);

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    open my $fmris, '-|', @cmd
        or die "ERROR: cannot get list of FMRI\n";

    my @fmris = <$fmris>;
    chomp(@fmris);

    return @fmris;
}

sub fmriExists {
    my $self = shift;
    my $fmri = shift;

    my @fmris = $self->listFMRI($fmri);

    return grep { $fmri eq $_ } @fmris;
}

sub propertyExists {
    my $self = shift;
    my $fmri = shift;
    my $property = shift;

    my @cmd = ($SVCPROP, qw(-q -p), $property, $fmri);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    return !system(@cmd);
}

sub addInstance {
    my $self = shift;
    my $fmri = shift;
    my $instance = shift;

    my @cmd = ($SVCCFG, '-s', $fmri, 'add', $instance);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot add instance '$instance' to $fmri\n";

    $self->addPropertyGroup("$fmri:$instance", 'general', 'framework');
    $self->setProperty("$fmri:$instance", 'general/complete', $instance);
    $self->setProperty("$fmri:$instance", 'general/enabled', 'false');

    $self->$refreshFMRI("$fmri:$instance");

    return 1;
}

sub deleteFMRI {
    my $self = shift;
    my $fmri = shift;

    my @cmd = ($SVCCFG, 'delete', $fmri);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot delete $fmri\n";

    return 1;
}

sub addPropertyGroup {
    my $self = shift;
    my $fmri = shift;
    my $pg = shift;
    my $type = $_[0] // 'application';

    my @cmd = ($SVCCFG, '-s', $fmri, 'addpg', $pg, $type);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot add property group to $fmri\n";

    $self->$refreshFMRI($fmri);

    return 1;
}

sub setProperty {
    my $self = shift;
    my $fmri = shift;
    my $property = shift;
    my $value = shift;

    #properties are stored as string per default
    my $type = 'astring';

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

    my @cmd = $self->propertyExists($fmri, $property) ?
        ($SVCCFG, '-s', $fmri, 'setprop', $property, '=', $value)
        : ($SVCCFG, '-s', $fmri, 'addpropvalue', $property, "$type:", $value);
    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    system(@cmd) and die "ERROR: cannot set property $property of $fmri\n";

    $self->$refreshFMRI($fmri);

    return 1;
}

sub setProperties {
    my $self = shift;
    my $fmri = shift;
    my $properties = shift;

    for my $key (keys %$properties){
        $self->setProperty($fmri, $key, $properties->{$key})
    }

    $self->$refreshFMRI($fmri);

    return 1;
}

sub getProperty {
    my $self = shift;
    my $fmri = shift;
    my $property = shift;

    my @cmd = ($SVCPROP, '-p', $property, $fmri);

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    open my $props, '-|', @cmd
        or die "ERROR: cannot get property of FMRI\n";

    my $value = <$props>;
    chomp $value;

    return $value;
}

sub getProperties {
    my $self = shift;
    my $fmri = shift;
    my $propGroup = shift;

    my $properties = {};

    my @cmd = ($SVCPROP, '-p', $propGroup, $fmri);

    print STDERR '# ' . join(' ', @cmd) . "\n" if $self->{debug};
    open my $props, '-|', @cmd
        or die "ERROR: cannot get properties of FMRI\n";

    while(my $prop = <$props>){
        chomp $prop;
        my ($name, $type, $value) = split /\s+/, $prop, 3;
        $properties->{$name} = $value;

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
my $smf = Illumos::SMF->new(debug=>0);
...

=head1 DESCRIPTION

object to manage SMF

=head1 ATTRIBUTES

=head2 debug

print debug information to STDERR

=head1 METHODS

=head2 listFMRI

lists instances of a FMRI

=head2 fmriExists

checks if the FMRI exists

=head2 propertyExists

checks whether a property or property group exists or not

=head2 addInstance

adds an instance to an existing FMRI

=head2 deleteFMRI

removes an FMRI from SMF

=head2 addPropertyGroup

adds a property group to a FMRI

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

2014-10-03 had Initial Version

=cut

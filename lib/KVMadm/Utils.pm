package KVMadm::Utils;

use strict;
use warnings;

use Illumos::SMF;

my $FMRI = 'svc:/system/kvm';
my $ZFS  = '/usr/sbin/zfs';

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

sub disk_media {
    return grep { $_[0] eq $_ } qw(disk cdrom);
}

sub disk_size {
    return shift =~ /^\d+[bkmgtp]$/i;
}

sub time_base {
    return grep { $_[0] eq $_ } qw(utc localtime);
}

sub zvolExists {
    my $value = shift;

    my @cmd = ($ZFS, qw(list -H -t volume -o name));
    open my $zvols, '-|', @cmd
        or die "ERROR: cannot list zvols\n";

    my @zvols = <$zvols>;
    chomp(@zvols);

    return grep { $value eq $_ } @zvols;
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

=head2 disk_media

checks if the disk media is 'disk' or 'cdrom'

=head2 disk_size

checks if the disk size is valid

=head2 time_base

checks if timebase is 'utc' or 'localtime'

=head2 hostname_unique

checks if the hostname is unique

=head2 zvolExists

checks if a zvol exists

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

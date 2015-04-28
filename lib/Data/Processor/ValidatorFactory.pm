use 5.10.1;
use strict;
use warnings;
package Data::Processor::ValidatorFactory;

=head1 NAME

Data::Processor::ValidatorFactory - create validators for use in schemas

=head1 SYNOPSIS

 use Data::Processor::ValidatorFactory;

 my $vf = Data::Processor::ValidatorFactory->new;

 my $SCHEMA = {
    log => {
        validator => $vf->file('>','writing'),
    },
    name => {
        validator => $vf->rx(qr{[A-Z]+},'expected name made up from capital letters')
    },
    mode => {
        validator => $vf->any(qw(UP DOWN))
    }
 }

=head1 DESCRIPTION

The ValidatorFactory lets you create falidator functions for use in L<Data::Processor> schemas.

=head1 METHODS

=head2 new

create an instance of the factory

=cut

sub new {
    my $class  = shift;
    my $self = { };
    bless ($self, $class);
    return $self;
}

=head2 file($operation,$message)

use the three parameter open to access the 'value' of if this does not work
return $message followed by the filename and the errormessage

 $vf->file('<','reading');
 $vf->file('>>','appending to');

=cut

sub file {
    my $self = shift;
    my $op = shift;
    my $msg = shift;
    return sub {
        my $file = shift;
        open my $fh, $op, $file and return undef;
        return "$msg $file: $!";
    }
}

=head2 dir()

check if the given directory exists

 $vf->dir();

=cut

sub dir {
    my $self = shift;
    return sub {
        my $value = shift;
        return undef if -d $value;
        return "directory $value does not exist";
    }
}

=head2 rx($rx,$message)

apply the regular expression to the value and return $message if it does
not match.

 $vf->rx(qr{[A-Z]+},'use uppercase letters')

=cut

sub  rx {
    my $self = shift;
    my $rx = shift;
    my $msg = shift;
    return sub {
        my $value = shift;
        if ($value =~ /$rx/){
            return undef;
        }
        return "$msg ($value)";
    }
}

=head2 any(@list)

value must be one of the values of the @list

 $vf->any(qw(ON OFF))

=cut

sub any {
    my $self = shift;
    my $array = [ @_ ];
    my %hash = ( map { $_ => 1 } @$array );
    return sub {
        my $value = shift;
        if ($hash{$value}){
            return undef;
        }
        return "expected one a value from the list: ".join(', ',@$array);
    }
};

=head1 COPYRIGHT

Copyright (c) 2015 by OETIKER+PARTNER AG. All rights reserved.

=head1 AUTHOR

Tobias Oetiker E<lt>tobi@oetiker.chE<gt>

=head1 LICENCE

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See L<perlartistic>.


=cut
1;

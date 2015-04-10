use 5.10.1;
use strict;
use warnings;
package Data::Processor::Error::Collection;
use Carp;
use Data::Processor::Error::Instance;

=head1 NAME
Data::Processor::Error::Collection - Collect errors for Data::Processor

=head1 METHODS
=head2 new

    my $errors = Data::Processor::Error::Collection->new();

=cut
sub new {
    my $class = shift;
    my $self = {
        errors => [] # the error instances are going into here
    };
    bless ($self, $class);
    return $self;
}

=head2 add
Adds an error.
parameters:
- message
- path
=cut
sub add {
    my $self = shift;
    my %p    = @_;
    my $error = Data::Processor::Error::Instance->new(%p);
    push @{$self->{errors}}, $error;
}

=head2 add_error
Adds an error object
=cut
sub add_error {
    my $self = shift;
    my $e    = shift;
    push @{$self->{errors}}, $e;
}

=head2 add_collection
Adds another error collection
=cut
sub add_collection{
    my $self  = shift;
    my $other = shift;
    my @e = $other->as_array();
    for (@e){
        $self->add_error($_);
    }

}

=head2 any_error_contains
Return true if any of the collected errors contains a given string.
  $error->collection->any_error_contains(
            string => "error_msg",
            field  => "message", # any of the data fields of an error
  );
=cut
sub any_error_contains {
    my $self = shift;
    my %p    = @_;
    for ('string', 'field'){
        croak "cannot check for errors without '$_'"
            unless $p{$_};
    }
    for my $error (@{$self->{errors}}){
        return 1 if $error->{$p{field}} =~ /$p{string}/;
    }
}

=head2 as_array
Return all collected errors as an array.
=cut
sub as_array {
    my $self = shift;
    return @{$self->{errors}};
}

=head2 count
Return count of errors.
=cut
sub count {
    my $self = shift;
    return scalar @{$self->{errors}};
}
1;


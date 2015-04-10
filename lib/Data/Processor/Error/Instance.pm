use 5.10.1;
use strict;
use warnings;
package Data::Processor::Error::Instance;

# An error.
# Always use throug Error::Collection to get correct caller info

use overload ('""' => \&stringify);

sub new {
    my $class = shift;
    my $self = { @_ };
    my %keys  = ( map { $_ => 1 } keys %$self );
    for (qw (message path)){
        delete $keys{$_};
        $self->{$_} // die "$_ missing";
    }
    die "Unknown keys ". join (",",keys %keys) if keys %keys;

    # keeping the array and store the message at its location
    $self->{path_array} = $self->{path};
    $self->{path} = join '->', @{$self->{path}};


    my (undef, undef, $line) = caller(2);
    my (undef, undef, undef, $sub) = caller(3);
    $self->{caller} = "$sub line $line";

    bless ($self, $class);
    return $self;
}

sub stringify {
    my $self = shift;
    return $self->{path}. ": " . $self->{message};
}

1;

package KVMadm::Progress;

use strict;
use warnings;

# constructor
sub new {
    my $class = shift;
    my $self = { @_ };

    $self->{state} = 'idle';
    $self->{chars} = [ qw(- \ | /) ];

    return bless $self, $class
}

sub init {
    my $self = shift;

    $self->{state} = 0;
}

sub done {
    my $self = shift;

    print "\b";
    $self->{state} = 'idle';
}

sub progress {
    my $self = shift;

    # just in case if someone calls progress w/o init first
    $self->{state} =~ /^\d$/ || $self->init;

    $self->{state} %= @{$self->{chars}};
    print "\b$self->{chars}->[$self->{state}++]";
}

1;


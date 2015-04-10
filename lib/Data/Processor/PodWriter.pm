use 5.10.1;
use strict;
use warnings;
package Data::Processor::PodWriter;

# writes pod for a schema given.

sub pod_write{
    my $schema     = shift;
    my $pod_string = shift;
    for my $key (sort keys %{$schema}){
        $pod_string .= $key;
        $pod_string .= " (optional)"
            if $schema->{$key}->{optional};
        $pod_string .= ": $schema->{$key}->{description}"
            if $schema->{$key}->{description};
        $pod_string .= "\n\nDefault value: $schema->{$key}->{default}"
            if $schema->{$key}->{default};
        $pod_string .= "\n\n";
        if ($schema->{$key}->{members}){
            $pod_string .= "$key has the following members:\n\n";
            $pod_string .= "=over\n\n";
            $pod_string .= pod_write($schema->{$key}->{members}, '');
            $pod_string .= "=back\n\n";
        }
    }
    return $pod_string;
}

1

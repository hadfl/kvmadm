use 5.10.1;
use strict;
use warnings;
package Data::Processor::Generator;

# make template: recursive tree traversal
sub make_data_template{
    my $schema_section = shift;

    my $data = {};

    for my $key (sort keys %{$schema_section}){

        # data keys always are hashes in schema.
        if (ref $schema_section->{$key} eq ref {} ){
            if ($key eq 'members'){
                # "members" indicates children but is not written in data
                return make_data_template(
                    $schema_section->{$key},
                );
            }
            else{
                if (exists $schema_section->{$key}->{description}){
                    $data->{$key} = $schema_section->{$key}->{description}
                }

                if (exists $schema_section->{$key}->{value}){
                    $data->{$key} .= $schema_section->{$key}->{value};
                }

                # we guess that if a section does not have a value
                # we might be interested in entering into it, too
                # Inversely, if there is a value, it is an end-point.
                if (! exists  $schema_section->{$key}->{value}){
                    $data->{$key} = make_data_template(
                        $schema_section->{$key},
                    );
                }
            }
        }
    }
    return $data;
}


1

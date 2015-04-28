use 5.10.1;
use strict;
use warnings;
package Data::Processor::Validator;
use Data::Processor::Error::Collection;
use Data::Processor::Transformer;

use Carp;

# XXX document this with pod. (if standalone)

# Data::Processor::Validator - Validate Data Against a Schema

sub new {
    my $class  = shift;
    my $schema = shift;
    my %p      = @_;
    my $self = {
        schema => $schema  // croak ('cannot validate without "schema"'),
        data   => $p{data} // undef,
        verbose=> $p{verbose} // undef,
        errors => $p{errors}  // Data::Processor::Error::Collection->new(),
        depth       => $p{depth} // 0,
        indent      => $p{indent} // 4,
        parent_keys => $p{parent_keys} // ['root'],
        transformer => Data::Processor::Transformer->new(),

    };
    bless ($self, $class);
    return $self;
}

# (recursively) checks data, or a section thereof;
# by instantiatin D::P::V objects and calling validate on them

sub validate {
    my $self = shift;
    $self->{data} = shift;
    croak ('cannot validate without "data"') unless $self->{data};
    $self->{errors} = Data::Processor::Error::Collection->new();

    $self->_add_defaults();

    for my $key (keys %{$self->{data}}){
        $self->explain (">>'$key'");

        # the shema key is ?
        # from here we know to have a "twin" key $schema_key in the schema
        my $schema_key = $self->_schema_twin_key($key) or next;

        # transformer (transform first)
        my $e = $self->{transformer}->transform($key,$schema_key, $self);
        $self->error($e) if $e;

        # now validate
        $self->__value_is_valid( $key );
        $self->__validator_returns_undef($key, $schema_key);


        # skip if explicitly asked for
        if ($self->{schema}->{$schema_key}->{no_descend_into}){
            $self->explain (
                ">>skipping '$key' because schema explicitly says so.\n");
            next;
        }
        # skip data branch if schema key is empty.
        if (! %{$self->{schema}->{$schema_key}}){
            $self->explain (">>skipping '$key' because schema key is empty\n'");
            next;
        }
        if (! $self->{schema}->{$schema_key}->{members}){
            $self->explain (
                ">>not descending into '$key'. No members specified\n"
            );
            next;
        }

        # recursion if we reach this point.
        $self->explain (">>descending into '$key'\n");

        if (ref $self->{data}->{$key} eq ref {} ){
            $self->explain
                (">>'$key' is not a leaf and we descend into it\n");
            my $e = Data::Processor::Validator->new(
                $self->{schema}->{$schema_key}->{members},
                parent_keys => [@{$self->{parent_keys}}, $key],
                depth       => $self->{depth}+1,
                verbose     => $self->{verbose},

            ) ->validate($self->{data}->{$key});
            $self->{errors}->add_collection($e);

        }
        elsif ((ref $self->{data}->{$key} eq ref [])
            && $self->{schema}->{$schema_key}->{array}){

            $self->explain(
            ">>'$key' is an array reference so we check all elements\n");
            for my $member (@{$self->{data}->{$key}}){
                my $e = Data::Processor::Validator->new(
                    $self->{schema}->{$schema_key}->{members},
                    parent_keys => [@{$self->{parent_keys}}, $key],
                    depth       => $self->{depth}+1,
                    verbose     => $self->{verbose},

                ) ->validate($member);
                $self->{errors}->add_collection($e);
            }
        }
        # Make sure that key in data is a leaf in schema.
        # We cannot descend into a non-existing branch in data
        # but it might be required by the schema.
        else {
            $self->explain(">>checking data key '$key' which is a leaf..");
            if ($self->{schema}->{$schema_key}->{members}){
                $self->explain("but schema requires members.\n");
                $self->error("'$key' should have members");
            }
            else {
                $self->explain("schema key is also a leaf. ok.\n");
            }
        }
    }
    # look for missing non-optional keys in schema
    # this is only done on this level.
    # Otherwise "mandatory" inherited "upwards".
    $self->_check_mandatory_keys();
    return $self->{errors};
}

#################
# internal methods
#################

# add an error
sub error {
    my $self = shift;
    my $string = shift;
    $self->{errors}->add(
        message => $string,
        path => $self->{parent_keys},
    );
}

# explains what we are doing.
sub explain {
    my $self = shift;
    my $string = shift;
    my $indent = ' ' x ($self->{depth}*$self->{indent});
    $string =~ s/>>/$indent/;
    print $string if $self->{verbose};
}


# add defaults. Go over all keys *on that level* and if there is not
# a value (or, most oftenly, a key) in data, add the key and the
# default value.

sub _add_defaults{
    my $self    = shift;

    for my $key (keys %{$self->{schema}}){
        next unless $self->{schema}->{$key}->{default};
        $self->{data}->{$key} = $self->{schema}->{$key}->{default}
            unless $self->{data}->{$key};
    }
}

# check mandatory: look for mandatory fields in all hashes 1 level
# below current level (in schema)
# for each check if $data has a key.
sub _check_mandatory_keys{
    my $self    = shift;

    for my $key (keys %{$self->{schema}}){
        $self->explain(">>Checking if '$key' is mandatory: ");
        unless ($self->{schema}->{$key}->{optional}
                   and $self->{schema}->{$key}->{optional}){

            $self->explain("true\n");
            next if defined $self->{data}->{$key};

            # regex-keys never directly occur.
            if ($self->{schema}->{$key}->{regex}){
                $self->explain(">>regex enabled key found. ");
                $self->explain("Checking data keys.. ");
                my $c = 0;
                # look which keys match the regex
                for my $c_key (keys %{$self->{data}}){
                    $c++ if $c_key =~ /$key/;
                }
                $self->explain("$c matching occurencies found\n");
                next if $c > 0;
            }

            # should only get here in case of error.
            my $error_msg = '';
            $error_msg = $self->{schema}->{$key}->{error_msg}
                if $self->{schema}->{$key}->{error_msg};
            $self->error("mandatory key '$key' missing. Error msg: '$error_msg'");
        }
        else{
            $self->explain("false\n");
        }
    }
}

# find key to validate (section of) data against
sub _schema_twin_key{
    my $self    = shift;
    my $key     = shift;

    my $schema_key;

    # direct match: exact declaration
    if ($self->{schema}->{$key}){
        $self->explain(" ok\n");
        $schema_key = $key;
    }
    # match against a pattern
    else {
        my $match;
        for my $match_key (keys %{$self->{schema}}){

            # only try to match a key if it has the property
            # _regex_ set
            next unless exists $self->{schema}->{$match_key}
                           and $self->{schema}->{$match_key}->{regex};

            if ($key =~ /$match_key/){
                $self->explain("'$key' matches $match_key\n");
                $schema_key = $match_key;
            }
        }
    }

    # if $schema_key is still undef we were unable to
    # match it against a key in the schema.
    unless ($schema_key){
        $self->explain(">>$key not in schema, keys available: ");
        $self->explain(join (", ", (keys %{$self->{schema}})));
        $self->explain("\n");
        $self->error("key '$key' not found in schema\n");
    }
    return $schema_key
}

# 'validator' specified gets this called to call the callback :-)
sub __validator_returns_undef {
    my $self       = shift;
    my $key        = shift;
    my $schema_key = shift;
    return unless $self->{schema}->{$schema_key}->{validator};
    $self->explain("running validator for '$key': ".($self->{data}->{$key} // '(undefined)').": \n");

    if (ref $self->{data}->{$key} eq ref []
        && $self->{schema}->{$schema_key}->{array}){

        my $counter = 0;
        for my $elem (@{$self->{data}->{$key}}){
            my $return_value = $self->{schema}->{$schema_key}->{validator}->($elem, $self->{data});
            if ($return_value){
                $self->explain("validator error: $return_value (element $counter)\n");
                $self->error("Execution of validator for '$key' element $counter returns with error: $return_value");
            }
            else {
                $self->explain("successful validation for key '$key' element $counter\n");
            }
            $counter++;
        }
    }
    else {
        my $return_value = $self->{schema}->{$schema_key}->{validator}->($self->{data}->{$key}, $self->{data});
        if ($return_value){
            $self->explain("validator error: $return_value\n");
            $self->error("Execution of validator for '$key' returns with error: $return_value");
        }
        else {
            $self->explain("successful validation for key '$key'\n");
        }
    }
}

# called by validate to check if a value is in line with definitions
# in the schema.
sub __value_is_valid{
    my $self    = shift;
    my $key     = shift;

    if (exists  $self->{schema}->{$key}
            and $self->{schema}->{$key}->{value}){
        $self->explain('>>'.ref($self->{schema}->{$key}->{value})."\n");

        # currently, 2 type of restrictions are supported:
        # (callback) code and regex
        if (ref($self->{schema}->{$key}->{value}) eq 'CODE'){
            # possibly never implement this because of new "validator"
        }
        elsif (ref($self->{schema}->{$key}->{value}) eq 'Regexp'){
            if (ref $self->{data}->{$key} eq ref []
                && $self->{schema}->{$key}->{array}){

                for my $elem (@{$self->{data}->{$key}}){
                    $self->explain(">>match '$elem' against '$self->{schema}->{$key}->{value}'");

                    if ($elem =~ m/^$self->{schema}->{$key}->{value}$/){
                        $self->explain(" ok.\n");
                    }
                    else{
                        # XXX never reach this?
                        $self->explain(" no.\n");
                        $self->error("$elem does not match ^$self->{schema}->{$key}->{value}\$");
                    }
                }
            }
            # XXX this was introduced to support arrays.
            else {
               $self->explain(">>match '$self->{data}->{$key}' against '$self->{schema}->{$key}->{value}'");

                if ($self->{data}->{$key} =~ m/^$self->{schema}->{$key}->{value}$/){
                    $self->explain(" ok.\n");
                }
                else{
                    # XXX never reach this?
                    $self->explain(" no.\n");
                    $self->error("$self->{data}->{$key} does not match ^$self->{schema}->{$key}->{value}\$");
                }
            }
        }
        else{
            # XXX match literally? How much sense does this make?!
            # also, this is not tested

            $self->explain("neither CODE nor Regexp\n");
            $self->error("'$key' not CODE nor Regexp");
        }

    }
}

1;


package SD::OpenAPI::Live;
use 5.22.0;
use warnings;

use Moo;

extends 'SD::OpenAPI';
with 'SD::OpenAPI::Role::Swagger2';

use Function::Parameters qw( :strict );

method BUILD {
    # dies on failure
    $self->_validate_spec;

    _expand_references($self->spec, $self->spec->{definitions});
}

fun _expand_references($hash, $definition_for) {
    for my $key (keys %$hash) {
        my $value = $hash->{$key};

        if (ref $value eq 'HASH') {
            # Recursively expand any hash values we find.
            _expand_references($value, $definition_for);
        }
        elsif (($key eq '$ref') && ($value =~ m{#/definitions/(.*)})) {
            if (exists $definition_for->{$1}) {
                my $replacement = $definition_for->{$1};

                # Remove the '$ref => #/definitions/Something' pair
                delete $hash->{$key};

                # Insert all the key/value pairs from the replacement hash.
                @${hash}{ keys %$replacement } = values %$replacement;
            }
        }
    }
}

1;

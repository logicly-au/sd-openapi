package SD::OpenAPI::Live;
use 5.22.0;
use warnings;

use Moo;

extends 'SD::OpenAPI';
with 'SD::OpenAPI::Role::Swagger2';

use Clone                qw( clone );
use Function::Parameters qw( :strict );

method BUILD {
    # dies on failure
    $self->_validate_spec;

    _expand_references($self->spec, $self->spec->{definitions});
    _expand_schemas($self->spec->{paths});
}

fun _expand_references($value, $definition_for) {
    if (ref $value eq 'HASH') {
        _expand_hash_references($value, $definition_for);
    }
    elsif (ref $value eq 'ARRAY') {
        _expand_array_references($value, $definition_for);
    }
}

fun _expand_hash_references($hash, $definition_for) {
    for my $key (keys %$hash) {
        my $value = $hash->{$key};

        # Recursively expand any hash or array values we find.
        _expand_references($value, $definition_for);

        if (($key eq '$ref') && ($value =~ m{#/definitions/(.*)})) {
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

fun _expand_array_references($array, $definition_for) {
    for my $value (@$array) {
        _expand_references($value, $definition_for);
    }
}

fun _expand_schemas($paths) {
    while (my ($path, $request) = each %$paths) {
        while (my ($method, $spec) = each %$request) {
            my @params;
            for my $param (@{ $spec->{parameters} }) {
                if (exists $param->{schema}) {
                    _expand_schema($param);
                }
                push(@params, _expand_param($param));
            }
            $spec->{parameters} = \@params;
        }
    }
}

fun _expand_param($param) {
    if ($param->{type} eq 'object') {
        return _expand_object($param);
    }
    if ($param->{type} eq 'array') {
        return _expand_array($param);
    }
    return $param;
}

fun _expand_object($param) {
    my %required = map { $_ => 1 } @{ $param->{required} // [] };
    while (my ($name, $property) = each %{ $param->{properties} }) {
        $property = _expand_param($property);
        $property->{name} = $name;
        $property->{required} = 1 if $required{$name};
    }
    return $param;
}

fun _expand_array($param) {
    $param->{items} = _expand_object($param->{items});
    return $param;
}

fun _expand_schema($param) {
    my $schema = $param->{schema};
    for my $key (keys %$schema) {
        delete $param->{$key}; # XXX: avoid read-only value error :/
        $param->{$key} = $schema->{$key};
    }
    delete $param->{schema};
}

1;

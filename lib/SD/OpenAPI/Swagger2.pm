package SD::OpenAPI::Swagger2;

use 5.22.0;
use warnings;

use Exporter                qw( import );
use JSON::Validator         qw( );

use Function::Parameters    qw( :strict );

our @EXPORT_OK = qw( expand_swagger validate_swagger );

fun validate_swagger($swagger) {
    my $validator = JSON::Validator->new;
    $validator->schema('http://swagger.io/v2/schema.json#');
    $validator->coerce(booleans => 1);

    if (my @errors = $validator->validate($swagger)) {
        my $errors = join("\n", map { $_->path . ': ' . $_->message } @errors);
        die "$errors\n";
    }

    return $swagger;
}

fun expand_swagger($swagger) {
    $swagger = _expand_references($swagger);
    _merge_required($swagger);
    _hoist_schemas($swagger);
    _merge_allofs($swagger);

    # Post-expansion internal validation
    my @errors = _validate_params($swagger);
    if (@errors) {
        my $errors = join("\n", @errors);
        die "$errors\n";
    }

    return $swagger;
}

fun _expand_references($swagger) {
    # I had code to do this, but JSON::Validator can do it for us. Win!
    my $validator = JSON::Validator->new;
    $validator->schema($swagger);
    return $validator->schema->data;
}

# This function walks the swagger tree, calling $f on each item it finds.
# The items may be hashes, arrays or scalars. Note that $f gets called
# after the recursive call, so $f will be applied bottom-up.
fun _walk_tree($object, $f) {
    if (ref $object eq 'ARRAY') {
        _walk_tree($_, $f) for @$object;
    }
    elsif (ref $object eq 'HASH') {
        _walk_tree($_, $f) for values %$object;
    }
    $f->($object);
}

# For schemas and such where we have:
#   properties => { name => { ... } }
#   required   => [ list-of-names ]
# make these the same as regular parameters by setting required=>1 in the
# properties themselves (just the required ones, there is no required=>0)
fun _merge_required($root) {
    _walk_tree($root, fun($object) {
        return unless ref $object eq 'HASH';

        if (exists $object->{properties} && exists $object->{required}) {
            $object->{properties}->{$_}->{required} = 1
                for @{ $object->{required} };

            delete $object->{required};
        }
    });
}

# Schemas with references have already been expanded, so hoist them up one
# level, as if they were declared inline.
fun _hoist_schemas($root) {
    _walk_tree($root, fun($object) {
        return unless ref $object eq 'HASH';

        if (exists $object->{schema}) {
            @{$object}{ keys %{ $object->{schema} }}
                = values %{ $object->{schema} };

            delete $object->{schema};
        }
    });
}

# Merge together any allOf sections. The code looks tricky but the idea is
# simple.
# Hash values get merged together so that [ { a => 1 }, { b => 2 } ]
# becomes { a => 1, b => 2 }
# List values get concatenated.
fun _merge_allofs($root) {
    _walk_tree($root, fun($object) {
        return unless ref $object eq 'HASH';
        return unless exists $object->{allOf};

        for my $sub_object (@{ $object->{allOf} }) {
            while (my ($key, $value) = each %$sub_object) {
                if (ref $value eq 'HASH') {
                    @{ $object->{$key} }{ keys %$value } = values %$value;
                }
                elsif (ref $value eq 'ARRAY') {
                    push(@{ $object->{$key} }, @$value);
                }
                else {
                    if (exists $object->{$key} && $object->{$key} ne $value) {
                        die "Merging allof: $object->{$key} ne $value\n";
                    }
                    else {
                        $object->{$key} //= $value;
                    }
                }
            }
        }

        delete $object->{allOf};
    });
}

fun _validate_params($swagger) {
    my @errors;
    my $paths = $swagger->{paths};
    for my $path (keys %$paths) {
        while (my ($method, $handler) = each %{ $paths->{$path} }) {
            push(@errors, _validate_path_params($method, $path, $handler));
            push(@errors, _validate_body_params($method, $path, $handler));
        }
    }
    return @errors;
}

fun _validate_handler_params($method, $path, $handler) {
    my @path_parameters = ($path =~ /{(.*?)}/g);
    if (@path_parameters) {
        local $, = ', ';
        say "$path: @path_parameters";
    }
}

fun _validate_path_params($method, $path, $handler) {
    my @errors;
    my $prefix = "$method $path";

    my @path_parameters = ($path =~ /{(.*?)}/g);
    my @params = @{ $handler->{parameters} // [ ] };
    for my $name (@path_parameters) {
        my @matching_params = grep { $_->{name} eq $name } @params;
        if (!@matching_params) {
            push(@errors,
                "$prefix: path parameter \"$name\" not in parameter list");
            next;
        }

        my ($path_param) = grep { $_->{in} eq 'path' } @params;
        if (!defined $path_param) {
            my $types = join(', ', map { $_->{in} } @matching_params);
            push(@errors,
                "$prefix: path parameter \"$name\" in $types, not in path");
            next;
        }

        if (! $path_param->{required}) {
            # JSON::Validator catches this.
            push(@errors,
                "$prefix: path parameter \"$name\" cannot be optional");
            next;
        }
    }

    for my $param (@params) {
        next unless $param->{in} eq 'path';
        my $name = $param->{name};
        if ($path !~ /{$name}/) {
            push(@errors,
                "$prefix: path parameter \"$name\" not in path");
        }
    }

    return @errors;
}

fun _validate_body_params($method, $path, $handler) {
    my $prefix = "$method $path";

    my @body_parameters = grep { $_->{in} eq 'body' }
                               @{ $handler->{parameters } };
    return ( ) unless @body_parameters;

    if ($method eq 'get') {
        return ("$prefix: body parameters not allowed in $method request");
    }

    if (@body_parameters > 1) {
        return ("$prefix: only one body parameter allowed");
    }

    my @errors;
    my ($body) = @body_parameters;

    if ($body->{name} ne 'body') {
        push(@errors,
            "body parameters must be named \"body\", not \"$body->{name}\"");
    }

    return @errors;
}

1;

__END__

=head1 NAME

SD::OpenAPI::Swagger2 - validate and expand swagger

=head1 SYNOPSIS

    use SD::OpenAPI::Swagger2 qw( expand_swagger validate_swagger );

    my $swagger_in = ...;
    validate_swagger($swagger_in);
    my $swagger_out = expand_swaggger($swagger_in);

=head1 FUNCTIONS

=head2 validate_swagger($swagger)

Validate the provided swagger and die if any errors are found.
Returns the validated swagger unchanged.

=head2 expand_swagger($swagger)

Expands references, schemas, and allOfs to the corresponding inline versions.
Returns the expanded swagger.

=cut

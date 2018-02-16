package SD::OpenAPI::Swagger2;

use 5.22.0;
use warnings;

use Exporter                qw( import );
use JSON::Validator         qw( );
use Clone                   qw( clone );

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
    _expand_references($swagger);
    _expand_security($swagger);
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
    my $refkey = '$ref';

    # I originally wrote my own giant clunky piece of code to do this, then
    # realised JSON::Validator could do it for me, and then realised their
    # code had issues allowing bad swagger through, so I've now replaced that
    # code with this. The circle is complete. For now.

    _walk_tree($swagger, fun($object) {
        return unless ref $object eq 'HASH';
        return unless exists $object->{$refkey};

        # I"m working on the assumption that references are always like this:
        #   { '$ref' => "#/definitions/$name" }
        # ie. always in a hash as the only pair

        if (keys %$object > 1) {
            use Data::Dumper::Concise; print STDERR Dumper($object);
            die "Found '\$ref' in a hash with other items\n";
        }

        my $value = $object->{$refkey};
        if ($value !~ m{^#/([^/]+)/(.+)}) {
            die "Bad reference string \"$value\"\n";
        }
        my $field = $1;
        my $name = $2;

        die "Field \"$field\" not found\n"
            unless exists $swagger->{$field};

        my $fields = $swagger->{$field};
        die "$field for \"$name\" not found\n"
            unless exists $fields->{$name};

        %$object = %{ $fields->{$name} };
    });
}

# This method decorates every method/path with the global security
# settings and then calls _expand_security_schemes to copy settings
# from the top level security definitions into each path/method
fun _expand_security($swagger){
    return unless $swagger->{securityDefinitions};

    my $global_security = $swagger->{security};

    foreach my $path ( keys %{ $swagger->{paths} } ) {

        foreach my $method ( values %{ $swagger->{paths}{$path} } ) {
            next unless $method->{security} || $global_security;

            # Inherit global security
            $method->{security} //= $global_security;

            _expand_security_schemes( $swagger, $path, $method );
        }
    }
}

# Given a path/method that has a 'security' parameter, this method
# expands that into the full security configuration copied from the
# top level securityDefinitions. In the case where there's scope in
# the path/method's security setting, the copying of data from the top
# level only includes relevant scopes.
fun _expand_security_schemes($swagger, $path, $method) {

    my $security_definitions = $swagger->{securityDefinitions};


    foreach my $security_option ( @{ $method->{security} } ) {
        my $expanded_options = {};

        my @security_schemes = keys %{ $security_option };

        foreach my $scheme ( @security_schemes ){
            if( ! exists $security_definitions->{$scheme} ){
                die("Unknown security definition '$scheme' used in $path\n");
            }
            $expanded_options->{$scheme} = clone $security_definitions->{$scheme};

            if( ref $expanded_options->{$scheme}{scopes} eq 'HASH' ){
                $expanded_options->{$scheme}{scopes} = [
                    grep {
                        exists $expanded_options->{$scheme}{scopes}{$_}
                    } @{$security_option->{$scheme}}
                ];
            }
        }

        push( @{ $method->{security_expanded} }, $expanded_options );
    }

}

# This function walks the swagger tree, calling $f on each item it finds.
# The items may be hashes, arrays or scalars. Note that $f gets called
# after the recursive call, so $f will be applied bottom-up.
fun _walk_tree($object, $f, $seen = { }) {
    # This $seen hash was to avoid an infinite recursion that was caused by
    # JSON::Validator allowing malformed references in. I'm going to leave this
    # in for now, but I suspect it is no longer necessary.
    # It may be needed in the case that swagger allows recursive structures.
    # eg. a Person definition could conceivably contain a sub-array of Persons
    return if $seen->{$object}++;
    if (ref $object eq 'ARRAY') {
        _walk_tree($_, $f, $seen) for @$object;
    }
    elsif (ref $object eq 'HASH') {
        _walk_tree($_, $f, $seen) for values %$object;
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

package SD::OpenAPI::Live::Dancer2;
use 5.22.0;

use Moo;
extends 'SD::OpenAPI::Live';

use Carp                        qw( croak );
use Clone                       qw( clone );
use Class::Load                 qw( load_class );
use DateTime::Format::ISO8601   qw( );
use Log::Any                    qw( $log );
use Try::Tiny;

use Function::Parameters qw( :strict );

has 'namespace' => (
    is => 'ro',
    default => method {
        # Walk up the call stack until we find a package that isn't ours.
        for (my $depth = 0; my $caller = caller($depth); $depth++) {
            if ($caller ne __PACKAGE__) {
                return $caller;
            }
        }
        croak("Can't deduce namespace - please specify namespace");
    },
);

method make_app($app) {
    my $paths = $self->spec->{paths};
    my %options;

    $log->info("Auto-generating dancer2 routes");

    while (my ($path, $request) = each %$paths) {
        while (my ($method, $spec) = each %$request) {

            my $metadata = $self->create_metadata($path, $method, $spec)
                or next;

            $self->add_route($app, $metadata);

            push(@{ $options{$path} }, uc $method);
            if ($method eq 'get') {
                push(@{ $options{$path} }, 'HEAD');
            }
        }
    }

    my %options_handler;
    while (my ($path, $methods) = each %options) {
        my $allow = join(',', sort @$methods);

        my $sub = $options_handler{$allow} //= sub {
            my ($app) = @_;
            $app->response->header('Allow' => $allow);
            return;
        };

        $app->add_route(method => 'options', regexp => $path, code => $sub);
    }
}

method create_metadata($path, $method, $spec) {
    if (!exists $spec->{operationId}) {
        $log->error("No operationId for $method $path - skipping");
        return;
    }

    my $metadata;
    if ($spec->{operationId} =~ /^(.*)::(.*)$/) {
        $metadata = clone($spec);
        $metadata->{module_name} = $1;
        $metadata->{sub_name} = $2;
    }
    else {
        $log->error("No module specified in $spec->{operationId} for \"$method $path\", skipping");
        return;
    }

    $metadata->{swagger_path} = $path;
    $metadata->{http_method}  = $method;

    $metadata->{dancer2_path} = $metadata->{swagger_path}
        =~ s/\{ (.*?) \}/:$1/grx;

    $metadata->{required_parameters} =
        [ grep { $_->{required} } @{ $metadata->{parameters} } ];
    $metadata->{optional_parameters} =
        [ grep { !$_->{required} } @{ $metadata->{parameters} } ];

    # Delete any empty parameter lists.
    for my $list (qw( required_parameters optional_parameters )) {
        delete $metadata->{$list} unless @{ $metadata->{$list} };
    }

    return $metadata;
}

method add_route($app, $metadata) {
    my %args = (
        method => $metadata->{http_method},
        regexp => $metadata->{dancer2_path},
        code   => $self->make_handler($metadata),
    );
    $app->add_route(%args);

    # If the request is a GET, add a HEAD with the same args.
    if ($metadata->{http_method} eq 'get') {
        $args{http_method} = 'head';
        $app->add_route(%args);
    }
}

my %param_method = (
    body     => 'body_parameters',
    formData => 'body_parameters',
    header   => 'header',
    path     => 'route_parameters',
    query    => 'query_parameters',
);

my $datetime_parser = DateTime::Format::ISO8601->new;

# http://swagger.io/specification/#data-types-12
my %type_check;
%type_check = (
    integer => sub {
        my ($value, $type, $name) = @_;
        if ($value =~ /^[-+]?\d+$/) {
            return int($value);
        }
        die { $name => 'must be an integer' };
    },
    string => sub {
        my ($value, $type, $name) = @_;
        if (length($value) > 0) {
            return "$value";
        }
        die { $name => 'must be a non-empty string' };
    },
    boolean => sub {
        my ($value, $type, $name) = @_;
        if ($value =~ /^0|1$/) {
            return $value != 0;
        }
        die { $name => "must be a boolean value (0 or 1)" };
    },
    'date-time' => sub {
        my ($value, $type, $name) = @_;
        try {
            $value = $datetime_parser->parse_datetime($value);
        }
        catch {
            die { $name => "must be an ISO8601-formatted datetime string" };
        };
        return $value;
    },
    array => sub {
        my ($value, $type, $name) = @_;
        my $itemtype = $type->{items}->{check_type};
        if (ref $value ne 'ARRAY') {
            die { $name => "must be an array of $itemtype" };
        }

        my $check = $type_check{$itemtype};

        # Collect any errors further down and propagate them up
        my @ret;
        my %errors;
        while (my ($index, $item) = each @$value) {
            try {
                push(@ret, $check->($item, $type->{items}, "$name\[$index\]"));
            }
            catch {
                @errors{ keys %$_ } = values %$_;
            };
        }
        die \%errors if keys %errors;
        return \@ret;
    },
    object => sub {
        my ($value, $type, $name) = @_;
        if (ref $value ne 'HASH') {
            die { $name => "must be an object" };
        }

        my %ret;
        my %errors;
        while (my ($field_name, $field_type) = each %{ $type->{properties} }) {
            my $key = "$name\.$field_name";

            if (!exists $value->{$field_name}) {
                $errors{$key} = "missing required field $field_name"
                    if $field_type->{required};
                next;
            }

            my $check = $type_check{ $field_type->{check_type} };
            try {
                $ret{$field_name} =
                    $check->($value->{$field_name}, $field_type, $key);
            }
            catch {
                @errors{ keys %$_ } = values %$_;
            };
        }
        die \%errors if keys %errors;
        return \%ret;
    },
);

fun assign_type($spec) {
    if ((exists $spec->{format}) && (exists $type_check{ $spec->{format} })) {
        $spec->{check_type} = $spec->{format};
    }
    elsif ((exists $spec->{type}) && (exists $type_check{ $spec->{type} })) {
        $spec->{check_type} = $spec->{type};
    }
    else {
        $log->error("Can't match type for $spec->{type}");
        #use Data::Dumper::Concise; print STDERR "MISSING: ", Dumper($spec);
        $spec->{type} = $spec->{check_type} = 'string';
    }

    if ($spec->{check_type} eq 'array') {
        assign_type($spec->{items});
    }
    elsif ($spec->{check_type} eq 'object') {
        assign_type($_) for values %{ $spec->{properties} };
    }
}

method make_handler($metadata) {
    my $package = join('::',
        $self->namespace,
        'Controller',
        $metadata->{module_name},
    );

    load_class($package);
    my $sub = $package->can($metadata->{sub_name});

    my $symbol = $package . '::' . $metadata->{sub_name};
    my $path   = $metadata->{dancer2_path};
    my $method = $metadata->{http_method};

    if (! defined $sub) {
        # If the required handler can't be found, substitute a default handler
        # which returns an unimplemented error along with some extra info.
        $log->error("Handler $symbol not found for $method $path");
        $sub = $self->unimplemented($metadata->{operationId});
    }
    else {
        $log->info("$method $path");
        $log->info(" --> $metadata->{module_name}::$metadata->{sub_name}");
    }

    # Install type checkers for all the types.
    # Do this ahead of time so we only need to check it all once. At run-time
    # we can assume this is all correct.
    my $default_type = 'string';
    for my $p (@{ $metadata->{parameters} }) {
        assign_type($p);
    }

    # Wrap the handler $sub in parameter validation/inflation code.
    # The function below is what gets called at run-time.
    return fun($app) {

        # Validate and inflate the parameters.
        my %params;
        my %errors;
        for my $p (@{ $metadata->{parameters} }) {
            my $get_param = $param_method{$p->{in}};

            my $name = $p->{name};
            my @vals;
            if ($p->{in} eq 'body') {
                $vals[0] = $app->request->data;
            }
            else {
                @vals = $app->request->$get_param->get_all($name);
            }

            if (@vals == 0) {
                $errors{$name} = "parameter $name not specified"
                    if $p->{required};
                next;
            }

            if (@vals > 1) {
                $errors{$name} = "parameter $name specified multiple times";
                next;
            }

            try {
                my $check = $type_check{$p->{check_type}};
                $params{$name} = $check->($vals[0], $p, $name);
            }
            catch {
                @errors{ keys %$_ } = values %$_;
            };
        }

        # Bomb out if we had any errors.
        if (keys %errors) {
            $app->response->status(400);
            return { errors => \%errors };
        }

        # Otherwise pass through the the actual handler.
        return $sub->($app, \%params, $metadata);
    }
}

# Generate a default handler when the named handler does not exist.
method unimplemented($sub_name) {
    return fun($app, $params, $metadata) {
        my $ret = {
            errors => "Unimplemented handler $sub_name",
            handler => $sub_name,
            params => $params,
            metadata => $metadata,
        };

        use Data::Dumper::Concise; print STDERR Dumper($ret);
        $app->response->status(501);

        return $ret;
    }
}

1;

__END__

=head1 NAME

SD::OpenAPI::Live::Dancer2

=cut

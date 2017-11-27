package SD::OpenAPI::Live::Dancer2;
use 5.22.0;
use warnings;

use Moo;
extends 'SD::OpenAPI::Live';

use Carp                        qw( croak );
use Clone                       qw( clone );
use Class::Load                 qw( load_class );
use Log::Any                    qw( $log );
use SD::OpenAPI::Types          qw( check_type prepare_handler );
use Try::Tiny;

use Function::Parameters        qw( :strict );

has namespace => (
    is => 'ro',
    default => method() {
        # Walk up the call stack until we find a package that isn't ours.
        for (my $depth = 0; my $caller = caller($depth); $depth++) {
            if ($caller ne __PACKAGE__) {
                return $caller;
            }
        }
        croak("Can't deduce namespace - please specify namespace");
    },
);

has hooks => (
    is => 'ro',
    default => sub {
        return {
            before_params  => [ ],
            before_handler => [ ],
            after_handler  => [ ],
        };
    },
);

method set_hook($hook_name, $code) {
    croak("Unknown hook $hook_name") unless exists $self->hooks->{$hook_name};
    push(@{ $self->hooks->{$hook_name} }, $code);
}

method get_hooks($hook_name) {
    return @{ $self->hooks->{$hook_name} // [] };
}

method make_app($app) {
    my $paths = $self->spec->{paths};
    my %options;

    $log->info("Auto-generating dancer2 routes");

    # sort paths on their *swagger* representation, ensuring specific
    # paths are added before generic ones; eg.
    # `/users/current` before `/users/{UUID}`.
    for my $path (sort keys %$paths) {
        while (my ($method, $spec) = each %{$paths->{$path}}) {

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
        $args{method} = 'head';
        $app->add_route(%args);
    }
}

my %param_method = (
    body => fun($request, $param) {
        return ( $request->data );
    },
    formData => fun($request, $param) {
        return ( $request->data );
    },
    header => fun($request, $param) {
        return $request->header($param);
    },
    path => fun($request, $param) {
        return $request->route_parameters->get_all($param);
    },
    query => fun($request, $param) {
        return $request->query_parameters->get_all($param);
    },
);

method make_handler($metadata) {
    my $package;
	# Allow module names to be "+-prefixed fully qualified",
	# otherwise assume the prefix is ${namespace}::Controller
    if ($metadata->{module_name} =~ /^\+(.*)$/ ) {
        $package = $1;
    }
    else {
        $package = join('::',
            $self->namespace,
            'Controller',
            $metadata->{module_name},
        );
    }

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

    # Install type checkers and defaults for all the types.
    # Do this ahead of time so we only need to check it all once. At run-time
    # we can assume this is all correct.
    prepare_handler($metadata);

    # Wrap the handler $sub in parameter validation/inflation code.
    # The function below is what gets called at run-time.
    return fun($app) {

        my %params;

        # Run any before_params hooks.
        for my $hook ($self->get_hooks('before_params')) {
            $hook->($app, \%params, $metadata);
        }

        # Validate and inflate the parameters.
        my %errors;
        for my $p (@{ $metadata->{parameters} }) {
            my $get_param = $param_method{$p->{in}};

            my $name = $p->{name};
            my @vals = $get_param->($app->request, $name);

            if (@vals == 0) {
                $errors{$name} = "missing parameter $name"
                    if $p->{required};

                if (exists $p->{default_value}) {
                    # This is already validated and inflated. Copy it and move
                    # on to the next parameter. We don't need to fall through.
                    $params{$name} = $p->{default_value};
                }
                next;
            }

            if (@vals > 1) {
                $errors{$name} = "parameter $name specified multiple times";
                next;
            }

            try {
                $params{$name} = check_type($vals[0], $p, $name);
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

        # Run any before_handler hooks.
        for my $hook ($self->get_hooks('before_handler')) {
            $hook->($app, \%params, $metadata);
        }

        # Otherwise pass through the the actual handler.
        my $result = $sub->($app, \%params, $metadata);

        # Run any after_handler hooks.
        for my $hook ($self->get_hooks('after_handler')) {
            $hook->($app, \%params, $result, $metadata);
        }

        return $result;
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

=head1 METHODS

=head2 make_app($app)

Inject the routes defined in the openapi spec to the given Dancer2 app.

This could probably do with a more meaningful name.

=head2 set_hook($hook_name, $handler_subref)

Similar in nature to Dancer2 hooks, these provide places in the code where
the downstream app can inject custom behaviour.

The code in the hooks is free to modify the parameters passed to it, throw
exceptions, or return error responses. Note that in the case of exceptions
or C<send_as> error responses, other hook handlers that would have been called
get skipped.

=head3 before_params($app, $params, $metadata)

This gets called before any of the parameter checking has been done. The $params
hashref is empty.

This is an appropriate place to do auth checking.

=head2 before_handler($app, $params, $metadata)

This gets called just before the route handler code. All of the parameter
processing has been completed. The args passed to this function are exactly
what would be passed to the route handler itself.

=head2 after_handler($app, $params, $result, $metadata)

This gets called immediately after the route handler has returned. It has an
extra C<$result> parameter which is the return value from the route handler.

The hook code is free to modify this C<$result> object.

=cut


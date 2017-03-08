package SD::OpenAPI::Live::Dancer2;
use 5.22.0;

use Moo;
extends 'SD::OpenAPI::Live';

use Clone       qw( clone );
use Class::Load qw( load_class );
use Try::Tiny;

use Function::Parameters qw( :strict );

has 'namespace' => (
    is => 'ro',
    required => 1,
);

method make_app($app) {
    my $paths = $self->spec->{paths};
    my %options;

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
        warn "No operationId for \"$method $path\" - skipping\n";
        return;
    }

    my $metadata;
    if ($spec->{operationId} =~ /^(.*)::(.*)$/) {
        $metadata = clone($spec);
        $metadata->{module_name} = $1;
        $metadata->{sub_name} = $2;
    }
    else {
        warn "No module specified in $spec->{operationId} for \"$method $path\", skipping\n";
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
    formData => 'body_parameters->get_all',
    header   => 'header',
    path     => 'route_parameters',
    query    => 'query_parameters',
);

my %type_check = (
    integer => sub {
        if ($_[0] =~ /^[-+]?\d+$/) {
            return int($_[0]);
        }
        die "an integer\n";
    },
    string => sub {
        if (length($_[0]) > 0) {
            return "$_[0]";
        }
        die "a non-empty string\n";
    },
    boolean => sub {
        if ($_[0] =~ /^0|1$/) {
            return $_[0] != 0;
        }
        die "a boolean value (0 or 1)\n";
    },
);

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

    say STDERR "$method $path";
    if (! defined $sub) {
        say STDERR "  ** NOT FOUND $symbol";
        $sub = sub { return { errors => 'Unimplemented' } };
    }
    else {
        say STDERR " --> $symbol";
    }

    # Install type checkers for all the types.
    my $default_type = 'string';
    for my $p (@{ $metadata->{parameters} }) {
        my $name = $p->{name};
        if (! exists $p->{type}) {
            warn " *** missing type for parameter \"$name\" - defaulting to $default_type\n";
            $p->{type} = $default_type;
        }
        my $type = $p->{type};
        if (! exists $type_check{$type}) {
            warn " *** unexpected type \"$type\" for parameter \"$p->{name}\" - defaulting to $default_type\n";
            $type = $default_type;
        }
        $p->{check} = $type_check{$type};
    }

    # Create a closure that wraps the custom handler in some parameter handling
    # code.
    return sub {
        my ($app) = @_;

        # Validate and coerce the parameters.
        my %params;
        my %errors;
        for my $p (@{ $metadata->{parameters} }) {
            my $get_param = $param_method{$p->{in}};

            my $name = $p->{name};
            my @vals = $app->request->$get_param->get_all($name);

            if (@vals != 1) {
                my $message = @vals == 0 ? 'not specified'
                                         : 'specified multiple times';
                $errors{$name} = "parameter $name $message";
                next;
            }

            try {
                $params{$name} = $p->{type_check}->($vals[0]);
            }
            catch {
                chomp;
                $errors{$name} = "must be $_";
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

1;

__END__

=head1 NAME

SD::OpenAPI::Live::Dancer2

=cut

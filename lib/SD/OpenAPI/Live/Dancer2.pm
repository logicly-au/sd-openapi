package SD::OpenAPI::Live::Dancer2;
use 5.22.0;

use Moo;
extends 'SD::OpenAPI::Live';

use Clone                       qw( clone );
use Class::Load                 qw( load_class );
use DateTime::Format::ISO8601   qw( );
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
        if ($_[0] =~ /^[-+]?\d+$/) {
            return int($_[0]);
        }
        die "$_[1]->{name} an integer\n";
    },
    string => sub {
        if (length($_[0]) > 0) {
            return "$_[0]";
        }
        die "$_[1]->{name} a non-empty string\n";
    },
    boolean => sub {
        if ($_[0] =~ /^0|1$/) {
            return $_[0] != 0;
        }
        die "$_[1]->{name} a boolean value (0 or 1)\n";
    },
    'date-time' => sub {
        my $date = $_[0];
        try {
            $datetime_parser->parse_datetime($date);
        }
        catch {
            die "an ISO8601-formatted datetime string <$date>\n";
        };
    },
    array => sub {
        my ($value, $type) = @_;
        my $itemtype = $type->{items}->{check_type};
        my $check = $type_check{$itemtype};
        if (ref $value ne 'array') {
            die "an array of $itemtype";
        }

        # Let any exceptions propagate up
        return [ map { $check->($_, $type->{items}) } @$value ];
    },
    object => sub {
        my ($value, $type) = @_;
        my %ret;
        while (my ($field_name, $field_type) = each %{ $type->{properties} }) {
            my $field_value = $value->{$field_name};
            if (!defined $field_value && $field_type->{required}) {
                die "Missing field $field_name\n";
            }

            my $check = $type_check{ $field_type->{check_type} };
            $ret{$field_name} = $check->($field_value, $field_type);
        }

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
        assign_type($p);
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
                $params{$name} = $check->($vals[0], $p);
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

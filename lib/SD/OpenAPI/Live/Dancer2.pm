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

            if (!exists $spec->{operationId}) {
                warn "No operationId for \"$method $path\" - skipping";
                next;
            }

            my $metadata;
            if ($spec->{operationId} =~ /^(.*)::(.*)$/) {
                $metadata = clone($spec);
                $metadata->{module_name} = $1;
                $metadata->{sub_name} = $2;
            }
            else {
                warn "No module specified in $spec->{operationId} for \"$method $path\", skipping";
                next;
            }

            $metadata->{swagger_path} = $path;
            $metadata->{http_method} = $method;

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

            $self->_add_route($app, $metadata);

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

method _add_route($app, $metadata) {
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

    return sub {
        my ($app) = @_;
        my %params;
        my %errors;

        for my $p (@{ $metadata->{parameters} }) {
            my $get_param = $param_method{$p->{in}};

            my $name = $p->{name};
            my @vals = $app->request->$get_param->get_all($name);

            if (@vals > 1) {
                $errors{$name} =
                    "parameter $name specified multiple times";
                next;
            }

            if (@vals == 0) {
                if ($p->{required}) {
                    $errors{$name} = "$p->{in} parameter $name not specified";
                }
                next;
            }

            my $type = $p->{type};
            my $value = try {
                $type_check{$type}->($vals[0]);
            }
            catch {
                chomp;
                $errors{$name} = "must be $_";
            };
            next unless defined $value;

            $params{$name} = $value;
        }

        if (keys %errors) {
            $app->response->status(400);
            return { errors => \%errors };
        }

        return $sub->($app, \%params, $metadata);
    }
}

1;

__END__

=head1 NAME

SD::OpenAPI::Live::Dancer2

=cut

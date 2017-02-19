package SD::OpenAPI::Loader::Dancer2;
use 5.24.0;
use Moo;
extends 'SD::OpenAPI::Loader';
use Function::Parameters qw(:strict);

use Carp qw(croak);
use Data::Dumper;

our $VERSION = '0.0.5';

has 'location' => (
    is => 'ro',
    required => 1,
);

has 'namespace' => (
    is => 'ro',
    required => 1,
);

method make_routes {
    $self->_write_routes(
        routes => $self->_parse_routes(),
    );
}

method filename_for_class($class) {
    $class =~ s!::!/!g;
    return $self->location . q{/} . $class . q{.pm};
}

method _parse_routes {
    my $paths = $self->spec->{paths};

    my $routes = {};
    for my $p ( keys $paths->%* ) {
        # adapt OpenAPI syntax for URL path args to Dancer2 syntax
        # '/path/{argument}' => '/path/:argument/
        my $path = $p =~ s/\{([^{}]+?)\}/:$1/gr;

        my @http_options = ();
        for my $m ( keys $paths->{$p}->%* ) {
            my $route_spec = $paths->{$p}{$m};

            my $http_method = $m;
            push @http_options, uc $http_method;
            push @http_options, 'HEAD' if $http_method eq 'get';

            # Dancer2 DSL keyword is difference from HTTP method
            $http_method = 'del' if $http_method =~ m/^delete$/i;

            my $module = '';
            my $method = $route_spec->{operationId};
            if ( $method =~ s/^(.+)::// ) { # looks like a perl module
                $module = "::$1";
            }

            $routes->{$path}{$http_method} = {
                controller => sprintf( '%s::Controller%s', $self->namespace, $module ),
                method     => $method,
                parameters => $route_spec->{parameters},
                description => $route_spec->{summary},
            };
        }
        # options route
        $routes->{$path}{'options'} = {
            allow => \@http_options,
        };
    }

    return $routes;
}

method _write_controller_stub( :$class, :$methods = [] ) {
    my $content = qq|package $class;\nuse 5.24.0;\n|
                . qq|use warnings;\nuse Function::Parameters {\n|
                . qq|  fun => 'function_strict', method => 'method_strict',\n|
                . qq|  route => { defaults => 'method', 'shift' => '\$app' }\n|
                . qq|};\n\n|
                . qq|use Try::Tiny;\n\n|;

    # Basic POD
    $content .= qq|=head1 NAME\n\n$class - a controller\n\n|
              . qq|=head1 ROUTES\n\n|;

    for my $mth ( $methods->@* ) {
        my ($method, $desc) = $mth->%*;
        $content .= qq|=head2 $method\n\n$desc\n\n=cut\n\n|;
        $content .= qq|route $method {\n\n# TODO\n\n}\n\n|;
    }

    $content .= "\n1;\n";

    $self->write_file(
        filename => $self->filename_for_class( $class ),
        content => $content,
    );
}

method _write_routes( :$routes ) {
    my $class = $self->namespace . '::Routes';

    my $namespace = $self->namespace;
    my $content = qq|package $class;\nuse 5.24.0;\n|
                . qq|use Dancer2 appname => '$namespace';\n\n|;

    # Use all controllers
    my $controllers = {};
    for my $route ( sort keys $routes->%* ) {
        for my $method ( sort keys $routes->{$route}->%* ) {
            next if $method eq 'options';
            $controllers->{ $routes->{$route}{$method}{controller} } //= [];
            push @{ $controllers->{ $routes->{$route}{$method}{controller} } },
              + { $routes->{$route}{$method}{method} => $routes->{$route}{$method}{description} };
        }
    }
    for my $ctr ( sort keys $controllers->%* ) {
        $content .= qq|use $ctr;\n|;
        $self->_write_controller_stub(
            class   => $ctr,
            methods => $controllers->{$ctr}
        );
    }
    $content .= "\n";

    my $prefix = $self->spec->{basePath};
    if ( defined $prefix ) {
        $content .= "prefix '$prefix' => sub {\n"
    }

    # paths need to be sorted on alpha lower case
    # except - paths with params (':') need to go after those without
    my @sorted_paths = map {
        $_->[0]
    } sort {
        my $lenA = scalar @{ $a->[1] };
        my $lenB = scalar @{ $b->[1] };
        my $shortest = $lenA < $lenB ? $lenA : $lenB;
        # start at 1, as all paths begin with '/'
        for ( 1 .. ( $shortest - 1 ) ) {
            next if $a->[1][$_] eq $b->[1][$_]; # Deeper
            my $firstA = substr($a->[1][$_],0,1);
            my $firstB = substr($b->[1][$_],0,1);
            if ( $firstA eq ':' ) {
                return ( $firstB eq ':' )
                    ? $a->[1][$_] cmp $b->[1][$_]
                    : 1;
            }
            return ($firstB eq ':')
                ? -1
                : $a->[1][$_] cmp $b->[1][$_];
        }
        # we have exhausted the shorter path
        $a->[0] cmp $b->[0]
    } map {
        [ $_, [ split( '/', $_ ) ] ]
    } keys %$routes;

    for my $route ( @sorted_paths ) {
        for my $method ( sort keys $routes->{$route}->%* ) {
            $content .= qq|$method '$route' => sub {\n|;

            if ($method eq 'options') {
                my $allow = join( ",", sort $routes->{$route}{$method}{allow}->@* ) ;
                $content .= qq|  response->header( 'Allow' => '$allow' );\n|
                         .  qq|  return;\n|
                         .  qq|};\n\n|;
                next;
            }

            $content .= $self->_required_params( $routes->{$route}{$method}{parameters} );
            $content .= sprintf('  goto &%s::%s;', $routes->{$route}{$method}->@{ qw/controller method/ } )
                . qq|\n};\n\n|;
        }
    }

    if ( defined $prefix ) {
        $content .= "};\n"
    }

    my $custom = $self->default_custom_content;
    my $target = $self->filename_for_class( $class );

    my $existing = $self->parse_file_with_sig( filename => $target );
    if ( $existing ) {
        # Always overwrite
        $custom = $existing->{custom};
    }

    $self->write_file_with_sig(
        filename => $target,
        content  => $content,
        custom   => $custom
    );
}

my $source_map = {
    formData => 'body_parameters->get_all',
    body     => 'body_parameters->get_all',
    path     => 'route_parameters->get_all',
    header   => 'header',
    query    => 'query_parameters->get_all',
};

my $type_map = {
    string  => 'length($vals[0])',
    integer => '$vals[0] =~ m/^[0-9]+$/',
    boolean => '$vals[0] =~ m/^0|1$/',
};

method _required_params($parameters) {
    my $content = '';

    my $required = {};
    for my $r ( grep { $_->{required} } $parameters->@* ) {
        # TODO handle "schema" entries

        if ( exists $r->{schema} && $r->{schema}->{type} eq 'object' ) {
            for my $rq ( @{ $r->{schema}{required} // [] } ) {

                my $type = $r->{schema}{properties}{$rq}{type};

                croak "Undefined type for $rq" . Dumper $r->{schema}
                  unless defined $type;
                croak "Unknown value for property type '$type' for body param $rq"
                  unless exists $type_map->{ $type };

                $required->{ 'body' }{ $type } //= [];
                push $required->{ 'body' }{ $type }->@*, $rq;
            }
        }
        else {
            # Should probably croak..
            next unless exists $r->{type};
            next if $r->{type} eq 'file';  # files are "special"

            croak "Unknown value for property 'in' for param " . $r->{name}
              unless exists $source_map->{ $r->{in} };
            croak "Unknown value for property 'type' for param " . $r->{name}
              unless exists $type_map->{ $r->{type} };

            $required->{ $r->{in} }{ $r->{type} } //= [];
            push $required->{ $r->{in} }{ $r->{type} }->@*, $r->{name};
        }
    }
    if ( keys $required->%* ) {
        $content .= qq|  my \$errors = {};\n|;
        for my $source ( sort keys $required->%* ) {
            for my $type ( sort keys $required->{$source}->%* ) {
                my $extra = $type_map->{$type};
                for my $param ( sort $required->{$source}{$type}->@* ) {
                    $content .= sprintf
                      '  { my @vals = $_[0]->request->%s(\'%s\'); @vals == 1 && %s or $errors->{\'%s\'}=\'Not specified in request %s\'; }',
                      $source_map->{$source}, $param, $extra, $param, $source;
                      $content .= "\n";
                }
            }
        }
        $content .= qq|  if ( keys %\$errors ) { \$_[0]->response->status(400); return { errors => \$errors } }\n|;
    }

    return $content;
}

1;

__END__

=pod

=encoding utf8

=head1 NAME

SD::OpenAPI::Loader::Dancer2 - load, validate and write out D2 routes for an OpenAPI spec

=head1 SYNOPSIS

  my $loader = SD::OpenAPI::Loader::Dancer2->new();

  # load and verify spec
  $loader->parse( 'mds_swagger_spec.yml' );

  # Dump Dancer2 routes and controller stems
  $loader->make_routes(
      namespace => 'SD::MDS::Backend',
      location  => './lib',
  );

  # TODO: check if all routes have methods in controllers
  $loader->verify_controller_methods();

=cut


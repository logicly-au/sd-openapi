use Test::More;
use Test::Fatal;
use PMHC::OpenAPI::Loader::Dancer2;

my $loader;

subtest "API spec is valid" => sub {

    my $exception = exception {
        $loader = SD::OpenAPI::Loader::Dancer2->new(
            spec => 't/swagger.yaml',
            namespace => 'Test',
            location => './lib',
        );
    };
    is( $exception, undef, "Loaded and validated API spec");
};

subtest "route stubs for all paths" => sub {
    my $routes = $loader->_parse_routes();

    my $controllers = {};
    for my $path ( keys %$routes ) {
        for my $verb ( keys $routes->{$path}->%* ) {
            next if $verb eq 'options';  # programatically generated routes
            my $controller = $routes->{$path}->{$verb}->{controller};
            my $method = $routes->{$path}->{$verb}->{method};
            ok($controller && $method, "groked controller/method for $path $verb");
            require_ok($controller) unless $controllers->{$controller}++;
            can_ok($controller, $method);
        }
    }
};

done_testing();

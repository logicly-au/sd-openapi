package Fixture::App;

use 5.22.0;
use warnings;

use Dancer2;
use Function::Parameters qw( :strict );
use SD::OpenAPI::Live::Dancer2;

set serializer => 'JSON';

my $openapi;

method generate($class: $swagger) {
    $openapi = SD::OpenAPI::Live::Dancer2->new(
        namespace => 'Fixture::App',
        swagger   => $swagger,
    );

    $openapi->make_app(app);

    return to_app;
}

method openapi($class:) {
    return $openapi;
}

{
    package Fixture::App::Controller::Test;
}

1;

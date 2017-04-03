package Fixture::App::Controller::Test;

use 5.22.0;
use warnings;

use Function::Parameters qw( :strict );

method get($app: $params, $metadata) {
    return {
        params => $params,
        metadata => $metadata,
    };
}

1;

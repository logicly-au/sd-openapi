#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use Test::Exception;

use Clone qw(clone);

use SD::OpenAPI::Swagger2 qw(expand_swagger);
use Fixture::BasicSwagger;

my $swagger_with_security_definition = Fixture::BasicSwagger::get_basic_swagger( {
    'securityDefinitions' => {
        'basic_security' => {
            'type' => 'basic'
        },
    },
} );



subtest 'With known security scheme' => sub {
    $swagger_with_security_definition->{security} = [ { basic_security => [] } ];
    my $expanded = expand_swagger( clone $swagger_with_security_definition );
    ok( exists $expanded->{paths}{'/getonly'}{get}{security_expanded}, 'path/method has security scheme assigned' );
};

subtest 'With unknown security scheme' => sub {
    $swagger_with_security_definition->{security} = [ { bad_security => [] } ];
    dies_ok( sub { expand_swagger( clone $swagger_with_security_definition ) } );
};

done_testing();

#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use Clone qw(clone);

use SD::OpenAPI::Swagger2   qw( expand_swagger );
use Fixture::BasicSwagger;

my $swagger_with_security_definition = Fixture::BasicSwagger::get_basic_swagger({
    'securityDefinitions' => {
        'basic_security' => {
            'type' => 'basic'
        },
        'api_key_security' => {
            'name' => 'api-key',
            'in' => 'header',
            'type' => 'apiKey'
        },
        'digest_security' => {
            'name' => 'authorization',
            'in' => 'header',
            'type' => 'apiKey'
        }
    }
});

subtest 'Unchanged without implementation' => sub {
    my $expanded = expand_swagger( clone $swagger_with_security_definition );
    is_deeply( $swagger_with_security_definition, $expanded, 'Nothing to expand' );
};


# This is shorthand for including the 'api_key_security' security, from the definitions, on every path and method
$swagger_with_security_definition->{security} = [ { api_key_security => [] } ];

subtest 'With global security' => sub {
    my $expanded = expand_swagger( clone $swagger_with_security_definition );

    ok( exists $expanded->{paths}{'/getonly'}{get}{security_expanded}, 'path/method has security scheme assigned' );
    is( scalar @{$expanded->{paths}{'/getonly'}{get}{security_expanded}}, 1, 'Only one security scheme on path/method' );
    ok( exists $expanded->{paths}{'/getonly'}{get}{security_expanded}[0]{api_key_security}, 'security scheme on path/method is api_key_security' );

    is( $expanded->{paths}{'/getonly'}{get}{security_expanded}[0]{api_key_security}{name}, 'api-key', 'api_key_security on /getonly/get/security has expected name' );
    is( $expanded->{paths}{'/getandpost'}{get}{security_expanded}[0]{api_key_security}{name}, 'api-key', 'api_key_security on /getandpost/get/security has expected name' );
    is( $expanded->{paths}{'/getandpost'}{post}{security_expanded}[0]{api_key_security}{name}, 'api-key', 'api_key_security on /getandpost/post/security has expected name' );
};



subtest 'With path/method specified security' => sub {
    $swagger_with_security_definition->{paths}{'/getandpost'}{get}{security} = [ { basic_security => [] } ];
    my $expanded = expand_swagger( clone $swagger_with_security_definition );

    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}, 'path/method has security scheme assigned' );
    is( scalar @{$expanded->{paths}{'/getandpost'}{get}{security_expanded}}, 1, 'Only one security scheme on path/method' );
    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}[0]{basic_security}, 'security scheme on path/method is basic_security' );

    is( $expanded->{paths}{'/getonly'}{get}{security_expanded}[0]{api_key_security}{name}, 'api-key', 'security on /getonly/get is global still' );
    is( $expanded->{paths}{'/getandpost'}{post}{security_expanded}[0]{api_key_security}{name}, 'api-key', 'security on /getandpost/post is global still' );
};


=for comment

When the two methods are listed in security as two separate elements in an array, then you can fulfill either of them:

paths:
    /getandpost:
        get:
            security:
            - api_key_security: []
            - basic_security: []
=cut

subtest 'Any-of-two security methods' => sub {
    $swagger_with_security_definition->{paths}{'/getandpost'}{get}{security} = [ { api_key_security => [] }, { basic_security => [] } ];
    my $expanded = expand_swagger( clone $swagger_with_security_definition );

    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}, 'path/method has security scheme assigned' );
    is( scalar( @{$expanded->{paths}{'/getandpost'}{get}{security_expanded}} ), 2, 'Two security schemes on path/method' );
    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}[0]{api_key_security}, 'security scheme on path/method allows api_key_security' );
    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}[1]{basic_security}, 'security scheme on path/method allows basic_security' );
};


=for comment

When the two methods are listed in security as a single element in the array, then you must fulfill both of them:

paths:
    /getandpost:
        get:
            security:
            - api_key_security: []
              basic_security: []
=cut


subtest 'All-of-two security methods' => sub {
    $swagger_with_security_definition->{paths}{'/getandpost'}{get}{security} = [ { api_key_security => [], basic_security => [] } ];
    my $expanded = expand_swagger( clone $swagger_with_security_definition );

    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}, 'path/method has security scheme assigned' );
    is( scalar @{$expanded->{paths}{'/getandpost'}{get}{security_expanded}}, 1, 'Only one security scheme on path/method' );
    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}[0]{api_key_security}, 'security scheme on path/method requires api_key_security' );
    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}[0]{basic_security}, 'security scheme on path/method requires basic_security' );
};


=for comment

Now we mix them. We will allow both api_key and basic OR JUST digest:

paths:
    /getandpost:
        get:
            security:
            - api_key_security: []
              basic_security: []
            - digest_security: []
=cut

subtest 'All-of-two or one of another security methods' => sub {
    $swagger_with_security_definition->{paths}{'/getandpost'}{get}{security} = [ { api_key_security => [], basic_security => [] }, { digest_security => [] } ];
    my $expanded = expand_swagger( clone $swagger_with_security_definition );

    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}, 'path/method has security scheme assigned' );
    is( scalar @{$expanded->{paths}{'/getandpost'}{get}{security_expanded}}, 2, 'Two security schemes on path/method' );
    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}[0]{api_key_security}, 'security scheme on path/method requires api_key_security' );
    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}[0]{basic_security}, 'security scheme on path/method requires basic_security' );
    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}[1]{digest_security}, 'security scheme on path/method allows digest_security' );
};


done_testing();


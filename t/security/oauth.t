#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use Clone qw(clone);

use SD::OpenAPI::Swagger2 qw(expand_swagger);
use Fixture::BasicSwagger;

my $swagger_with_security_definition = Fixture::BasicSwagger::get_basic_swagger( {
    'securityDefinitions' => {
        "oauth_security" => {
            "type"             => "oauth2",
            "authorizationUrl" => "http://example.com/api/oauth/dialog",
            "flow"             => "implicit",
            "scopes"           => {
                "write:things" => "modify things in your account",
                "read:things"  => "read your things"
            }
        }
    }
} );

subtest 'Unchanged without implementation' => sub {
    my $expanded = expand_swagger( clone $swagger_with_security_definition );
    is_deeply( $swagger_with_security_definition, $expanded, 'Nothing to expand' );
};


subtest 'With oAuth security' => sub {
    $swagger_with_security_definition->{paths}{'/getandpost'}{get}{security} = [ { oauth_security => [ 'read:things' ] } ];
    $swagger_with_security_definition->{paths}{'/getandpost'}{post}{security} = [ { oauth_security => [ 'write:things' ] } ];
    my $expanded = expand_swagger( $swagger_with_security_definition );

    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}, 'path/method has security scheme assigned' );
    ok( exists $expanded->{paths}{'/getandpost'}{get}{security_expanded}[0]{oauth_security}, 'security scheme on path/method requires oauth_security' );
    is( scalar @{ $expanded->{paths}{'/getandpost'}{get}{security_expanded}[0]{oauth_security}{scopes} }, 1, 'There is only one scope on getandpost/get' );
    is( $expanded->{paths}{'/getandpost'}{get}{security_expanded}[0]{oauth_security}{scopes}[0], 'read:things', 'You need the read:things scope to getandpost/get' );

    ok( exists $expanded->{paths}{'/getandpost'}{post}{security_expanded}, 'path/method has security scheme assigned' );
    ok( exists $expanded->{paths}{'/getandpost'}{post}{security_expanded}[0]{oauth_security}, 'security scheme on path/method requires oauth_security' );
    is( scalar @{ $expanded->{paths}{'/getandpost'}{post}{security_expanded}[0]{oauth_security}{scopes} }, 1, 'There is only one scope on getandpost/post' );
    is( $expanded->{paths}{'/getandpost'}{post}{security_expanded}[0]{oauth_security}{scopes}[0], 'write:things', 'You need the write:things scope to getandpost/post' );
};


done_testing();


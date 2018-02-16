package Fixture::BasicSwagger;
use strict;
use warnings FATAL => 'all';

use Clone qw(clone);
use Hash::Merge;

my $basic_swagger = {
    swagger => '2.0',
    info    => {
        title   => 'Test',
        version => '0.0.0',
    },
    paths   => {
        '/getonly' => {
            get => {
                operationId => 'GetOnly::get',
                parameters  => [],
                responses   => {
                    200 => {
                        description => 'ok',
                    },
                },
            },
        },
        '/getandpost' => {
            get => {
                operationId => 'GetAndPost::get',
                parameters  => [],
                responses   => {
                    200 => {
                        description => 'ok',
                    },
                },
            },
            post => {
                operationId => 'GetAndPost::post',
                parameters  => [],
                responses   => {
                    200 => {
                        description => 'ok',
                    },
                },
            },
        },
    },
};

sub get_basic_swagger {
    my $merge = shift // {};
    return Hash::Merge::merge( clone($basic_swagger), $merge );
}

1;
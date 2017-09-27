use SD::OpenAPI::Test;
use Fixture::App;

my $swagger = {
    swagger => '2.0',
    info => {
        title => 'Test',
        version => '0.0.0',
    },
    paths => {
        '/foo' => {
            get => {
                operationId => 'Test::get',
                responses => {
                    200 => {
                        description => 'ok',
                    },
                },
            },
        },
    },
};

lives_ok { Fixture::App->generate($swagger) } 'Make app ok';

done_testing;

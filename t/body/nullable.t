use SD::OpenAPI::Test;
use Fixture::Agent;
use Function::Parameters qw( :strict );

# Swagger is being rather picky about boolean values.
my $true = (2 + 2 == 4);

my $swagger = {
    swagger => '2.0',
    info => {
        title => 'Test',
        version => '0.0.0',
    },
    paths => {
        '/foo' => {
            post => {
                operationId => 'Test::put',
                description => 'Test nullable',
                parameters => [
                    {
                        in       => 'body',
                        name     => 'body',
                        schema   => {
                            type  => 'array',
                            items => {
                                '$ref' => '#/definitions/item',
                            },
                        },
                        required => $true,
                    },
                ],
                responses => {
                    200 => {
                        description => 'ok',
                    },
                },
            },
        },
    },
    definitions => {
        item => {
            type  => 'object',
            properties => {
                id => {
                    type => 'integer',
                },
                required_and_nullable => {
                    type         => 'string',
                    'x-nullable' => $true,
                },
                required_not_nullable => {
                    type         => 'string',
                },
                optional_and_nullable => {
                    type         => 'string',
                    'x-nullable' => $true,
                },
                optional_not_nullable => {
                    type         => 'string',
                },
            },
            required => [qw( id required_and_nullable required_not_nullable )],
        },
    },
};

my $agent = Fixture::Agent->new(swagger => $swagger);

my %good = (
    required_and_nullable => undef,
    required_not_nullable => 'ok',
);

my @good_data = (
    { id => 1, %good                                    },
    { id => 2, %good, optional_and_nullable => undef,   },
    { id => 3, %good, optional_not_nullable => 'ok',    },
    { id => 4, %good, required_and_nullable => '',      },
    { id => 5, %good, required_not_nullable => '',      },
);

my $r = $agent->post('/foo', \@good_data);
is($r->code, 200, 'Got /foo ok');
eq_or_diff($r->json->{params}->{body}, \@good_data, 'Good data as expected');

# Each row should contain one error.
my @bad_data = (
    { id => 1, required_and_nullable => undef },
    { id => 2, %good, required_not_nullable => undef },
    { id => 3, %good, optional_not_nullable => undef },
);

$r = $agent->post('/foo', \@bad_data);
is($r->code, 400, 'Bad data not allowed');
is(scalar keys %{ $r->json->{errors} }, scalar @bad_data, 'All errors found');

done_testing;

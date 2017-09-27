use SD::OpenAPI::Test;
use SD::OpenAPI::Live::Dancer2 qw( );
use Function::Parameters qw( :strict );
use Clone qw( clone );

# Swagger is being rather picky about boolean values.
my $true = (2 + 2 == 4);
my $false = !$true;

my $path_param = 'bar';
my $path = "/foo/{$path_param}";
my $method = 'post';

my $base_swagger = {
    swagger => '2.0',
    info => {
        title => 'Test',
        version => '0.0.0',
    },
    paths => {
        $path => {
            $method => {
                operationId => 'Test::put',
                description => 'Test nullable',
                parameters => [
                    {
                        name     => $path_param,
                        in       => 'path',
                        type     => 'integer',
                        required => $true,
                    },
                    {
                        name     => 'body',
                        in       => 'body',
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
            },
            required => [qw( id )],
        },
    },
};

#------------------------------------------------------------------------------

lives_ok { validate($base_swagger) } 'Base swagger is fine';

{
    my $swagger = clone($base_swagger);
    find_param($swagger, sub { $_->{name} eq $path_param })->{name} = 'not';

    throws_ok { validate($swagger) }
        qr/path parameter "$path_param" not in parameter list/,
        'Caught missing path parameter';
}

{
    my $in = 'query';
    my $swagger = clone($base_swagger);
    find_param($swagger, sub { $_->{name} eq $path_param })->{in} = $in;

    throws_ok { validate($swagger) }
        qr/path parameter "$path_param" in $in, not in path/,
        "Caught path parameter declared as $in";
}

{
    my $swagger = clone($base_swagger);
    find_param($swagger,
        sub { $_->{name} eq $path_param })->{required} = $false;

    # This one gets caught by JSON::Validator, which throws a crappy message.
    dies_ok { validate($swagger) } 'Caught non-required path parameter';
}

{
    my $swagger = clone($base_swagger);
    my $param = clone(find_param($swagger, sub { $_->{name} eq $path_param }));
    $param->{name} .= '2';
    push(@{ handler($swagger)->{parameters} }, $param);

    throws_ok { validate($swagger) }
        qr/path parameter "$param->{name}" not in path/,
        "Caught path parameter not in path";
}

{
    my $bad_method = 'get';
    my $swagger = clone($base_swagger);
    $swagger->{paths}->{$path}->{$bad_method} =
        delete $swagger->{paths}->{$path}->{$method};

    throws_ok { validate($swagger) }
        qr/body parameters not allowed in $bad_method request/,
        "Caught body parameter in $bad_method request";
}

{
    my $swagger = clone($base_swagger);
    my $param = clone(find_param($swagger, sub { $_->{in} eq 'body' }));
    $param->{name} .= '2';
    push(@{ handler($swagger)->{parameters} }, $param);

    throws_ok { validate($swagger) }
        qr/only one body parameter allowed/,
        'Caught multiple body parameters';
}

{
    my $swagger = clone($base_swagger);
    my $bad_name = 'foo';
    find_param($swagger, sub { $_->{in} eq 'body' })->{name} = $bad_name;

    throws_ok { validate($swagger) }
        qr/body parameters must be named "body", not "$bad_name"/,
        'Caught body parameter named something other than "body"';
}

done_testing;

#------------------------------------------------------------------------------

fun validate($swagger) {
    my $openapi = SD::OpenAPI::Live::Dancer2->new(swagger => clone($swagger));
    $openapi->spec;
}

fun handler($swagger) {
    return $swagger->{paths}->{$path}->{$method};
}

fun find_param($swagger, $pred) {
    my @params = @{ handler($swagger)->{parameters} };
    my ($ret) = grep { $pred->() } @params;
    return $ret;
}


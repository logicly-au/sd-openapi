use SD::OpenAPI::Test;
use SD::OpenAPI::Live::Dancer2 qw( );
use Fixture::Agent;
use Function::Parameters qw( :strict );

# Swagger is being rather picky about boolean values.
my $true = (2 + 2 == 4);
my $false = !$true;

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
                description => 'Test nullable',
                parameters => [
                    {
                        name     => 'no-limit',
                        in       => 'query',
                        type     => 'string',
                    },
                    {
                        name     => 'min-3',
                        in       => 'query',
                        type     => 'string',
                        minLength => 3,
                    },
                    {
                        name     => 'max-6',
                        in       => 'query',
                        type     => 'string',
                        maxLength => 6,
                    },
                    {
                        name     => 'min-3-max-6',
                        in       => 'query',
                        type     => 'string',
                        minLength => 3,
                        maxLength => 6,
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
};

#------------------------------------------------------------------------------

my $agent = Fixture::Agent->new(swagger => $swagger);

my @strings = ( '', qw( a ab abc abcd abcde abcdef abcdefg abcdefgh ) );

my @bad_values = (
    [ 'min-3'       => [ grep { length($_) < 3 } @strings ] ],
    [ 'max-6'       => [ grep { length($_) > 6 } @strings ] ],
    [ 'min-3-max-6' => [ grep { length($_) < 3 || length($_) > 6 } @strings ] ],
);

for (@bad_values) {
    my ($param, $values) = @$_;
    for my $value (@$values) {
        my $r = $agent->get("/foo?$param=$value");
        is($r->code, 400, "Caught bad $param value \"$value\"");
    }
}

my @good_values = (
    [ 'no-limit'    => \@strings ],
    [ 'min-3'       => [ grep { length($_) >= 3 } @strings ] ],
    [ 'max-6'       => [ grep { length($_) <= 6 } @strings ] ],
    [ 'min-3-max-6' =>
                [ grep { length($_) >= 3 && length($_) <= 6 } @strings ] ],
);

for (@good_values) {
    my ($param, $values) = @$_;
    for my $value (@$values) {
        my $r = $agent->get("/foo?$param=$value");
        is($r->code, 200, "Good $param value \"$value\" succeeds");
    }
}

done_testing;

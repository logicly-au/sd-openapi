use SD::Test;
use Fixture::Agent;
use Function::Parameters qw( :strict );

fun make_param($type) {
    my $param = {
        name    => $type,
        type    => $type,
        in      => 'query',
    };

    if ($type !~ /boolean|integer|string/) {
        $param->{type}   = 'string';
        $param->{format} = $type;
    }

    return $param;
}

sub make_params {
    my @types = qw( integer boolean string date date-time range sort );
    return [ map { make_param($_) } @types ];
}

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
                parameters => make_params(),
                responses => {
                    200 => {
                        description => 'ok',
                    },
                },
            },
        },
    },
};


my $agent = Fixture::Agent->new(swagger => $swagger);

note 'Check bad values';
my @bad_values = (
    [ integer => 'xxx' ],
    [ integer => ''    ],
    [ integer => 'x3'  ],
    [ integer => '3x'  ],
    [ integer => 3.142 ],
    [ integer => -2147483649 ],
    [ integer => +2147483648 ],
);

for (@bad_values) {
    my ($param, $value) = @$_;
    my $r = $agent->get("/foo?$param=$value");
    is($r->code, 400, "Caught bad $param value \"$value\"");
}

note 'Check good values';
my @good_values = (
    [ integer => -2147483648 ],
    [ integer => +2147483647 ],
);

for (@good_values) {
    my ($param, $value) = @$_;
    my $r = $agent->get("/foo?$param=$value");
    is($r->code, 200, "Good $param value \"$value\" succeeds");
    eq_or_diff($r->json->{params}, { $param => $value },
        "and inflates correctly");
}


done_testing;

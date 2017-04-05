use SD::Test;
use Fixture::Agent;
use Function::Parameters qw( :strict );

{
    # Force DateTime objects to serialize in a way that makes testing easy.
    no warnings 'once';
    *{DateTime::TO_JSON} = method() {
        # For the purposes of round-tripping, if something can be a date,
        # stringify it as one.
        if (($self->second == 0)
                && ($self->minute == 0)
                && ($self->hour == 0)) {
            return $self->strftime('%F');
        }
        return $self->strftime('%FT%TZ');
    };
}

my %params = (
    boolean    => 1,
    integer    => '666',
    string     => 'sixsixsix',
    date       => '2017-04-03',
    'date-time' => '2017-04-03T17:33:15Z',
    range      => [ '1-100', [ 1, 100 ] ],
    sort       => [ '+foo,-bar', [ [ '+', 'foo' ], [ '-', 'bar' ] ] ],
);

my $true = (2 + 2 == 4);

fun make_property($type, $value) {
    if (ref $value) {
        $value = $value->[0];
    }
    my $param = {
        type    => $type,
        default => $value,
    };

    if ($type !~ /boolean|integer|string/) {
        $param->{type}   = 'string';
        $param->{format} = $type;
    }

    return $param;
}

sub make_definition {
    return {
        type  => 'object',
        properties => {
            map { $_ => make_property($_, $params{$_}) } keys %params
        },
        required => [ sort keys %params ],
    };
}

my $swagger = {
    swagger => '2.0',
    info => {
        title => 'Test',
        version => '0.0.0',
    },
    paths => {
        '/foo' => {
            put => {
                operationId => 'Test::put',
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
        item => make_definition(),
    },
};

my $agent = Fixture::Agent->new(swagger => $swagger);

my $r = $agent->put('/foo', [ { } ] );
is($r->code, 200, 'Put /foo ok');

my %expected;
while (my ($key, $value) = each %params) {
    $expected{$key} = ref $value ? $value->[1] : $value;
}

eq_or_diff(
    $r->json->{params}->{body},
    [ \%expected ],
    'All default params filled in');

done_testing;

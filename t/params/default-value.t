use SD::OpenAPI::Test;
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
    integer    => 666,
    string     => 'sixsixsix',
    date       => '2017-04-03',
    'date-time' => '2017-04-03T17:33:15Z',
    range      => [ '1-100', [ 1, 100 ] ],
    sort       => [ '+foo,-bar', [ [ '+', 'foo' ], [ '-', 'bar' ] ] ],
);

fun make_param($type, $value) {
    if (ref $value) {
        $value = $value->[0];
    }
    my $param = {
        name    => $type,
        type    => $type,
        default => $value,
        in      => 'query',
    };

    if ($type !~ /boolean|integer|string/) {
        $param->{type}   = 'string';
        $param->{format} = $type;
    }

    return $param;
}

sub make_params {
    return [ map { make_param($_, $params{$_}) } keys %params ];
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

my $r = $agent->get('/foo');
is($r->code, 200, 'Got /foo ok');

while (my ($name, $value) = each %params) {
    my $message = "Got $name=$value";
    if (ref $value) {
        $message = "Got $name=$value->[0]";
        $value = $value->[1];
    }
    eq_or_diff($r->json->{params}->{$name}, $value, $message);
}

done_testing;

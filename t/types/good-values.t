use SD::OpenAPI::Test;
use Function::Parameters    qw( :strict   );
use JSON::MaybeXS;

use SD::OpenAPI::Types  qw( check_type prepare_handler );

my $true  = JSON->true;
my $false = JSON->false;

my @good_values = (
    {
        type     => { type => 'string' },
        values => [
            [ '' => '' ],
            [ 'hello' => 'hello' ],
        ],
    },
    {
        type     => { type => 'string', minLength => 3, maxLength => 5 },
        values => [
            [ 'abc' => 'abc' ],
            [ 'abcd' => 'abcd' ],
            [ 'abcde' => 'abcde' ],
        ],
    },
    {
        type     => { type => 'string', pattern => '^a?b+c*$' },
        values => [
            [ 'abc' => 'abc' ],
            [ 'ab' => 'ab' ],
            [ 'b' => 'b' ],
            [ 'abbbccc' => 'abbbccc' ],
            [ 'abccc' => 'abccc' ],
            [ 'bbccc' => 'bbccc' ],
            [ 'bccc' => 'bccc' ],
        ],
    },
    {
        type     => { type => 'string', enum => [qw( foo bar )] },
        values => [
            [ 'foo'    => 'foo' ],
            [ 'bar'    => 'bar' ],
        ],
    },
    {
        type     => { type => 'integer' },
        values => [
            [ '123'   => 123 ],
            [ '-123'  => -123 ],
            [ '+123'  => 123 ],
            [ '0'     => 0 ],
            [ '-2147483648' => -2147483648 ],
            [ '+2147483647' => 2147483647 ],
            [ '2147483647' => 2147483647 ],
        ],
    },
    {
        type    => { type => 'integer', minimum => -10, maximum => 20 },
        values => [
            [ '-10'  => -10 ],
            [ '-9'   => -9 ],
            [ '+19'  => 19 ],
            [ '+20'  => 20 ],
        ],
    },
    {
        type    => { type => 'integer', format => 'int64' },
        values  => [
            [ '9223372036854775806' => 9223372036854775806 ],
            [ '9223372036854775807' => 9223372036854775807 ],
            [ '+9223372036854775807' => 9223372036854775807 ],
            [ '-9223372036854775807' => -9223372036854775807 ],
            [ '-9223372036854775808' => -9223372036854775808 ],
        ],
    },
    {
        type    => { type => 'boolean' },
        values  => [
            [ $true  => $true  ],
            [ $false => $false ],
            [ 'true' => $true ],
            [ 'false' => $false ],
            [ '1' => $true ],
            [ '0' => $false ],
        ],
    },
    {
        type    => { type => 'range' },
        values  => [
            [ '1-100', [ 1, 100 ] ],
            [ '2-',    [ 2, undef ] ],
        ],
        deep => 1,
    },
    {
        type    => { type => 'sort' },
        values  => [
            [ 'foo'  => [ [ '+', 'foo' ] ] ],
            [ '-foo' => [ [ '-', 'foo' ] ] ],
            [ '+foo' => [ [ '+', 'foo' ] ] ],
            [ '+foo,-bar' => [ [ '+', 'foo' ], [ '-', 'bar' ] ] ],
            [ '-foo,+bar' => [ [ '-', 'foo' ], [ '+', 'bar' ] ] ],
            [ '-foo,bar' => [ [ '-', 'foo' ], [ '+', 'bar' ] ] ],
            [ 'foo,-bar' => [ [ '+', 'foo' ], [ '-', 'bar' ] ] ],
            [ '-foo,-bar' => [ [ '-', 'foo' ], [ '-', 'bar' ] ] ],
            [ '-foo,-bar,+foo' =>
                [ [ '-', 'foo' ], [ '-', 'bar' ], [ '+', 'foo' ] ] ],
        ],
        deep => 1,
    },
    {
        type    => { type => 'date' },
        values  => [
            [ '2017-01-01' => DateTime->new(year => 2017) ],
            [ '2017-02-01' => DateTime->new(year => 2017, month => 2) ],
            [ '2017-01-02' => DateTime->new(year => 2017, day => 2) ],
            [ '2017-02-03'
                => DateTime->new(year => 2017, month => 2, day => 3) ],
        ],
    },
    {
        type    => { type => 'date', 'x-minimum' => '2016-07-01', 'x-maximum' => '2017-06-30' },
        values  => [
            [ '2017-02-03'
                => DateTime->new(year => 2017, month => 2, day => 3) ],
        ],
    },
    {
        type    => { type => 'date-time' },
        values  => [
            [ '2017-02-03'
                => DateTime->new(year => 2017, month => 2, day => 3) ],
            [ '2017-02-03T00:00:00Z'
                => DateTime->new(year => 2017, month => 2, day => 3) ],
            [ '2017-02-03T04:05:06Z'
                => DateTime->new(year => 2017, month => 2, day => 3,
                    hour => 4, minute => 5, second => 6) ],
            [ '2017-02-03T04:05:06+10:00'
                => DateTime->new(year => 2017, month => 2, day => 3,
                    hour => 4, minute => 5, second => 6, time_zone => 'Australia/Brisbane') ],
        ],
    },
);

for my $set (@good_values) {
    my $name = 'foo';

    my $type = $set->{type};
    $type->{name} = $name;
    prepare_handler({ parameters => [ $type ] });

    my $typename = $type->{check_type};

    for (@{ $set->{values} }) {
        my ($value, $expected) = @$_;
        my $got = check_type($value, $type, $name);
        my $msg = "$value parses as $typename";
        if ($set->{deep}) {
            eq_or_diff($got, $expected, $msg);
        }
        else {
            is($got, $expected, $msg);
        }
    }
}

done_testing;

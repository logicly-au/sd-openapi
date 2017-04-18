use SD::Test;
use Function::Parameters    qw( :strict   );
use Test::Fatal             qw( exception );

use SD::OpenAPI::Types  qw( check_type prepare_handler );

my @bad_values = (
    {
        type    => { type => 'string', minLength => 3 },
        message => 'must be a string at least 3 characters long',
        values  => ['', qw( a ab )],
    },
    {
        type    => { type => 'string', maxLength => 8 },
        message => 'must be a string of no more than 8 characters',
        values  => [qw( abcdefghi abcdefghij )],
    },
    {
        type    => { type => 'string', minLength => 3, maxLength => 8 },
        message => 'must be a string between 3 and 8 characters long',
        values  => ['', qw( a ab abcdefghi abcdefghij )],
    },
    {
        type    => { type => 'string', maxLength => 8 },
        message => 'must be a string of no more than 8 characters',
        values  => [qw( abcdefghi abcdefghij )],
    },
    {
        message => 'must be a string matching /^a?b+c*$/',
        type    => { type => 'string', pattern => '^a?b+c*$' },
        values  => ['', qw( aab cccba abbccd )],
    },
    {
        message => 'must be a string in the list: foo, bar',
        type    => { type => 'string', enum => [qw( foo bar )] },
        values  => ['', 'foo-not', 'not-foo', 'bar-not', 'not-bar' ],
    },
    {
        type    => { type => 'integer' },
        message => 'must be an int32',
        values => [
            '', qw( xxx x3 3x 3.14 -2147483649 +2147483648 2147483648)
        ],
    },
    {
        type    => { type => 'integer', minimum => 10 },
        message => 'must be an int32 no less than 10',
        values  => [qw( 8 9 -9 -10 -11)],
    },
    {
        type    => { type => 'integer', maximum => 20 },
        message => 'must be an int32 no greater than 20',
        values  => [qw( 21 22)],
    },
    {
        type    => { type => 'integer', minimum => 10, maximum => 20 },
        message => 'must be an int32 in range [10, 20]',
        values  => [qw( 8 9 -9 -10 -11 21 22)],
    },
    {
        type    => { type => 'integer', format => 'int64' },
        message => 'must be an int64',
        values  => ['', qw(
            9223372036854775808 +9223372036854775808 -9223372036854775809
            -9323372036854775810
        )],
    },
    {
        type    => { type => 'boolean' },
        message => 'must be a boolean value',
        values  => ['', qw(
            True False 2 zero yes no
        )],
    },
    {
        type    => { type => 'range' },
        message => 'must be a range (eg. 0-599, or 100-)',
        values  => ['', qw(
            123 -123 100-99 foo a10-20 10-20z
        )],
    },
    {
        type    => { type => 'sort' },
        message => 'must be a comma-separated list of field/+field/-field',
        values  => [ # qw( freaks out over the commas here
            'foo,', ',foo', 'foo,,foo', '*foo',
        ],
    },
    {
        type    => { type => 'sort', 'x-sort-fields' => [qw( aa bb )] },
        message => 'must be a comma-separated list of field/+field/-field. Valid fields are: aa, bb',
        values  => [ # qw( freaks out over the commas here
            'foo', 'aa,foo,bb', 'foo,aa,bb', 'aa,bb,foo'
        ],
    },
    {
        type    => { type => 'date' },
        message => 'must be a YYYY-MM-DD date string',
        # Note that invalid days fail, eg. Feb 30
        values  => ['', qw(
            2017-02-29 2017-13-01 2017/01/01 2017-31-12 Monday
            2017-01-01T12:00:00Z
        )],
    },
    {
        type    => { type => 'date-time' },
        message => 'must be an ISO8601-formatted datetime string',
        # Note that invalid days fail, eg. Feb 30
        values  => ['', qw(
            2017/01/01 Monday 2017-01-01T25:00:00Z
            2017-13-01T00:00:00Z 2017-01-32T00:00:00Z
        )],
    },
);

for my $set (@bad_values) {
    my $name = 'foo';

    my $type = $set->{type};
    $type->{name} = $name;
    prepare_handler({ parameters => [ $type ] });

    my $msg = $set->{message};
    for my $value (@{ $set->{values} }) {
        eq_or_diff(
            exception { check_type($value, $type, $name) },
            { $name => $msg },
            "\"$value\" fails with \"$msg\"",
        );
        my $out;
        if (!exception { $out = check_type($value, $type, $name) }) {
            diag "$value -> $out";
        }
    }
}

done_testing;

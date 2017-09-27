use SD::OpenAPI::Test;
use Function::Parameters    qw( :strict   );
use Test::Fatal             qw( exception );

use SD::OpenAPI::Types  qw( check_type prepare_handler );

my $name = 'foo';

my @bad_types = (
    {
        type    => { type => 'string', pattern => '*' },
        error  => { "$name.pattern" => 'Quantifier follows nothing in regex' },
        message => 'bad regex in pattern',
    },
);

for my $set (@bad_types) {

    my $type = $set->{type};
    $type->{name} = $name;

    eq_or_diff(
        exception { prepare_handler({ parameters => [ $type ] }) },
        [ $set->{error} ],
        "$set->{type}->{type}: $set->{message}"
    );
}

done_testing;

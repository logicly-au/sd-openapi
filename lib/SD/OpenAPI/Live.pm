package SD::OpenAPI::Live;
use 5.22.0;
use warnings;

use Moo;

use Carp                    qw( croak );
use Log::Any                qw( $log );
use SD::OpenAPI::Swagger2   qw( expand_swagger validate_swagger );
use Try::Tiny;

use Function::Parameters    qw( :strict );

has swagger_path => (
    is => 'ro',
    required => 1,
);

has spec => (
    is => 'lazy',
);

method _build_spec {
    my $swagger = YAML::XS::LoadFile($self->swagger_path);

    try {
        $swagger = validate_swagger($swagger);
    }
    catch {
        croak $self->swagger_path . "$_\n";
    };

    return expand_swagger($swagger);
}

1;

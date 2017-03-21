package SD::OpenAPI::Live;
use 5.22.0;
use warnings;

use Moo;

use Carp                    qw( croak );
use JSON::MaybeXS           qw( );
use Log::Any                qw( $log );
use Path::Tiny              qw( path );
use YAML::XS                qw( );
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
    my $content = path($self->swagger_path)->slurp_utf8;
    my $swagger = ($content =~ /^\s*\{/s)
        ? JSON::MaybeXS::decode_json($content)
        : YAML::XS::Load($content);

    try {
        $swagger = validate_swagger($swagger);
    }
    catch {
        croak $self->swagger_path . "$_\n";
    };

    return expand_swagger($swagger);
}

1;

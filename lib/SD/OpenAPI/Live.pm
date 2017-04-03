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
    predicate => 1,
);

has swagger => (
    is => 'lazy',
    builder => method() {
        die "Must specify swagger or swagger_path"
            unless $self->has_swagger_path;

        my $content = path($self->swagger_path)->slurp_utf8;
        return ($content =~ /^\s*\{/s)
            ? JSON::MaybeXS::decode_json($content)
            : YAML::XS::Load($content);
    },
);

has spec => (
    is => 'lazy',
    builder => method() {
        my $swagger = $self->swagger;
        try {
            $swagger = validate_swagger($swagger);
        }
        catch {
            my $path = $self->swagger_path // '(swagger)';
            croak "$path $_\n";
        };

        return expand_swagger($swagger);
    },
);

1;

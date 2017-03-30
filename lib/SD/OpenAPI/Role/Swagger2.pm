package SD::OpenAPI::Role::Swagger2;
use 5.22.0;
use Moo::Role;
use Function::Parameters qw(:strict);

use Carp qw(croak);
use Data::Dumper;
use HTTP::Tiny qw();
use JSON::Validator qw();
use JSON::MaybeXS qw();
use Path::Tiny qw(path);
use YAML::XS qw();

has _openapi_specification_uri => (
    is => 'ro',
    default => 'http://swagger.io/v2/schema.json',
);

has _openapi_schema => (
    is => 'lazy',
);

has spec => (
    is => 'ro',
    coerce => sub {
        return ( ref $_[0] eq 'HASH' )
          ? $_[0]
          : _load_spec($_[0]);
    },
);

method _build__openapi_schema() {
    my $res = HTTP::Tiny->new->get( $self->_openapi_specification_uri );
    croak "Failed to fetch OpenAPI schema specification"
      unless $res->{success};
    return JSON::MaybeXS::decode_json( $res->{content} );
}

method _validate_spec() {
    my $validator = JSON::Validator->new();

    # YAML doesn't have an equivilent boolean notation as JSON does
    $validator->coerce(booleans => 1);
    $validator->schema( $self->_openapi_schema );

    # validate spec against the OpenAPI schema
    my @errors = $validator->validate( $self->spec );
    croak "Failed to validate supplied spec against OpenAPI schema"
      if scalar @errors;

    # DIRTY: *in-place* resolve of references
    $validator->schema($self->spec);
}

fun _load_spec($source) {
    unless ( defined $source && $source ) {
        croak "No source for spec provided"
    }

    my $content;
    # Load spec source from a URI or local file
    if ( $source =~ m!^http! ) {
        my $res = HTTP::Tiny->new->get($source);
        croak "Failed to fetch source for spec"
          unless $res->{success};
          $content = $res->{content};
    }
    else {
        my $file = path($source);
        croak "$source does not exist (or not a file)"
          unless $file->is_file;

        $content = $file->slurp_raw;
    }

    return ( $content =~ m/^\s*\{/s )
            ? JSON::MaybeXS::decode_json( $content )
            : YAML::XS::Load( $content );
}

1;

=pod

=encoding utf8

=head1 NAME

SD::OpenAPI::Role::Swagger2 - parse, validate and manipulate OpenAPI specs

=cut

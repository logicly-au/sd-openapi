package SD::OpenAPI::Loader;
use 5.22.0;
use Moo;
extends 'SD::OpenAPI';
use Function::Parameters qw(:strict);

with 'SD::OpenAPI::Role::Swagger2', 'SD::OpenAPI::Role::FileGenerator';

method BUILD($args={}) {
    # dies on failure
    $self->_validate_spec;
}

1;

=pod

=encoding utf8

=head1 NAME

SD::OpenAPI::Loader - load and validate an OpenAPI spec

=head1 SYNOPSIS

  # load and verify spec
  my $loader = SD::OpenAPI::Loader->new(
      spec => 'mds_swagger_spec.yml'
  );

=cut


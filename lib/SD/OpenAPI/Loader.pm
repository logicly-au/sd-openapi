package SD::OpenAPI::Loader;
use 5.24.0;
use Moo;
use Function::Parameters qw(:strict);

our $VERSION = '0.0.1';

method version {
    my $class = ref $self || $self;
    return eval "\$${class}::VERSION";
}

with 'SD::OpenAPI::Role::Swagger2', 'SD::OpenAPI::Role::FileGenerator';

method BUILD {
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


#!/usr/bin/env perl
use 5.24.0;
use Moo;
use MooX::Options;

use lib "../lib";

use SD::OpenAPI::Loader::Dancer2;

option file => (
    is       => 'ro',
    format   => 's',
    default  => 'swagger.yaml',
    doc      => 'Swagger 2.0 specification file',
);

option namespace => (
    is       => 'ro',
    required => 1,
    format   => 's',
    doc      => 'Namespace for generated classes',
);

option location => (
    is       => 'ro',
    format   => 's',
    default  => './lib',
    doc      => 'Location of generated code',
);

sub run {
    my ($self) = @_;

    my $loader = SD::OpenAPI::Loader::Dancer2->new(
      spec      => $self->file,
      namespace => $self->namespace,
      location  => $self->location // ,
    );

    $loader->make_routes();
}


main->new_with_options->run;
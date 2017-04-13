package SD::OpenAPI;
use 5.22.0;
use Moo;
use Function::Parameters qw(:strict);

our $VERSION = '0.0.28';

method version() {
    my $class = ref $self || $self;
    return eval "\$${class}::VERSION";
}

1;

__END__

=encoding utf-8

=head1 NAME

SD::OpenAPI - Strategic Data's OpenAPI utilities.

=head1 LICENSE

Copyright (C) Strategic Data.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR

Strategic Data E<lt>support@strategicdata.com.auE<gt>

=cut

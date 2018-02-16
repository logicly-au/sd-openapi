#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';
use 5.20.0;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper::Concise   qw( Dumper );
use SD::OpenAPI::Swagger2   qw( expand_swagger );
use YAML::XS                qw( LoadFile );

my ($filename) = @ARGV
    or die "usage: $0 filename";

my $swagger = LoadFile($filename);

my $expanded = expand_swagger($swagger);

print Dumper($expanded);

1;
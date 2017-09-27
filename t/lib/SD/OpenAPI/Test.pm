package SD::OpenAPI::Test;

use strict;
use warnings;

use Test::Most;             # also gives us strict + warnings
use Test::FailWarnings;     # no need to import this

use Import::Into;

sub import {
    my $target = caller;
    Test::Most->import::into($target);
}

1;

package Dancer2::Plugin::OpenAPI;

use 5.22.0;
use warnings;

use Dancer2::Plugin;
use SD::OpenAPI::Live::Dancer2   qw( );

has swagger => (
    is => 'ro',
    from_config => 1,
);

has namespace => (
    is => 'ro',
    from_config => 1,
);

sub BUILD {
    my ($plugin) = @_;


use Data::Dumper::Concise; print STDERR Dumper($plugin->swagger);
use Data::Dumper::Concise; print STDERR Dumper($plugin->namespace);

    my $loader = SD::OpenAPI::Live::Dancer2->new(
        spec      => $plugin->swagger,
        namespace => $plugin->namespace,
    );
    $loader->make_app($plugin->app);
}

1;

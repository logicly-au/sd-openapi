use File::Find;
use List::Util qw(shuffle);
use Test::More;

# Make sure that everything compiles.

my @Modules;
find( sub {
    return unless -f $_;
    return if $File::Find::dir =~ m!/.svn($|/)!;
    return if $File::Find::name =~ /~$/;
    return unless $File::Find::name =~ /\.pm$/;

    (my $filename) = $File::Find::name =~ m{^$File::Find::topdir/(.*\.pm)$};

    push @Modules, $filename;
}, "lib/" );


# Shuffle them to find any inconsistencies
for my $module (shuffle @Modules) {
    require_ok $module;
}

ok(scalar(@Modules), "Found more than zero modules to load.");

done_testing;

requires 'perl', '5.022000';

requires $_ for qw(
    Class::Load
    Clone
    Dancer2
    Data::Dumper::Concise
    DateTime::Format::ISO8601
    Digest::MD5
    Function::Parameters
    JSON::MaybeXS
    JSON::Validator
    Log::Any
    Moo
    MooX::Options
    Path::Tiny
    Try::Tiny
);

# minimum version of YAML::XS - for $YAML::XS::Boolean support
requires 'YAML::XS', '0.67';

on 'test' => sub {
    requires 'Import::Into';
    requires 'Plack::Test';
    requires 'Test::FailWarnings';
    requires 'Test::Most';
};

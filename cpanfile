requires 'perl', '5.022000';

requires $_ for qw(
    Class::Load
    Clone
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
    YAML::XS
);

on 'test' => sub {
    requires 'SD::Test';
};

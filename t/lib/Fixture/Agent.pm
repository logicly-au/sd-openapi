package Fixture::Agent;

use 5.22.0;
use strict;

use Moo;
use Function::Parameters qw( :strict );

use Cpanel::JSON::XS        qw( );
use Plack::Test             qw( );
use HTTP::Request           qw( );

use Fixture::App;

my $json = Cpanel::JSON::XS->new;

has swagger => (
    is => 'ro',
    required => 1,
);

has plack_test => (
    is => 'lazy',
    builder => method() {
        return Plack::Test->create(Fixture::App->generate($self->swagger));
    },
);

# Evilly monkey-patch a json decoding method into HTTP::Response
*{HTTP::Response::json} = method() {
    return $self->{'***json***'} //= eval { $json->decode($self->content) };
};

method request($method, $path, $data = undef, $header = undef) {
    my $request = HTTP::Request->new($method, $path, $header);
    if (defined $data) {
        my $content = $json->encode($data);
        $request->content($content);
        $request->content_length(length $content);
        $request->content_type('application/json');
    }
    return $self->plack_test->request($request);
}

method get($path, $header = undef) {
    $self->request(GET => $path, undef, $header);
}

method delete($path, $header = undef) {
    $self->request(DELETE => $path, undef, $header);
}

method options($path, $header = undef) {
    $self->request(OPTIONS => $path, undef, $header);
}

method patch($path, $data, $header = undef) {
    $self->request(PATCH => $path, $data, $header);
}

method post($path, $data, $header = undef) {
    $self->request(POST => $path, $data, $header);
}

method put($path, $data, $header = undef) {
    $self->request(PUT => $path, $data, $header);
}

1;

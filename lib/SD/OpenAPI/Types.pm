package SD::OpenAPI::Types;
use 5.22.0;
use warnings;

use DateTime::Format::ISO8601   qw( );
use Log::Any                    qw( $log );
use JSON::MaybeXS               qw( is_bool );
use Math::BigInt                qw( );
use Try::Tiny;

use Exporter qw( import );
our @EXPORT_OK = qw( check_type prepare_handler );

use Function::Parameters        qw( :strict );

my $datetime_parser = DateTime::Format::ISO8601->new;

# http://swagger.io/specification/#data-types-12
# This table contains handlers to check and inflate the incoming types.
# In assign_type we set a check_type field in each type. This field matches
# the keys below.
my %check_type_table = (
    array       => \&check_array,
    boolean     => \&check_boolean,
    date        => \&check_date,
    'date-time' => \&check_datetime,
    integer     => \&check_integer,
    object      => \&check_object,
    range       => \&check_range,
    sort        => \&check_sort,
    string      => \&check_string,
);

fun check_array($value, $type, $name) {
    my $itemtype = $type->{items}->{check_type};
    if (ref $value ne 'ARRAY') {
        die { $name => "must be a JSON-formatted array of $itemtype" };
    }

    my $check = $check_type_table{$itemtype};

    # Collect any errors further down and propagate them up
    my @ret;
    my %errors;
    while (my ($index, $item) = each @$value) {
        try {
            push(@ret, $check->($item, $type->{items}, "$name\[$index\]"));
        }
        catch {
            @errors{ keys %$_ } = values %$_;
        };
    }
    die \%errors if keys %errors;
    return \@ret;
};

fun check_boolean($value, $type, $name) {
    # Value may come from body json in which case we need is_bool, or it
    # may come from header/query/path where it will be a plain string.
    if (is_bool($value) || ($value =~ /^0|false|1|true$/)) {
        return 0 if $value eq 'false';  # special case for 'false'
        return $value ? 1 : 0;          # this works better with postgres
    }
    die { $name => "must be a boolean value" };
}

fun check_date($value, $type, $name) {
    if (my ($yyyy, $mm, $dd) = ($value =~ /^(\d{4})-(\d{2})-(\d{2})$/)) {
        my $date = try {
            DateTime->new(year => $yyyy, month => $mm, day => $dd)
        };
        return $date if defined $date;
    }
    die { $name => 'must be a YYYY-MM-DD date string' };
};

fun check_datetime($value, $type, $name) {
    try {
        $value = $datetime_parser->parse_datetime($value);
    }
    catch {
        die { $name => "must be an ISO8601-formatted datetime string" };
    };
    return $value;
}

fun check_integer($value, $type, $name) {
    if ($value =~ /^[-+]?\d+$/) {
        # Convert to big int for range checks so that very large values don't
        # overflow and slip through.
        my $big_value = Math::BigInt->new($value);
        if (($big_value->bcmp($type->{minimum}) >= 0)
             && ($big_value->bcmp($type->{maximum}) <= 0)) {

            # Once we're done with the BigInt checks, just return a regular int.
            return int($value);
        }
    }
    die { $name => $type->{msg} };
}

fun check_object($value, $type, $name) {
    if (ref $value ne 'HASH') {
        die { $name => "must be a JSON-formatted object" };
    }

    my %ret;
    my %errors;
    while (my ($field_name, $field_type) = each %{ $type->{properties} }) {
        my $key = "$name\.$field_name";

        if (!exists $value->{$field_name}) {
            if (exists $field_type->{default_value}) {
                # This is already validated and inflated. Copy it and move
                # on to the next parameter. We don't need to fall through.
                $ret{$field_name} = $field_type->{default_value};
            }
            elsif ($field_type->{required}) {
                $errors{$key} = "missing field $field_name";
            }

            # In all cases we can skip to the next field.
            next;
        }

        if (!defined $value->{$field_name}) {
            if ($field_type->{'x-nullable'}) {
                $ret{$field_name} = undef;
            }
            else {
                $errors{$key} = "null field $field_name";
            }

            # In all cases we can skip to the next field.
            next;
        }

        my $check = $check_type_table{ $field_type->{check_type} };
        try {
            $ret{$field_name} =
                $check->($value->{$field_name}, $field_type, $key);
        }
        catch {
            @errors{ keys %$_ } = values %$_;
        };
    }
    die \%errors if keys %errors;
    return \%ret;
}

fun check_range($value, $type, $name) {
    if (my ($low, $high) = ($value =~ /^(\d+)-(\d+)?$/)) {
        if ((!defined $high) || ($low <= $high)) {
            return [ $low, $high ];
        }
    }
    die { $name => "must be a range (eg. 0-599, or 100-)" };
}

fun check_sort($value, $type, $name) {
    if ($value =~ $type->{pattern}) {
        # [ [ '+', 'foo' ], [ '-', 'bar' ] ]
        # The sign is optional, and defaults to plus. Note that the regex
        # below deliberately makes the sign non-optional. If we match, we
        # have an explicit sign, otherwise we have no sign.
        return [ map { /^([+-])(.*)$/ ? [ $1, $2 ] : [ '+', $_ ] }
                    split(/,/, $value) ];
    }
    die { $name => $type->{msg} };
}

fun check_string($value, $type, $name) {
    $value = "$value";
    my $length = length($value);
    if ($length >= $type->{minLength} && $length <= $type->{maxLength}) {
        return $value;
    }
    die { $name => $type->{msg} };
}

fun check_type($value, $type, $name) {
    my $checker = $check_type_table{ $type->{check_type} };
    return $checker->($value, $type, $name);
}

my %limit = (
    int32 => {
        min => Math::BigInt->new('-0x8000_0000'),
        max => Math::BigInt->new('+0x7fff_ffff'),
    },
    int64 => {
        min => Math::BigInt->new('-0x8000_0000_0000_0000'),
        max => Math::BigInt->new('+0x7fff_ffff_ffff_ffff'),
    },
);

my %assign_type_table = (
    array       => \&assign_type_array,
    integer     => \&assign_type_integer,
    object      => \&assign_type_object,
    sort        => \&assign_type_sort,
    string      => \&assign_type_string,
);

# Recursively assign types to the parameters. The swagger params use a two-level
# hierarchy for the types. We create a single 'check_type' key which maps to
# the correct handler in %check_type_table.
fun assign_type($spec) {
    if ((exists $spec->{format})
            && (exists $check_type_table{ $spec->{format} })) {
        $spec->{check_type} = $spec->{format};
    }
    elsif (exists $check_type_table{ $spec->{type} }) {
        $spec->{check_type} = $spec->{type};
    }
    else {
        $log->error("Can't match type for $spec->{name}");
        #use Data::Dumper::Concise; print STDERR "MISSING: ", Dumper($spec);
        $spec->{type} = $spec->{check_type} = 'string';
    }

    if (my $assigner = $assign_type_table{ $spec->{check_type} }) {
        $assigner->($spec);
    }
}

fun assign_type_array($spec) {
    # All the items are of the same type, so we only need to descend once,
    # unlike check_type_array which needs to check each item.
    assign_type($spec->{items});
}

fun assign_type_integer($spec) {
    $spec->{format} //= 'int32';
    $spec->{msg} = "must be an $spec->{format}";

    if (exists $spec->{minimum} && exists $spec->{maximum}) {
        $spec->{msg} .= " in range [$spec->{minimum}, $spec->{maximum}]";
    }
    elsif (exists $spec->{minimum}) {
        $spec->{msg} .= " no less than $spec->{minimum}";
    }
    elsif (exists $spec->{maximum}) {
        $spec->{msg} .= " no greater than $spec->{minimum}";
    }

    my $limit = $limit{ $spec->{format} };
    $spec->{minimum} //= $limit->{min};
    $spec->{maximum} //= $limit->{max};
}

fun assign_type_object($spec) {
    # Recursively assign the type of all the properties of the object.
    assign_type($_) for values %{ $spec->{properties} };
}

fun assign_type_sort($spec) {
    # Build up the regex that matches the sort spec ahead of time.
    # If we have an array of x-sort-fields, use those specifically,
    # otherwise default to \w+.
    $spec->{msg} = 'must be a comma-separated list of field/+field/-field';

    my $sign  = qr/[-+]/;
    my $ident = qr/\w+/;    # default case if no sort fields specified
    if (my $sort_fields = $spec->{'x-sort-fields'}) {
        my $pattern = join('|', map { quotemeta } sort @$sort_fields);
        $ident = qr/(?:$pattern)/;

        $spec->{msg} .= '. Valid fields are: ' .
            join(', ', sort @$sort_fields);
    }
    my $term = qr/($sign)?($ident)/;
    $spec->{pattern} = qr/^$term(?:,$term)*$/;
}

fun assign_type_string($spec) {
    $spec->{msg} = 'must be a string';

    if (exists $spec->{minLength} && exists $spec->{maxLength}) {
        $spec->{msg} .= " between $spec->{minLength} and $spec->{maxLength} characters long";
    }
    elsif (exists $spec->{minLength}) {
        $spec->{msg} .= " at least $spec->{minLength} characters long";
    }
    elsif (exists $spec->{maxLength}) {
        $spec->{msg} .= " of no more than $spec->{maxLength} characters";
    }

    $spec->{minLength} //= 0;
    $spec->{maxLength} //= 2 * 1024 * 1024 * 1024; # that oughta do it...
}

fun assign_default($spec, $name) {
    if (exists $spec->{default}) {
        my $check = $check_type_table{$spec->{check_type}};
        try {
            $spec->{default_value} =
                $check->($spec->{default}, $spec, $name . '.default');
        }
        catch {
            while (my ($field, $error) = each %$_) {
                $log->error("$field: $error");
                #XXX: die here?
            }
        };
    }

    if ($spec->{check_type} eq 'array') {
        assign_default($spec->{items}, $name);
    }
    elsif ($spec->{check_type} eq 'object') {
        while (my ($key, $value) = each %{ $spec->{properties} }) {
            assign_default($value, "$name.$key");
        }
    }
}

# Install type checkers and defaults for all the types.
# Do this ahead of time so we only need to check it all once. At run-time
# we can assume this is all correct.
fun prepare_handler($metadata) {
    for my $p (@{ $metadata->{parameters} }) {
        assign_type($p);
        assign_default($p, $p->{name});
    }
}

1;

__END__

=head1 NAME

SD::OpenAPI::Types - Type checking and value inflation for SD::OpenAPI

=head1 FUNCTIONS

These functions must be explicitly imported.

=head2 prepare_handler($metadata)

Performs extra validation and pre-computes defaults and constraints for handler
parameters.

Call this at startup on the metadata for each route.

=head2 check_type($value, $type, $name)

Validates and inflates C<$value> according to C<$type>. Returns inflated value
on success, throws C<{ error => $message }> on failure.

=cut

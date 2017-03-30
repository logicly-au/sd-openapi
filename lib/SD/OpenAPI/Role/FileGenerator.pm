package SD::OpenAPI::Role::FileGenerator;
use 5.22.0;
use Moo::Role;
use Function::Parameters qw(:strict);

use Carp qw(carp croak);
use Digest::MD5;
use Encode qw(encode decode);
use Path::Tiny qw(path);
use POSIX ();

my $CR   = "\x0d";
my $LF   = "\x0a";

requires 'version';

method class { return ref $self || $self }

# Writes out content to a file without md5 marker
method write_file( :$filename, :$content, :$overwrite = 0) {
    my $file = path($filename);
    if ( $file->is_file && ! $overwrite ) {
        carp "$filename exists but overwrite disabled";
        return;
    }
    $file->parent->mkpath unless $file->exists; # creates intermediate directories too

    my $comment = $self->_sig_comment(
        version   => $self->version,
        timestamp => POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime),
    );
    $content =~ s/\n\n/\n\n$comment\n\n/;
    $file->spew({binmode => ':raw:encoding(UTF-8)'}, $content );
}

# Writes out content, md5 marker and custom content to filename
method write_file_with_sig( :$filename, :$content, :$custom = '', :$overwrite = 1) {
    my $file = path($filename);
    if ( $file->is_file && ! $overwrite ) {
        croak "$filename exists but overwrite disabled";
    }
    $file->parent->mkpath unless $file->exists; # creates intermediate directories too

    my $comment = qq|# Created by | . $self->class . qq|\n|
                . qq|# DO NOT MODIFY THE FIRST PART OF THIS FILE\n\n|;
    $content =~ s/\n\n/\n\n$comment/;

    # Generate marker and md5 checksum of content
    $content .= $self->_sig_comment(
        version   => $self->version,
        timestamp => POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime),
    );
    $content .= qq|\n# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:|;

    # Open file and write content, md5 checksum and custom chunks.
    my $fh = $file->filehandle('>',':raw:encoding(UTF-8)')
      or croak "Cannot open '$filename' for writing: $!";

    # Write the top half and its MD5 sum
    print $fh $content . Digest::MD5::md5_base64(encode 'UTF-8', $content) . "\n";

    # Write out any custom content the user has added
    print $fh $custom;

    close($fh)
      or croak "Error closing '$filename': $!";
}

method default_custom_content() {
    my $default = qq|\n\n# You can replace this text with custom|
         . qq| code or comments, and it will be preserved on regeneration|
         . qq|\n1;\n|;
    return $default;
}

method _sig_comment(:$version = '', :$timestamp = '' ) {
    return qq|# Created by | . $self->class
         . (length($version) ? q| v| . $version : '')
         . (length($timestamp) ? q| @ | . $timestamp : '');
}

method parse_file_with_sig( :$filename ) {
    return unless -f $filename;

    open( my $fh, '<:encoding(UTF-8)', $filename )
      or croak "Cannot open '$filename' for reading: $!";

    my $mark_re = qr{^(# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:)([A-Za-z0-9/+]{22})\r?\n};
    my $class = $self->class;
    my $created_re = qr{^# Created by $class ( v[\d.]+)?( @ [\d-]+ [\d:]+)?\r?\Z/};

    my ($real_md5, $timestamp, $version, $generated);
    while ( my $line = <$fh> ) {
        if ( $line =~ $mark_re ) {
            my $pre_md5 = $1;
            my $mark_md5 = $2;
 
            # Pull out the version and timestamp from the line above
            ($version, $timestamp) = $generated =~ m/$created_re/m;
            $version =~ s/^ v// if $version;
            $timestamp =~ s/^ @ // if $timestamp;
 
            $generated .= $pre_md5;
            $real_md5 = Digest::MD5::md5_base64(encode 'UTF-8', $generated);
            croak "Checksum mismatch in '$filename', the auto-generated part of the file has been modified outside of this loader.  Aborting."
                if $real_md5 ne $mark_md5;

            last;
        }
        else {
            $generated .= $line;
        }
    }
    
    # Slurp remainder (custom content)
    my $custom = do { local $/; <$fh> } if $real_md5;
    close $fh;

    $custom //= '';
    $custom =~ s/$CR?$LF/\n/g;

    return +{
        generated => $generated, 
        checksum  => $real_md5,
        version   => $version,
        timestamp => $timestamp,
        custom    => $custom,
    };
}

1;

__END__

=pod

=encoding utf8

=head1 NAME

SD::OpenAPI::Role::FileGenerator - read / write generated perl packages

=cut


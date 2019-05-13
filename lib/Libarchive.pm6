use NativeCall;
use Archive::Libarchive::Raw;
use Archive::Libarchive::Constants;

class X::Libarchive is Exception
{
    has $.errno;
    has $.message;

    multi method new() { self.bless }

    multi method new(archive:D $archive!)
    {
        self.bless(errno   => archive_errno($archive),
                   message => archive_error_string($archive))
    }
}

class X::Libarchive::Unknown is X::Libarchive
{
    method message() { "Unknown error" }
}

class X::Libarchive::UnknownFormat is X::Libarchive
{
    has $.format;
    method message() { "Unknown format $!format" }
}

class X::Libarchive::UnknownFilter is X::Libarchive
{
    has $.filter;
    method message() { "Unknown filter $!filter" }
}

class X::Libarchive::UnknownSource is X::Libarchive
{
    has $.source;
    method message() { "Don't know how to read from a {$!source.^name}" }
}

class X::Libarchive::UnknownDestination is X::Libarchive
{
    has $.dest;
    method message() { "Don't know how to write to a {$!dest.^name}" }
}

class X::Libarchive::ArchiveClosed is X::Libarchive
{
    method message() { 'Tried to use a closed archive' }
}

role Libarchive
{
    has archive $.archive;
    has Bool $.opened;

    method lib-version() # Copied from Archive::Libarchive
    {
        {
            ver     => archive_version_number,
            strver  => archive_version_string,
            details => archive_version_details,
            zlib    => archive_zlib_version,
            liblzma => archive_liblzma_version,
            bzlib   => archive_bzlib_version,
            liblz4  => archive_liblz4_version,
            libzstd => try { archive_libzstd_version },
        }
    }

    method DESTROY()
    {
        self.close if $!opened or $!archive;
    }

    method die() is hidden-from-backtrace
    {
        die X::Libarchive.new($!archive)
    }

    method format() { archive_format_name($_) with $!archive }

    method compression() { archive_compression_name($_) with !archive }
}

=begin pod

=head1 NAME

Libarchive - Role for shared Libarchive functionality

=head1 SYNOPSIS

    use Libarchive;

    say Libarchive.lib-version;

=head1 DESCRIPTION

Adds a few shared methods to C<Libarchive::Read> and C<Libarchive::Write>:

=head3 B<lib-version>()

Return a hash of libarchive library version information.

=head3 B<die>()

Throw an exception related to the libarchive object.

=head3 B<format>()

Return the format used in the archive.

=head3 B<filter>()

Return the filter used in the archive.

=head3 B<DESTROY>()

close the archive during destruction.

=end pod

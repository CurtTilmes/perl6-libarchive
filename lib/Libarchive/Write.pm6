use NativeCall;
use Archive::Libarchive::Raw;
use Archive::Libarchive::Constants;
use NativeHelpers::Callback :cb;
use Libarchive;
use Libarchive::Entry;

unit class Libarchive::Write does Libarchive;

has $.format;
has $.filter = ();
has $.passphrase = ();
has $.options = '';
has Int:D $.bytes-per-block = 10240;
has Int:D $.bytes-in-last-block = 1;
has Bool:D $.follow-links = False;
has Bool:D $.absolute = False;
has $.reader;
has %.opts;
has $.dest;

method die-reader() { die X::Libarchive.new($!reader) }

method new-reader()
{
    $!reader = archive_read_disk_new() // die X::Libarchive::Unknown.new;

    archive_read_disk_set_standard_lookup($!reader)
        == ARCHIVE_OK or self.die-reader;

    ($!follow-links ?? archive_read_disk_set_symlink_logical($!reader)
                    !! archive_read_disk_set_symlink_physical($!reader))
        == ARCHIVE_OK or self.die-reader
}

sub archive-open(archive $archive, int64 $id --> int32)
{
    ARCHIVE_OK
}

sub archive-write-buf(archive $archive, int64 $id,
                      CArray[uint8] $buf, size_t $bytes --> size_t)
{
    cb.lookup($id).dest.append: $buf[^$bytes];
    $bytes
}

sub archive-write-iohandle(archive $archive, int64 $id,
                           CArray[uint8] $buf, size_t $bytes --> size_t)
{
    cb.lookup($id).dest.write: Blob.new($buf[^$bytes]);
    $bytes
}

sub archive-write-supplier(archive $archive, int64 $id,
                           CArray[uint8] $buf, size_t $bytes --> size_t)
{
    cb.lookup($id).dest.emit: Blob.new($buf[^$bytes]);
    $bytes
}

sub archive-write-channel(archive $archive, int64 $id,
                          CArray[uint8] $buf, size_t $bytes --> size_t)
{
    try cb.lookup($id).dest.send(Blob.new($buf[^$bytes]));
    with $!
    {
        archive_set_error($archive, ARCHIVE_FATAL, .message);
        return -1
    }
    $bytes
}

sub archive-close(archive $archive, int64 $id --> int32)
{
    given cb.lookup($id).dest
    {
        when IO::Handle|Channel { .close }
        when Supplier           { .done  }
    }
    ARCHIVE_OK
}

method new($dest where Str|IO::Path|Blob|IO::Handle|Supplier|Channel,
           |open-opts)
{
    self.bless.open($dest, |open-opts)
}

method open($dest where Str|IO::Path|Buf|IO::Handle|Supplier|Channel,
            |write-opts)
{
    self.close if $!opened;

    without $!archive
    {
        $!archive = archive_write_new() // die X::Libarchive::Unknown.new;
        cb.store(self, $!archive);
    }

    self.write-options(|write-opts);

    given $!dest := $dest
    {
        when Str|IO::Path
        {
            unless $.format
            {
                archive_write_set_format_filter_by_ext($!archive, ~$dest)
                    == ARCHIVE_OK or self.die
            }
            archive_write_open_filename($!archive, ~$dest)
                == ARCHIVE_OK or self.die
        }
        when Buf
        {
            archive_write_open($!archive, cb.id($!archive), &archive-open,
                               &archive-write-buf, &archive-close)
                == ARCHIVE_OK or self.die
        }
        when IO::Handle
        {
            archive_write_open($!archive, cb.id($!archive), &archive-open,
                               &archive-write-iohandle, &archive-close)
                == ARCHIVE_OK or self.die;
        }
        when Supplier
        {
            archive_write_open($!archive, cb.id($!archive), &archive-open,
                               &archive-write-supplier, &archive-close)
                == ARCHIVE_OK or self.die;
        }
        when Channel
        {
            archive_write_open($!archive, cb.id($!archive), &archive-open,
                               &archive-write-channel, &archive-close)
                == ARCHIVE_OK or self.die;
        }
    }
    $!opened = True;
    self
}

method close()
{
    if $!opened
    {
        archive_write_close($!archive) == ARCHIVE_OK or self.die;
        $!dest := Nil;
        $!opened = False;
    }
    with $!archive
    {
        cb.remove($!archive);
        archive_write_free($_) == ARCHIVE_OK or self.die;
        $!archive = Nil;
    }
    with $!reader
    {
        archive_read_free($_) == ARCHIVE_OK or self.reader-die;
        $!reader = Nil;
    }
    self
}

method write-options(:$format, :$filter, :$passphrase,
                     Int :$bytes-per-block,
                     Int :$bytes-in-last-block,
                     Bool :$follow-links,
                     Bool :$absolute,
                     Str :$options,
                     *%opts)
{
    $!format              = $_ with $format;
    $!filter              = $_ with $filter;
    $!passphrase          = $_ with $passphrase;
    $!bytes-per-block     = $_ with $bytes-per-block;
    $!bytes-in-last-block = $_ with $bytes-in-last-block;
    $!follow-links        = $_ with $follow-links;
    $!absolute            = $_ with $absolute;
    $!options             = $_ with $options;
    %!opts                = %opts if %opts;

    with $!format
    {
        archive_write_set_format_by_name($!archive, $!format)
            == ARCHIVE_OK or self.die
    }

    for @$!filter -> $filter
    {
        archive_write_add_filter_by_name($!archive, $filter)
            == ARCHIVE_OK or self.die
    }

    for @$!passphrase -> $passphrase
    {
        archive_write_set_passphrase($!archive, $passphrase)
            == ARCHIVE_OK or self.die
    }

    archive_write_set_bytes_per_block($!archive, $!bytes-per-block)
        == ARCHIVE_OK or self.die;

    archive_write_set_bytes_in_last_block($!archive, $!bytes-in-last-block)
        == ARCHIVE_OK or self.die;

    archive_write_set_options($!archive, $!options)
        == ARCHIVE_OK or self.die
}

multi method add(*@paths, |opts)
{
    samewith(.IO, |opts) for @paths;
    self
}

multi method add(IO::Path:D $path,
                 Bool :$absolute = $!absolute,
                 *%opts)
{
    die X::Libarchive::ArchiveClosed.new without $!archive;

    my $entry = Libarchive::Entry.new;

    $entry.sourcepath: ~$path;
    $entry.pathname: $absolute ?? $path.absolute !! $path.relative;

    self.new-reader without $!reader;

    archive_read_disk_entry_from_file($!reader, $entry.entry, -1, Pointer)
        == ARCHIVE_OK or self.die-reader;

    $entry.set: |%!opts, |%opts;

    archive_write_header($!archive, $entry.entry)
        == ARCHIVE_OK or self.die;

    if $entry.is-file
    {
        my $io = $path.open(:bin);
        LEAVE .close with $io;

        while my $buf = $io.read
        {
            archive_write_data($!archive, $buf, $buf.bytes)
                >= ARCHIVE_OK or self.die
        }
    }
    self
}

multi method write(Str:D() $pathname, Blob $buf?, *%opts)
{
    die X::Libarchive::ArchiveClosed.new without $!archive;

    my $entry = Libarchive::Entry.new;

    $entry.set: |%!opts, size => $buf ?? $buf.bytes !! 0, :$pathname, |%opts;

    archive_write_header($!archive, $entry.entry)
        == ARCHIVE_OK or self.die;

    if $buf
    {
        archive_write_data($!archive, $buf, $buf.bytes)
            >= ARCHIVE_OK or self.die
    }
    self
}

multi method write(Str:D() $pathname, Str:D $str, *%opts)
{
    samewith $pathname, $str.encode, |%opts
}

multi method write(Str:D() $pathname, IO::Handle:D $io, *%opts)
{
    die X::Libarchive::ArchiveClosed.new without $!archive;

    my $entry = Libarchive::Entry.new;
    $entry.set: |%!opts, :$pathname, |%opts;

    archive_write_header($!archive, $entry.entry)
        == ARCHIVE_OK or self.die;

    my $bytes-to-go = $entry.size;
    while $bytes-to-go > 0
    {
        my $buf = $io.read(min($!bytes-per-block, $bytes-to-go));
        last unless $buf;
        archive_write_data($!archive, $buf, $buf.bytes);
        $bytes-to-go -= $buf.bytes;
    }
    self
}

multi method write(Str:D() $pathname, IO::Path $path, *%opts)
{
    samewith $pathname, $path.open(:bin), size => $path.s, |%opts
}

method mkdir(Str:D() $pathname, |opts)
{
    self.write($pathname, :dir, |opts)
}

multi method symlink(Pair:D $symlink, |opts)
{
    self.write($symlink.key, symlink => $symlink.value, |opts)
}

multi method symlink(Str:D() $pathname, Str:D() $symlink, |opts)
{
    self.write($pathname, :$symlink, |opts)
}

method copy($seq)
{
    die X::Libarchive::ArchiveClosed.new without $!archive;

    for $seq<> -> $entry
    {
        archive_write_header($!archive, $entry.entry)
            == ARCHIVE_OK or self.die;

        my $bytes-to-go = $entry.size;
        while $bytes-to-go > 0
        {
            my $buf = $entry.data(min($!bytes-per-block, $bytes-to-go));
            last unless $buf;
            archive_write_data($!archive, $buf, $buf.bytes);
            $bytes-to-go -= $buf.bytes;
        }
    }
    self
}

=begin pod

=head1 NAME

Libarchive::Read - Streaming write of an archive with libarchive

=head1 SYNOPSIS

    use Libarchive::Write;

    with Libarchive::Write('file.tar.gz') {
        .add: 'afile';
        .write: 'file', "Some content\n";
        .mkdir: 'adir';
        .symlink: 'linked' => 'afile';
        .close
    }

=head1 DESCRIPTION

A wrapper around the C<libarchive> library that writes an archive.
Creating an object opens an archive to write somewhere, then you
direct the creation of a series of archive entities, then finally you
must C<close> the object to finalize the archive.  Following a
C<close> the object may no longer be used.

=head2 METHODS

=head3 B<new>($dest, |open-opts)

Creates a new object, then passes all options to B<open>().

=head3 B<open>($dest, |write-opts)

Passes options on to B<write-options>().

C<$dest> can be:

=item C<Str> or C<IO::Path> with a filename to open.  The extension of
the filename is also used to determine a format/filter to use for the
archive.

=item C<Buf> A memory buffer to write to.  Note that as the archive
grows, the memory buffer is continually appended to, which may
reallocate and/or relocate in memory to accomodate the growth.  It
works find for small things, but streams directly to your final
destination will be more efficient.

=item C<IO::Handle>, C<Supplier> or C<Channel> Send a stream of binary
blobs to this destination and closes the destination on completion.

=head3 B<close>()

Close the archive and free all resources.  The object may no longer be
used.

=head3 B<write-options>(:$format, :$filter, :$passphrase, Int
:$bytes-per-block, Int :$bytes-in-last-block, Bool :$follow-links,
Bool :$absolute, Str :$options, *%opts)

Any named option not listed here will be passed on during creation of
C<Libarchive::Entry> objects, for example, C<perm> override or
C<uname> override might be useful here.  Overriding fields like
C<pathname> or C<size> are strongly discouraged.

=item C<$format> - format to use when creating archive.  Valids: 7zip,
ar, arbsd, argnu, arsvr4, bsdtar, cd9660, cpio, gnutar, iso, iso9660,
mtree, mtree-classic, newc, odc, oldtar, pax, paxr, posix, raw, rpax,
shar, shardump, ustar, v7tar, v7, warc, xar, zip.  See libarchive
documentation for details and caveats about various formats.

=item C<$filter> - One or more filters to encode the archive with.
Valids: b64encode, bzip2, compress, grzip, gzip, lrzip, lz4, lzip,
lzma, lzop, uuencode, xz, zstd. See libarchive documentation for
details and caveats about various filters.

=item C<$passphrase> - passphrase to encrypt archive with assuming the
specified format supports it.

=item C<$bytes-per-block> - A non-binding block size to write the
archive with.  In particular, the last block could be shorter than
this size.

=item C<$bytes-in-last-block> - By default this is set to 1, so the
last block is no larger than it needs to be, but you might want to
have full blocks, for example if you are streaming a cpio archive to a
tape device.

=item C<$follow-links> - when adding symbolic links from the
filesystem, setting this will cause the file linked to be added rather
than the link itself.

=item C<$absolute> - When adding filesystem entities to the archive,
record their absolute pathnames instead of relative into the archive.
Default is to store them relative to C<$*CWD>.  You can change that,
or use C<indir> while writing the archive.

=item C<$options> - A single string with a comma-separated list of
options.  See libarchive documentation for full details, but in a
nutshell:

C<option=value>

The option/value pair will be provided to every module. Modules that
do not accept an option with this name will ignore it.

C<option>

The option will be provided to every module with a value of "1".

C<!option>

The option will be provided to every module with a NULL value.

C<module:option=value, module:option, module:!option>

As above, but the corresponding option and value will be provided only
to modules whose name matches module.

=head3 B<add>(*@paths, *%opts)
=head3 B<add>(IO::Path:D $path, Bool :$absolute, *%opts)

Add one or more existing filesystem entities to the archive.  Pass any
extra options for the C<Libarchive::Entry> objects as well.

=head3 B<write>(Str:D() $pathname, Blob $buf?, *%opts)
=head3 B<write>(Str:D() $pathname, Str:D $str, *%opts)
=head3 B<write>(Str:D() $pathname, IO::Path:D $path, *%opts)
=head3 B<write>(Str:D() $pathname, IO::Handle:D $io, *%opts)

Create a new file in the archive, with the contents from a memory
Blob, Str, or from a file specified by C<IO::Path> or C<IO::Handle>.

=head3 B<mkdir>(Str:D() $pathname, |opts)

Create a directory in the archive.

=head3 B<symlink>(Str:D() $pathname, Str:D() $symlink, |opts)
=head3 B<symlink>(Pair:D $symlink, |opts)

Create a symbolic link in the archive.

=head3 B<copy>($seq)

Copy a sequence of C<Libarchive::Entry> objects into the archive.
Probably from a C<Libarchive::Read> or C<Libarchive::Archive>.

=end pod

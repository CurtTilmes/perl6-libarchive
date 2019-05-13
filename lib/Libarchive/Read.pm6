use NativeCall;
use Archive::Libarchive::Raw;
use Archive::Libarchive::Constants;
use NativeHelpers::Callback :cb;
use Libarchive;
use Libarchive::Entry::Read;

unit class Libarchive::Read does Libarchive does Iterable does Iterator;

has $.format = 'all';
has $.filter = 'all';
has $.passphrase = ();
has Str $.destpath;
has Bool $.verbose;
has Int $.blocksize = 10240;
has Int $.flags = 0;
has Str $.options = '';
has $.source;
has $.buf is rw;

my %read-formats =
    'all'            => &archive_read_support_format_all,
    '7zip'           => &archive_read_support_format_7zip,
    'ar'             => &archive_read_support_format_ar,
    'cab'            => &archive_read_support_format_cab,
    'cpio'           => &archive_read_support_format_cpio,
    'empty'          => &archive_read_support_format_empty,
    'gnutar'         => &archive_read_support_format_gnutar,
    'iso9660'        => &archive_read_support_format_iso9660,
    'lha'            => &archive_read_support_format_lha,
    'mtree'          => &archive_read_support_format_mtree,
    'rar'            => &archive_read_support_format_rar,
    'raw'            => &archive_read_support_format_raw,
    'tar'            => &archive_read_support_format_tar,
    'warc'           => &archive_read_support_format_warc,
    'xar'            => &archive_read_support_format_xar,
    'zip'            => &archive_read_support_format_zip,
    'zip-streamable' => &archive_read_support_format_zip_streamable,
    'zip-seekable'   => &archive_read_support_format_zip_seekable,
;

my %read-filters =
    'all'            => &archive_read_support_filter_all,
    'bzip2'          => &archive_read_support_filter_bzip2,
    'compress'       => &archive_read_support_filter_compress,
    'gzip'           => &archive_read_support_filter_gzip,
    'grzip'          => &archive_read_support_filter_grzip,
    'lrzip'          => &archive_read_support_filter_lrzip,
    'lz4'            => &archive_read_support_filter_lz4,
    'lzip'           => &archive_read_support_filter_lzip,
    'lzma'           => &archive_read_support_filter_lzma,
    'lzop'           => &archive_read_support_filter_lzop,
    'none'           => &archive_read_support_filter_none,
    'rpm'            => &archive_read_support_filter_rpm,
    'uu'             => &archive_read_support_filter_uu,
    'xz'             => &archive_read_support_filter_xz,
    'zstd'           => &archive_read_support_filter_zstd,
;

sub archive-open(archive $archive, int64 $id --> int32)
{
    ARCHIVE_OK
}

sub archive-read-channel(archive $archive, int64 $id,
                         CArray[Pointer] $ptr --> size_t)
{
    my $read = cb.lookup($id);
    try $read.buf = $read.source.receive;
    return 0 if $!;
    $ptr[0] = nativecast(Pointer, $read.buf);
    return $read.buf.bytes;
}

sub archive-read-iohandle(archive $archive, int64 $id,
                          CArray[Pointer] $ptr --> size_t)
{
    my $read = cb.lookup($id);
    return 0 if $read.source.eof;
    $read.buf = $read.source.read;
    $ptr[0] = nativecast(Pointer, $read.buf);
    return $read.buf.bytes;
}

sub archive-close(archive $archive, int64 $id --> int32)
{
    cb.lookup($id).source.close;
    ARCHIVE_OK
}

method new(|open-opts)
{
    self.bless.open(|open-opts)
}

method open($source?, |read-opts)
{
    UNDO self.close;
    self.close if $!opened;
    without $!archive
    {
        $!archive = archive_read_new() // die X::Libarchive::Unknown.new;
        cb.store(self, $!archive);
    }
    self.read-options(|read-opts);

    with $source
    {
        when Str|IO::Path
        {
            archive_read_open_filename($!archive, ~$source, $!blocksize)
                == ARCHIVE_OK or self.die
        }
        when Blob
        {
            archive_read_open_memory($!archive, $source, $source.bytes)
                == ARCHIVE_OK or self.die
        }
        when Supply
        {
            $!source := .Channel;

            archive_read_open($!archive, cb.id($!archive), &archive-open,
                              &archive-read-channel, &archive-close)
                == ARCHIVE_OK or self.die
        }
        when IO::Handle
        {
            $!source := $source;
            archive_read_open($!archive, cb.id($!archive), &archive-open,
                              &archive-read-iohandle, &archive-close)
                == ARCHIVE_OK or self.die
        }
        when Channel
        {
            $!source := $source;
            archive_read_open($!archive, cb.id($!archive), &archive-open,
                              &archive-read-channel, &archive-close)
                == ARCHIVE_OK or self.die
        }
        default
        {
            die X::Libarchive::UnknownSource.new(:$source)
        }
    }
    else
    {
        return self
    }

    $!opened = True;

    self
}

method read-options(:$format, :$filter, :$passphrase,
                    Int :$blocksize, Str :$destpath, Bool :$verbose,
                    Str :$options, |flags)
{
    $!format     = $_ with $format;
    $!filter     = $_ with $filter;
    $!passphrase = $_ with $passphrase;
    $!blocksize  = $_ with $blocksize;
    $!destpath   = $_ with $destpath;
    $!options    = $_ with $options;
    $!verbose    = $_ with $verbose;

    $!flags = $.extract-flags(|flags) if flags;

    for @$!format -> $format
    {
        with %read-formats{$format} -> &install-format
        {
            install-format($!archive) == ARCHIVE_OK or self.die
        }
        else
        {
            die X::Libarchive::UnknownFormat.new(:$format)
        }
    }

    for @$!filter -> $filter
    {
        with %read-filters{$filter} -> &install-filter
        {
            install-filter($!archive) == ARCHIVE_OK or self.die
        }
        else
        {
            die X::Libarchive::UnknownFilter.new(:$filter)
        }
    }

    for @$!passphrase -> $passphrase
    {
        archive_read_add_passphrase($!archive, $passphrase)
            == ARCHIVE_OK or self.die
    }

    archive_read_set_options($!archive, $!options)
        == ARCHIVE_OK or self.die
}

method close()
{
    if $!opened
    {
        archive_read_close($!archive) == ARCHIVE_OK or self.die;
        $!source := Nil;
        $!opened = False;
    }
    with $!archive
    {
        cb.remove($!archive);
        archive_read_free($_) == ARCHIVE_OK or self.die;
        $!archive = Nil;
    }
    self
}

method read()
{
    return Nil unless $!opened and $!archive;

    my $entry = archive_entry_new() // die X::Libarchive::Unknown.new;

    given archive_read_next_header2($!archive, $entry)
    {
        when ARCHIVE_EOF   { archive_entry_free($entry); return Nil }
        when ARCHIVE_FATAL { archive_entry_free($entry); self.die }
        when ARCHIVE_WARN  { warn archive_error_string($!archive) }
    }

    Libarchive::Entry::Read.new(:$entry, libarchive => self)
}

method pull-one() { $.read // IterationEnd }

method sink-all() { IterationEnd }

method is-lazy() { True }

method iterator() { self }

method read-data(Int $size)
{
    die X::Libarchive::ArchiveClosed.new unless $!opened and $!archive;

    my $buf = buf8.allocate($size);

    loop
    {
        given archive_read_data($!archive, $buf, $size)
        {
            when ARCHIVE_FATAL|ARCHIVE_WARN { self.die }
            when ARCHIVE_RETRY { next }
            when $size { return $buf }
            default { return $buf.reallocate($_) }
        }
    }
}

method extract-flags(Bool :$extract-owner,
                     Bool :$extract-perm,
                     Bool :$extract-time,
                     Bool :$extract-no-overwrite,
                     Bool :$extract-unlink,
                     Bool :$extract-acl,
                     Bool :$extract-fflags,
                     Bool :$extract-xattr,
                     Bool :$extract-secure-symlinks,
                     Bool :$extract-secure-nodotdot,
                     Bool :$extract-no-autodir,
                     Bool :$extract-no-overwrite-newer,
                     Bool :$extract-sparse,
                     Bool :$extract-secure-noabsolutepaths,
                     Bool :$extract-clear-nochange-fflags)
{
    my $flags = $!flags;

    with $extract-owner
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_OWNER }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_OWNER }
    }
    with $extract-perm
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_PERM }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_PERM }
    }
    with $extract-time
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_TIME }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_TIME }
    }
    with $extract-no-overwrite
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_NO_OVERWRITE }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_NO_OVERWRITE }
    }
    with $extract-unlink
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_UNLINK }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_UNLINK }
    }
    with $extract-acl
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_ACL }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_ACL }
    }
    with $extract-fflags
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_FFLAGS }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_FFLAGS }
    }
    with $extract-xattr
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_XATTR }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_XATTR }
    }
    with $extract-secure-symlinks
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_SECURE_SYMLINKS }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_SECURE_SYMLINKS }
    }
    with $extract-secure-nodotdot
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_SECURE_NODOTDOT }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_SECURE_NODOTDOT }
    }
    with $extract-no-autodir
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_NO_AUTODIR }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_NO_AUTODIR }
    }
    with $extract-no-overwrite-newer
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_NO_OVERWRITE_NEWER }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_NO_OVERWRITE_NEWER }
    }
    with $extract-sparse
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_SPARSE }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_SPARSE }
    }
    with $extract-secure-noabsolutepaths
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS }
    }
    with $extract-clear-nochange-fflags
    {
        if $_ { $flags +|=    ARCHIVE_EXTRACT_CLEAR_NOCHANGE_FFLAGS }
        else  { $flags +&= +^ ARCHIVE_EXTRACT_CLEAR_NOCHANGE_FFLAGS }
    }
    $flags
}

method extract(Libarchive::Entry::Read $entry,
               Str :$destpath = $!destpath,
               Bool :$verbose = $!verbose,
               |flags)
{
    die X::Libarchive::ArchiveClosed.new unless $!opened and  $!archive;

    $entry.pathname(.IO.add($entry.pathname)) with $destpath;

    $entry.Str.note if $verbose;

    archive_read_extract($!archive, $entry.entry, $.extract-flags(|flags))
        == ARCHIVE_OK or self.die
}

=begin pod

=head1 NAME

Libarchive::Read - Streaming read of an archive with libarchive

=head1 SYNOPSIS

  use Libarchive::Read;

  my $archive := Libarchive::Read.new('myfile.tar.gz');
  for $archive -> $entry {
      put $entry.pathname;
  }

  .put for Libarchive::Read.new('foo.zip');  # Archive listing

  .extract for Libarchive::Read.new($*IN);   # Extract all files to filesystem

=head1 DESCRIPTION

C<Libarchive::Read> is a wrapper around the C<libarchive> library that
reads an archive, producing a series of C<Archive::Entry::Read>
objects.

In general, you shouldn't need to access methods in this object,
preferring to use the higher level calls on the
C<Archive::Entry::Read> objects.

C<Libarchive::Read> does both C<Iterable> and an C<Iterator>,
returning itself when iterated.

It also does C<Libarchive> getting some basic functionality from that
role.

=head2 METHODS

=head3 B<new>()

Passes all options through to B<open>().

=head3 B<open>($source?, |read-opts)

Passes all read-opts through to B<read-options>().

C<$source> can be :

=item C<Str> or C<IO::Path> with a filename to open

=item C<Blob> of memory to read the archive from

=item C<IO::Handle> to read archive from

=item C<Supply> or C<Channel> producing a stream of memory C<Blob>
blocks from which to read the archive.

=head3 B<read-options>(:$format, :$filter, :$passphrase, Int :$blocksize, Str :$destpath, Bool :$verbose, Str :$options, |flags)

=item C<flags> - See B<extract-flags>()

=item C<$format> - one or more candidate formats to consider when
extracting an archive.  Defaults to 'all'.  Valids are: all, 7zip, ar,
cab, cpio, empty, gnutar, iso9660, lha, mtree, rar, raw, tar, warc,
xarr, zip, zip-streamable, zip-seekable

=item C<$filter> - one or more candidate filters to consider when
extracting an archive.  Defaults to 'all'.  Valids are: all, bzip2,
compress, gzip, grzip, lrzip, lz4, lzip, lzma, lzop, none, rpm, uu,
xz, zstd

=item C<$passphrase> - one or more passphrases to try when reading an
encrypted archive.

=item C<$blocksize> - Block size to read from disk with, defaults to 10240.

=item C<$destpath> - Default destination path to use while extracting
files to disk.  This is prepended to the C<pathname> of the archive
entry.

=item C<$verbose> - notes description of entry to STDERR during
extraction.

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

B<Format iso9660>

joliet -  Support Joliet extensions. Defaults to enabled, use !joliet to disable.

rockridge - Support RockRidge extensions. Defaults to enabled, use !rockridge to disable.

B<Format tar>

compat-2x - Libarchive 2.x incorrectly encoded Unicode filenames on some platforms. This option mimics the libarchive 2.x filename handling so that such archives can be read correctly.

hdrcharset - The value is used as a character set name that will be used when translating filenames.

mac-ext - Support Mac OS metadata extension that records data in special files beginning with a period and underscore. Defaults to enabled on Mac OS, disabled on other platforms. Use !mac-ext to disable.

read_concatenated_archives - Ignore zeroed blocks in the archive, which occurs when multiple tar archives have been concatenated together. Without this option, only the contents of the first concatenated archive would be read.

=head3 B<close>()

Close the archive.  It isn't required that you call this.  It will be
automatically called if needed.

=head3 B<read>()

Return a C<Libarchive::Entry::Read> for the next entry in the archive.
Return `Nil` if there are no more entries.

=head3 B<pull-one>()

For C<Iterator>, just like B<read>(), but return C<IterationEnd> at
the end.

=head3 B<sink-all>()

Returns an immediate C<IterationEnd> without bothering to read the
rest of the archive.

=head3 B<is-lazy>()

True

=head3 B<iterator>()

self

=head3 B<read-data>(Int $size)

This can only be called directly after reading an archive entity
header.  Reads one block of up to C<$size> bytes from the archive
stream, returning it in a C<buf8>.

=head3 B<extract-flags>(...)

Any of: C<:extract-owner>, C<:extract-perm>, C<:extract-time>,
C<:extract-no-overwrite>, C<:extract-unlink>, C<:extract-acl>,
C<:extract-fflags>, C<:extract-xattr>, C<:extract-secure-symlinks>,
C<:extract-secure-nodotdot>, C<:extract-no-autodir>,
C<:extract-no-overwrite-newer>, C<:extract-sparse>,
C<:extract-secure-noabsolutepaths>, C<:extract-clear-nochange-fflags>

See libarchive documentation for precise meaning of each flag.

=head3 B<extract>(Libarchive::Entry::Read $entry, Str :$destpath, Bool
:$verbose, |flags)

Extracts an entity to disk.

=item flags - see B<extract-flags>

=item $entry - the entry to extract

=item $destpath - path prepended to C<pathname> for extraction to disk

=item $verbose - notes a summary of the filesystem entity to STDERR
during extraction.

=end pod

# Libarchive - Multi-format archive and compression

[libarchive](https://www.libarchive.org/) is a multi-format archive
and compression libarary.  This module provides a very composable high
level interface to the library for reading, processing and writing
archives of files.

## Simple, streaming archive reading

    use Libarchive::Simple;

    .put for archive-read 'myfile.tar.gz';               # Print listing

    .extract for archive-read $*IN;                      # Extract all files

    # Print a custom listing, using field accessors
    for archive-read($*IN) {
        put "dir: {.pathname}" if .is-dir;
        put "file: {.pathname} {.human-size}" if .is-file;
    }

    for archive-read('this.tar.gz') {
       .content.put if .pathname eq 'README'
    }

    archive-read('this.zip'.IO)           # Process Seq in normal ways
        .grep({ .pathname ~~ /README/ })  # with for, grep, map, etc.
        .map: { .extract :verbose };      # print listing to STDERR as extract

    # Many extract options to customize, either in object or extract()
    for archive-read('dvd.iso', :extract-no-overwrite,
                     destpath => '/somewhere') {
        next unless .pathname eq 'the-file-i-want';
        .extract(perm => 0o600);
    }

Can read from filename, IO::Path, IO::Handle, Memory Buf, Supply of Blobs,
Channel of Blobs

`archive-read()` is just short-hand for `Libarchive::Read.new()`

## Simple, streaming archive writing

    use Libarchive::Simple;

    with archive-write('foo.zip')
    {
        .add: 'afile';         # Add a file from the filesystem to the archive
        .add: 'somedir';       # Add a directory, but not contents
        .add: dir('somedir');  # Add every file in a directory
        .add: 'thisdir', dir('thisdir');  # Add directory and contents

        .write: 'afile', "Some content\n";      # Create a file from a Str
        .write: 'bfile', buf8.new(1,2,3,4);     # or from a Blob
        .write: 'bigrandomfile',                # or an IO::Handle
                '/dev/urandom'.IO.open(:bin),
                size => 100_000;                # override size

        .mkdir: 'adir';                               # Create a directory
        .mkdir: 'bdir', perm => 0o700;                # Override perm
        .write: 'cdir'.IO.add('another'), "this\n";   # IO::Path is fine too

        .symlink: 'linked', 'adir/anotherfile';       # Create a symlink
        .symlink: 'anotherlink' => 'adir/yetanother'; # Pair symlink is ok

        .close;                                       # Always close!
    }

Can write to filename, IO::Path, IO::Handle, Memory Buf, Supplier of Blobs,
Channel of Blobs.  Must specify format (optionally filters) unless filename:

    archive-write($*OUT, format => 'zip');  # Send zip file to STDOUT

`archive-write()` is just shorthand for `Libarchive::Write.new()`

## Simple, Slurping all content into memory:

    use Libarchive::Simple;

    my $archive := archive-slurp 'this.tar';
    say $archive;                                   # Print listing
    put $archive<README>;                           # content of a file
    $archive<afile>.content = "Change content\n";   # change existing file
    $archive<adir/bad>:delete;                      # Remove file
    $archive.spurt: 'foo.zip';                      # Dump archive back to disk

`archive-slurp()` is just shorthand for `Libarchive::Archive.new()`

It creates an object that is both `Iterable` just like `archive-read`,
and also `Associative`, including all the data/content from the
archive instead of reading it out of the stream as it goes, so you can
use hyper processing in parallel without worry.  The keys are paths,
not just filenames.  If the archive has two files with exactly the
same path, you'll just get one. (Why would you do that anyway?)

## Processing Archives in a pipeline

`Libarchive::Read` (and `archive-read`) produces a Seq of
`Libarchive::Entry`s.  You can use the `.copy` method to copy them into
an `Libarchive::Write`.

For example, you could hook up a reader to a writer to convert a tar
file to a zip file (or ISO or whatever):

    use Libarchive::Simple;

    with archive-write($*OUT, format => 'zip')
    {
        .copy: archive-read($*IN, format => 'tar')
        .close;
    }

Or even process the contents in various ways as they go:

    use Libarchive::Simple;

    with archive-write($*OUT, format => 'zip')
    {
        .write: 'NEWREADME', "This is my README\n";      # Add some extra files
        .write: 'LICENSE', "Special license file\n";
        .copy: archive-read($*IN, format => 'tar')
               .grep({ .pathname ~~ /good/})             # Only pass good files
               .map({ .pathname(.pathname.uc) })         # Uppercase filenames
               .map({ .uname('fred').perm(0o600)});      # Change owner and perm
        .close;
    }

When streaming, make sure you keep the sequence lazy, otherwise the
stream with the data will be past before the copy occurs.  If you want
random access, use `Libarchive::Archive` or `archive-slurp`.

# Filtering without an Archive, format 'raw'

`libarchive` supports a special format 'raw' that works on a single
virtual file, passing it through the specified filters.  This can be
used to `compress`, `gzip`, `bzip2` etc.

The manual process is something like this:

    with archive-write($dest, format => 'raw', filter => 'gzip')
    {
        .write('ignore-filename', $source, size => ...);
        .close
    }

or

    with archive-read($source, format => 'raw')
    {
        my $header = .read;  # Read and ignore the archive header
        while my $buf = .read-data(<blocksize>)
        {
            ...do something with $buf...
        }
    }

These constructs have been packaged up into `Libarchive::Filter` with
two subroutines `archive-encode` and `archive-decode`.  Each take a
`$source`, and a `$destination` that can be most of the normal things.
`archive-encode`, of course, must include 1 or more filters to be
useful.

For example, you can read/write files:

    use Libarchive::Filter;
    archive-encode('Some content', 'file.gz', filter => 'gzip');
    my $content = archive-decode('file.gz');
    ... $content eq 'Some content';

or just use a memory buffer:

    use Libarchive::Filter;
    my $buf = archive-encode('Some content', filter => 'gzip');
    ...encoded into $buf...

    my $content = archive-decode($buf);
    ...$content eq 'Some content'

`archive-encode` sources can be anything that `archive-write` will write:
content in a `Str` or `Buf`, or a filename `IO::Path`, an
`IO::Handle`, a `Supply` or `Channel` of `Blob`s.

`archive-encode` destinations can be anything that `archive-write`
will produce: `Buf`, `IO::Handle`, `Supplier`, `Channel`, or a `Str`
or `IO::Path` filename.

`archive-decode` sources can be anything that `archive-read` will read:
filename in a `Str` or `IO::Path`, `Blob`, `Supply`, `IO::Handle`, or
`Channel`.

`archive-decode` destinations can be `Blob`, `IO::Handle`, `IO::Path`,
`Supplier`, `Channel`. If you don't set a destination, a `Str` with
the content is returned.

Note that the `Str` *into* `archive-encode` or *out* of
`archive-decode` is the content itself, but `Str` *out* of
`archive-encode` or *into* `archive-decode` are filenames.  You can
always use `IO::Path` for a filename.

A number of shortcuts for various filters have also been defined:

    use Libarchive::Filter :gzip;

    my $buf = gzip('Some content');
    my $content = gunzip($buf);

These include:
* `:gzip` -> `gzip()` and `gunzip()`
* `:compress` -> `compress()` and `uncompress()`
* `:bzip2` -> `bzip2()` and `bunzip2()`
* `:lz4` -> `lz4()` and `unlz4()`
* `:uuencode` -> `uuencode()` and `uudecode()`
* `:lzma` -> `lzma()` and `unlzma()`

You can also specify `use Libarchive::Filter :all` to get all the
shortcut routines.

These all take the same options that `archive-encode()` and
`archive-decode()` do and go to/from files, IO::Handles, Supplies,
Channels, etc.

## Formats and Filters

Valid read formats:

'7zip', 'ar', 'cab', 'cpio', 'empty', 'gnutar', 'iso9660', 'lha',
'mtree', 'rar', 'raw', 'tar', 'warc', 'xar', 'zip', 'zip-streamable',
'zip-seekable'

Valid read filters:

'bzip2', 'compress', 'gzip', 'grzip', 'lrzip', 'lz4', 'lzip', 'lzma',
'lzop', 'none', 'rpm', 'uu', 'xz', 'zstd'

You can specify a list of multiple formats/filters to consider if you
want to limit which types you support.  You can also specify 'all' for
either format or filter, which is the default.

Valid write formats:

'7zip', 'ar', 'arbsd', 'argnu', 'arsvr4', 'bsdtar', 'cd9660', 'cpio',
'gnutar', 'iso', 'iso9660', 'mtree', 'mtree-classic', 'newc', 'odc',
'oldtar', 'pax', 'paxr', 'posix', 'raw', 'rpax', 'shar', 'shardump',
'ustar', 'v7tar', 'v7', 'warc', 'xar', 'zip'

Valid write filters:

'b64encode', 'bzip2', 'compress', 'grzip', 'gzip', 'lrzip', 'lz4',
'lzip', 'lzma', 'lzop', 'uuencode', 'xz', 'zstd'

By default, if you write to a file, the extension of the filename will
be used to set the format (and possibly filter):

You can override by explicitly specifying a format and/or filters:

    Libarchive::Write.new('myfile.tar.gz', format => 'zip');

will create a zip file named 'myfile.tar.gz' (but don't do that).

If you are writing to a stream, you _*must*_ specify a format:

    Libarchive::Write.new($*OUT, format => 'zip');

You can optionally specify one or more filters to use while writing.

    Libarchive::Write.new('myfile', format => 'gnutar',
                                 filter => <gzip b64encode>);

Multiple filters are built into a pipeline, so the order they are
listed is significant.

For more details on the specific way that libarchive handles each
format, including some limitations, see the man page:
[libarchive-formats.5](https://github.com/libarchive/libarchive/wiki/ManPageLibarchiveFormats5)
and the
[libarchive wiki](https://github.com/libarchive/libarchive/wiki/LibarchiveFormats).

## Libarchive Entry methods

An `Libarchive::Entry` is sort of like a super-stat, holding all of the
information about a file system component.

`Str` and `gist` return a single line summary of the archive entry,
kind of like an 'ls -l' or 'tar t' listing.

The other methods can query and/or set various information about the
entry:

`pathname`, `size`, `uid`, `gid`, `uname`, `gname`, `fflags`

`perm` - Integer permissions, for new files, defaults to `0o644`, for new
directories, defaults to `0o755`.

`atime`, `mtime`, `ctime`, `birthtime` - Various times, returned as
`DateTime`s.  Depending on the archive format, these might not be set.

`symlink` - for a symbolic link, this is what it points to

`strmode` - Read only unixish string for filetype/permissions
(like `-rw-r--r--` or `drwxr-x-r-x`)

`mode` - file mode, better to use perm and/or filetype

`human-size` - uses [`Number::Bytes::Human`](https://github.com/dugword/Number-Bytes-Human) to process the size, so you get values like "15M", "25K" or "96B" for the
size of a file.

`filetype` - returns an `Libarchive::Filetype` object that numifys to
the Unix/C filetype bits and stringifys to: REG, LINK, SOCK, CHAR,
BLOCK, DIR, FIFO.  You can pass in `:dir` to set filetype to DIR (or
just use '.mkdir');

`is-file` - Bool shortcut to query for filetype REG

`is-dir` - Bool shortcut to query for filetype DIR

## Libarchive Entry Extraction

A `Libarchive::Read` produces `Libarchive::Entry::Read` objects that
are `Libarchive::Entry`s with several additional methods:

`data` reads the content of the entry from the data stream and returns
it as a `Buf`.

`content` - same as `data`, but `decode`s the `Buf` into a Str
(encoding `utf-8` -- if you want other encodings, just call `decode`
on data).

`extract` - extracts the entry into a filesystem entity (file,
directory, symlink, socket, fifo, etc.)

You can change the `pathname` to rename or move the file around.  You
can also pass in `:destpath` either to the main object on creation, or
to `extract()` and it will be prepended to the `pathname`.

You can also pass in extract flags, either to the main object, or to
individual `extract` calls to control the extraction:

## Extract flags:

Extract flags can be specified to `Libarchive::Read.new()`, or to the
`.open()`, or to `.extract()`.  Flags to `.new()` and `.open()` are
sticky, and will affect all future `.open`s as well.  Flags to
`.extract()` are not -- they affect only the specific extract.

`:extract-owner` - The user and group IDs should be set on the restored
file. By default, the user and group IDs are not restored.

`:extract-perm` - Full permissions (including SGID, SUID, and sticky
bits) should be restored exactly as specified, without obeying the
current umask. Note that SUID and SGID bits can only be restored if
the user and group ID of the object on disk are correct. If
`:extract_owner` is not specified, then SUID and SGID bits will only be
restored if the default user and group IDs of newly-created objects on
disk happen to match those specified in the archive entry. By default,
only basic permissions are restored, and umask is obeyed.

`:extract-time` - The timestamps (mtime, ctime, and atime) should be
restored. By default, they are ignored. Note that restoring of atime
is not currently supported.

`:extract-no-overwrite` - Existing files on disk will not be
overwritten. By default, existing regular files are truncated and
overwritten; existing directories will have their permissions updated;
other pre-existing objects are unlinked and recreated from scratch.

`:extract-unlink` - Existing files on disk will be unlinked before any
attempt to create them. In some cases, this can prove to be a
significant performance improvement. By default, existing files are
truncated and rewritten, but the file is not recreated. In particular,
the default behavior does not break existing hard links.

`:extract-acl` - Attempt to restore ACLs. By default, extended ACLs are
ignored.

`:extract-fflags` - Attempt to restore extended file flags. By default,
file flags are ignored.

`:extract-xattr` - Attempt to restore POSIX.1e extended attributes. By
default, they are ignored.

`:extract-secure-symlinks` - Refuse to extract any object whose final
location would be altered by a symlink on disk. This is intended to
help guard against a variety of mischief caused by archives that
(deliberately or otherwise) extract files outside of the current
directory. The default is not to perform this check. If
`:extract-unlink` is specified together with this option, the library
will remove any intermediate symlinks it finds and return an error
only if such symlink could not be removed.

`:extract-secure-nodotdot` - Refuse to extract a path that contains a
.. element anywhere within it. The default is to not refuse such
paths. Note that paths ending in .. always cause an error, regardless
of this flag.

`:extract-secure-noabsolutepaths` - Refuse to extract an absolute
path. The default is to not refuse such paths.

`:extract-sparse` - Scan data for blocks of NUL bytes and try to
recreate them with holes. This results in sparse files, independent of
whether the archive format supports or uses them.

`:extract-clear-nochange-fflags` - Before removing a file system object
prior to replacing it, clear platform-specific file flags which might
prevent its removal.

## Creating a new archive

## Writing to an archive

Using either `Libarchive::Write.new()` or `archive-write()`, there are
a number of methods for adding/creating filesystem entities.

### Add existing filesystem entitities:

`add()` adds existing entities by filename or `IO::Path`.

You may find ecosystem modules such as
[`File::Find`](https://github.com/tadzik/File-Find) or
[`Concurrent::File::Find`](https://github.com/gfldex/perl6-concurrent-file-find)
useful for generating lists of files:

```
    use Libarchive::Simple;
    use Concurrent::File::Find;

    with archive-write('somefile.tar.gz')
    {
        .add '/somedir', find('/somedir'); # Recursively add files
    }
```

If you add files within a directory, don't forget to add the directory
itself if you want it to be created on extraction too.

### Create new files

`write($filename, $content)` will create a new file

`$filename` can be a `Str` or something that will convert to a `Str`,
like an `IO::Path`.  `$content` can be a `Str`, a `Blob`, an
`IO::Handle` from which the content will be read, or an `IO::Path`
from which the content will be read.

### Create directories

`mkdir($pathname)` will add a new directory to the archive

### Create new symbolic links

`symlink($pathname, $symlink)` or
`symlink($pathname => $symlink)`

### Add a sequence of `Archive::Entry`s

Use `copy()` to read from an `archive-read()` or `archive-slurp()`
sequence into a new archive.


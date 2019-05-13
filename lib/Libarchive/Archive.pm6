use Archive::Libarchive::Raw;
use Libarchive::Read;
use Libarchive::Write;
use Libarchive::Entry::Data;

unit class Libarchive::Archive does Associative does Iterable;

has %.entries handles<EXISTS-KEY DELETE-KEY keys values>;

method AT-KEY($key)
{
    fail "File $key does not exist" unless %!entries{$key}:exists;
    %!entries.AT-KEY($key)
}

method new(|opts) { self.bless.copy: Libarchive::Read.new(|opts) }

method copy($seq)
{
    for $seq<>
    {
        my Buf $buf;
        $buf = .data if .is-file;
        %!entries{.pathname} = Libarchive::Entry::Data.new(
            :$buf, entry => archive_entry_clone(.entry));
    }
    self
}

method iterator() { %!entries.values.iterator }

method gist() { join("\n", %!entries.values».gist) }

method Str() { $.gist }

method spurt(|opts)
{
    with Libarchive::Write.new(|opts)
    {
        .copy: %!entries.values.grep: { .is-dir };
        .copy: %!entries.values.grep: { !.is-dir };
        .close;
    }
}

multi method add(*@paths, |opts)
{
    samewith(.IO, |opts) for @paths;
    self
}

multi method add(IO::Path:D $path, Bool :$absolute, *%opts)
{
    my $pathname = $absolute ?? $path.absolute !! $path.relative;

    $path.d ?? $.mkdir($pathname, |%opts)
            !! $.write($pathname, $path.open, |%opts)
}

multi method write(Str:D() $pathname, Blob $buf?, *%opts)
{
    my $entry = Libarchive::Entry::Data.new(:$buf);
    $entry.set: size => $buf ?? $buf.bytes !! 0, :$pathname, |%opts;
    %!entries{$entry.pathname} = $entry;
    self
}

multi method write(Str:D() $pathname, Str:D $str, *%opts)
{
    samewith $pathname, $str.encode, |%opts
}

multi method write(Str:D() $pathname, IO::Handle:D $io, *%opts)
{
    samewith $pathname, $io.slurp(:bin), |%opts
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

=begin pod

=head1 NAME

Libarchive::Archive - Memory based archive

=head1 SYNOPSIS

    use Libarchive::Archive;

    my $archive = Libarchive::Archive.new('this.tar.gz');
    put $archive<README>;   # String contents of README file
    $archive<afile>.content = "Change content\n";
    $archive<adir/bad>:delete;
    $archive.spurt: 'foo.zip';

    with Libarchive::Archive.new() {
        .mkdir: 'adir';
        .write: 'adir/afile', "Some content\n";
        .add: 'fileinfilesystem';
        .spurt: 'foo.zip';
    }

=head1 DESCRIPTION

While the main libarchive modules C<Libarchive::Read> and
C<Libarchive::Write> support streaming archives, this module simply
slurps the entire archive into memory.  You can inspect or alter file
contents or attributes, then spurt the archive back out to disk (or
stream wherever you want it to go.  In general this will be less
efficient than streaming, but can be useful and easier to use for some
use cases.

C<Libarchive::Archive> does Iterable like C<Libarchive::Read> but has
a sequence of C<Libarchive::Entry::Data> objects.  They act almost the
same as the C<Libarchive::Entry::Read> objects, but also hold the
contents of the file in memory.  One main difference, the C<Str>
method results in the contents of the file rather than just a summary.

C<Libarchive::Archive> also does Associative, so you can treat is like
a Hash referencing the contents by the pathname of the object in the
archive.

=head2 METHODS

=head3 new(|opts)

All options are passed to C<Libarchive::Read.new()>, the resulting
archive stream is read into memory.

=head3 copy($seq)

Copy the contents of another archive into this one.

=head3 iterator()

An iterator of the C<Libarchive::Entry::Data> objects that make up
this archive.

=head3 gist()

A listing of this archive, similar to 'ls -l', 'unzip -v' or 'tar tv'.

=head3 Str()

Same as gist()

=head3 spurt(|opts)

Pass all options to a C<Libarchive::Write.new> and send the contents
to that writer.  First send all directories, then all non-directories.
This ensures that during extraction the directories will get created
prior to the files that go in the directory.

=head3 add(*@paths, |opts)
=head3 add(IO::Path:D $path, Bool :$absolute, *%opts)

Add a file or a directory to the archive

=head3 write(Str:D() $pathname, Blob $buf? *%opts)
=head3 write(Str:D() $pathname, Str:D $str, *%opts)
=head3 write(Str:D() $pathname, IO::Handle:D $io, *%opts)

Create a new filesystem entity in the archive.  The contents from a
Blob, Str, or read from an IO::Handle.

=head3 mkdir(Str:D() $pathname, |opts)

Create a new directory in the archive.

=head3 symlink(Str:D() $pathname, Str:D() $symlink, |opts)
=head3 symlink(Pair:D $symlink, |opts)

Create a symbolic link in the archive.

=end pod


use Libarchive::Read;
use Libarchive::Write;

multi archive-decode($source where Str|IO::Path|Blob|Supply|IO::Handle|Channel,
               $dest where Str|Blob|IO::Handle|IO::Path|Supplier|Channel = Str,
              :$format, :$blocksize = 10240, |opts)
    is export(:DEFAULT :all)
{
    my $io;
    my $str = '';

    my &sendit = do given $dest
    {
        when Blob         { -> $dest, $buf       { $dest.append($buf)      } }
        when Str          { -> $dest, $buf       { $str ~= $buf.decode     } }
        when IO::Handle   { -> $dest, $buf       { $dest.write($buf)       } }
        when Supplier     { -> $dest, $buf       { $dest.emit($buf)        } }
        when Channel      { -> $dest, $buf       { $dest.send($buf)        } }
        when IO::Path     { $io = $dest.open(:w, :bin);
                            -> $dest, $buf       { $io.write($buf)         } }
    };

    with Libarchive::Read.new($source, format => 'raw', :blocksize, |opts)
    {
        my $header = .read;
        while my $buf = .read-data($blocksize)
        {
            sendit($dest, $buf);
        }
    }

    given $dest
    {
        when IO::Handle { .close }
        when IO::Path   { .close with $io }
        when Supplier   { .done }
        when Channel    { .close }
    }

    $str || $dest
}

sub archive-encode($source where Str|Blob|IO::Path|IO::Handle,
    $dest where Str|Blob|IO::Path|IO::Handle|Supplier|Channel = Buf.new,
    :$format, :$blocksize = 10240, :$size = 2**62, |opts)
    is export(:DEFAULT :all)
{
    with Libarchive::Write.new($dest, format => 'raw',
                               bytes-per-block => $blocksize, |opts)
    {
        .write('ignore', $source, :$size);
        .close
    }
    $dest
}

sub gzip(|opts) is export(:gzip :all)
{
    archive-encode(|opts, filter => 'gzip')
}

sub gunzip(|opts) is export(:gzip :all)
{
    archive-decode(|opts, filter => 'gzip')
}

sub compress(|opts) is export(:compress :all)
{
    archive-encode(|opts, filter => 'compress')
}

sub uncompress(|opts) is export(:compress :all)
{
    archive-decode(|opts, filter => 'compress')
}

sub bzip2(|opts) is export(:bzip2 :all)
{
    archive-encode(|opts, filter => 'bzip2')
}

sub bunzip2(|opts) is export(:bzip2 :all)
{
    archive-decode(|opts, filter => 'bzip2')
}

sub lz4(|opts) is export(:lz4 :all)
{
    archive-encode(|opts, filter => 'lz4')
}

sub unlz4(|opts) is export(:lz4 :all)
{
    archive-decode(|opts, filter => 'lz4')
}

sub uuencode(|opts) is export(:uuencode :all)
{
    archive-encode(|opts, filter => 'uuencode')
}

sub uudecode(|opts) is export(:uuencode :all)
{
    archive-decode(|opts, filter => 'uu')
}

sub lzma(|opts) is export(:lzma :all)
{
    archive-encode(|opts, filter => 'lzma')
}

sub unlzma(|opts) is export(:lzma :all)
{
    archive-decode(|opts, filter => 'lzma')
}

=begin pod

=head1 NAME

Libarchive::Filter - compression and encoding routines from libarchive

=head1 SYNOPSIS

  use Libarchive::Filter;
  archive-encode('Some content', 'file.gz', filter => 'gzip');
  archive-encode('Some content', $*OUT, filter => 'gzip');
  my $buf = archive-encode('Some content');
  archive-decode($*IN, $*OUT);
  my $content = archive-decode($buf);

  use Libarchive::Filter :gzip;
  gzip('Some content', 'file.gz');
  my $buf = gzip(*$IN);
  gunzip($buf, $*OUT);

=head1 DESCRIPTION

Two main routines, C<archive-encode> and C<archive-decode> that are
wrappers around C<Libarchive::Write> and C<Libarchive::Read>
respectively that perform basic filtering actions without an archive.

There are also a number of shortcuts that simply include a specific
filter.  Those shortcuts will be exported if you pass a specific
option in to the use line for C<Libarchive::Filter>.  You can also
pass in C<:all> to get them all.

C<:gzip> - C<gzip()>, C<gunzip()>

C<:compress> - C<compress()>, C<uncompress()>

C<:bzip2> - C<bzip2()>, C<bunzip2()>

C<:lz4> - C<lz4()>, C<unlz4()>

C<:uuencode> - C<uuencode()>, C<uudecode()>

C<:lzma> - C<lzma()>, C<unlzma()>

=head3 C<archive-encode>($source, $destination?, :$blocksize = 10240,
    :$size = 2**62, *%opts)

C<$source> can be a C<Str> or C<Blob> of content or C<IO::Path>
filename or an C<IO::Handle>.

C<$destination> can be anything C<Libarchive::Write> will write to: a
C<Str> or C<IO::Path> of a filename, or an C<IO::Handle>, C<Supplier>
or C<Channel> of Blobs where to write the encoded data.  The data will
be written in blocks of C<$blocksize> bytes for up to C<$size> bytes
(or until the source is exhausted).

If C<$destination> is omitted, the archive will be returned as a
memory C<Buf>.  (Otherwise C<$destination> will be returned.)

Any other options passed in will be passed in to C<Libarchive::Write>.

Notably, you should pass in C<filter> with one or more filters to
process the data.

=head3 C<archive-decode>($source, $destination?, :$blocksize = 10240, *%opts)

C<$source> can be anything C<Libarchive::Read> will read from: a
C<Str> or C<IO::Path> filename, a C<Blob>, C<IO::Handle>, C<Supply> or
C<Channel> or Blobs.

C<$destination> can be a C<Blob>, C<IO::Path>, C<IO::Handle>,
C<Supplier>, or C<Channel> to write the decoded data to.  If you don't
pass in a destination, the content will be returned as a utf-8 decoded
C<Str>.  (Otherwise the destination will be returned).

Any other options passed in will be passed in to C<Libarchive::Read>.

=end pod

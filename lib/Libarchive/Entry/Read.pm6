use Libarchive::Entry;

unit class Libarchive::Entry::Read does Libarchive::Entry;

has $.libarchive is required;

method data($size = $.size) { $!libarchive.read-data($size) }

method content() { $.data.decode }

method extract(|opts)
{
    self.set(|opts);
    $!libarchive.extract(self, |opts)
}

=begin pod

=head1 NAME

Libarchive::Entry::Read - Readable version of Libarchive::Entry

=head1 SYNOPSIS

  my $entry = Libarchive::Entry::Read.new(libarchive => $read);

  $entry.data;                    # Reads all data
  $entry.data($size);             # Reads $size bytes
  $entry.content;                 # Reads data and decodes to Str
  $entry.extract(|opts);          # extract the entry via libarchive

=head1 DESCRIPTION

An archive entry producing during a streaming read of an archive
via C<Libarchive::Read>.

It provides all the methods of a C<Libarchive::Entry> with several
additional methods.

Note that during streaming, the data can only be read immediately after
the header is read, and can only be read once.

=head2 METHODS

=head3 data($size = $.size)

Reads data from the streaming archive and returns it as a C<Buf>.  By default
reads all the data.  Specify $size to read fewer bytes.  Returns Nil when
there is no more data.

=head3 content()

Reads all the data, then decodes as a utf8 C<Str>.

=head3 extract(|opts)

extract the archive entity to the filesystem.  Optional arguments controlling
the extraction are passed to C<Libarchive::Read.extract()>:

=item $destpath - path prepended to C<pathname> for extraction to disk

=item $verbose - notes a summary of the filesystem entity to STDERR
during extraction.

=item flags - see B<Libarchive::Read.extract-flags>

=end pod

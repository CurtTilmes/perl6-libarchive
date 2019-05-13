use Libarchive::Entry;

unit class Libarchive::Entry::Data does Libarchive::Entry;

has Blob $.buf;

multi method data(Int $size?)
{
    $!buf
}

multi method data(Blob $new)
{
    $!buf = $new;
    $.size($!buf.bytes)
}

method Blob(--> Blob) { $!buf }

method Str(--> Str) { $!buf.decode }

method content() is rw
{
    my $self = self;
    Proxy.new(
        FETCH => method (-->Str)     { $self.Str },
        STORE => method (Str() $new) { $self.data($new.encode) }
    )
}

=begin pod

=head1 NAME

Libarchive::Entry::Data - Memory archive version of Libarchive::Entry

=head1 SYNOPSIS

  my $entry = Libarchive::Entry::Data.new(:$buf);

  $entry.data;                    # Returns the cached data
  $entry.data($size);             # Ignores $size and returns all data
  $entry.data($blob);             # Replace the buffer with new data
  $entry.Blob;                    # Also returns the data as a Buf
  $entry.Str;                     # Returns data data decoded as a Str
  $entry.content;                 # Returns same a Str
  $entry.content = "blah";        # Can also act as an lvalue to set the data

=head1 DESCRIPTION

An archive entry produced by a C<Libarchive::Archive>, It provides all
the methods of a C<Libarchive::Entry> but also includes the cached data
content from the file.

=head2 METHODS

=head3 data($size?)

$size is ignored, it is just included for compatibilita.  Always
returns the cached data buf.

=head3 data(Blob $buf)

Replaces the existing data.

=head3 Blob()

Returns the buffer.

=head3 Str()

Returns the data buffer decoded as a C<Str>.

=head3 content()

Returns the data buffer decoded as a C<Str> but also can act as an lvalue
to set the content to a new C<Str>.

=end pod

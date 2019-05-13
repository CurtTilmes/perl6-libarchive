use Libarchive::Read;
use Libarchive::Write;
use Libarchive::Archive;

sub archive-read(|opts) is export { Libarchive::Read.new(|opts) }

sub archive-write(|opts) is export { Libarchive::Write.new(|opts) }

sub archive-slurp(|opts) is export { Libarchive::Archive.new(|opts) }

sub archive-new() is export { Libarchive::Archive.new }

=begin pod

=head1 NAME

Libarchive::Simple - Simple shortcuts for Libarchive::*

=head1 SYNOPSIS

  use Libarchive::Simple;

  .put for archive-read 'this.tar.gz';       # Archive listing

  .extract for archive-read 'foo.zip';       # Extract all files to disk

  with archive-write 'myfile.tar' {
    .add: 'somefile';
    .mkdir: 'adir';
    .write: 'adir/afile', "Some content\n";
    .close
  }

  my $archive = archive-slurp 'foo.tar';      # Memory archive
  say $archive;                               # Archive listing
  .extract for $archive;
  put $archive<README>;
  $archive.spurt: 'this.zip';

  with archive-new() {
      .add('somefile');
      .mkdir('adir');
      .write('adir/afile', "Some content\n");
      .spurt: 'this.tar.gz';
  }

=head1 DESCRIPTION

Provides short-cuts for various `Libarchive::*` objects:

* C<archive-read> - C<Libarchive::Read.new>

* C<archive-write> - C<Libarchive::Write.new>

* C<archive-slurp> - C<Libarchive::Archive.new>

* C<archive-new> - C<Libarchive::Archive.new>

=end pod

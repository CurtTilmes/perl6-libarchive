use Number::Bytes::Human :functions;
use Archive::Libarchive::Raw;
use BitEnum;

my enum Libarchive::Filetypes (
    REG    => 0o100000,
    LINK   => 0o120000,
    SOCK   => 0o140000,
    CHAR   => 0o020000,
    BLOCK  => 0o060000,
    DIR    => 0o040000,
    FIFO   => 0o010000,
);

class Libarchive::Filetype does BitEnum[Libarchive::Filetypes] {}

role Libarchive::Entry
{
    has archive_entry $.entry = archive_entry_new() // Libarchive.die;

    method set(Str  :$sourcepath,
               Str  :$pathname,
               Int  :$size,
               Bool :$dir,
               Str  :$symlink,
               Str  :$uname,
               Str  :$gname,
               Int  :$uid,
               Int  :$gid,
               Int  :$perm,
               Int  :$mode,
               :$atime,
               :$mtime,
               :$ctime,
               :$birthtime)
    {
        self.sourcepath($_)    with $sourcepath;
        self.pathname($_)      with $pathname;
        self.size($_)          with $size;
        self.uid($_)           with $uid;
        self.gid($_)           with $gid;
        self.uname($_)         with $uname;
        self.gname($_)         with $gname;
        self.perm($_)          with $perm;
        self.mode($_)          with $mode;
        self.atime($_)         with $atime;
        self.mtime($_)         with $mtime;
        self.ctime($_)         with $ctime;
        self.birthtime($_)     with $birthtime;
        self.symlink($symlink) with $symlink;
        self.filetype(DIR)     if $dir;

        self.filetype(REG)     unless +$.filetype;
        self.uname(~$*USER)    unless $.uname;
        self.gname(~$*GROUP)   unless $.gname;
        self.uid(+$*USER)      unless $.uid;
        self.gid(+$*GROUP)     unless $.gid;

        self.atime(now.to-posix[0]) unless $.atime;
        self.mtime(now.to-posix[0]) unless $.mtime;
        self.ctime(now.to-posix[0]) unless $.ctime;
        self.birthtime(now.to-posix[0]) unless $.birthtime;

        unless $.perm { $.perm($.is-dir ?? 0o755 !! 0o644) }
    }

    submethod DESTROY()
    {
        with $!entry
        {
            archive_entry_free($_);
            $!entry = Nil
        }
    }

    method Str() { $.gist() }

    method gist()
    {
        my $time = ($.mtime // $.atime // $.ctime // $.birthtime //
                    DateTime.new(now)).local;

        sprintf("%s %8s/%-8s %5s %s %02d:%02d %s%s",
                $.strmode(),
                $.uname() // $.uid(),
                $.gname() // $.gid(),
                $.human-size,
                $time.yyyy-mm-dd, $time.hour, $time.minute,
                $.pathname() // '',
                (with $.symlink { " -> $_" } else { '' }))
    }

    multi method pathname(Str:D $pathname)
    {
        archive_entry_copy_pathname($_, $pathname) with $!entry; self
    }

    multi method pathname(IO::Path:D $path)
    {
        archive_entry_copy_pathname($_, ~$path) with $!entry; self
    }

    multi method pathname(--> Str)
    {
        archive_entry_pathname($_) with $!entry
    }

    multi method sourcepath(Str:D $path)
    {
        archive_entry_copy_sourcepath($_, $path) with $!entry; self
    }

    multi method sourcepath(--> Str)
    {
        archive_entry_sourcepath($_) with $!entry
    }

    multi method size(Int:D $size)
    {
        archive_entry_set_size($_, $size) with $!entry; self
    }

    method human-size(--> Str)
    {
        format-bytes($.size)
    }

    multi method size(--> Int)
    {
        archive_entry_size($_) with $!entry
    }

    multi method uid(Int:D $uid)
    {
        archive_entry_set_uid($_, $uid) with $!entry; self
    }

    multi method uid(--> Int)
    {
        archive_entry_uid($_) with $!entry
    }

    multi method gid(Int:D $gid)
    {
        archive_entry_set_gid($_, $gid) with $!entry; self
    }

    multi method gid(--> Int)
    {
        archive_entry_gid($_) with $!entry
    }

    multi method filetype(Int:D $filetype)
    {
        archive_entry_set_filetype($_, $filetype) with $!entry; self
    }

    multi method filetype(--> Libarchive::Filetype)
    {
        Libarchive::Filetype.new(archive_entry_filetype($_)) with $!entry
    }

    method is-file(--> Bool)
    {
        $.filetype.isset(REG)
    }

    method is-dir(--> Bool)
    {
        $.filetype.isset(DIR)
    }

    method fflags(--> Str)
    {
        (archive_entry_fflags_text($_) // '') with $!entry
    }

    multi method perm(Int:D $perm)
    {
        archive_entry_set_perm($_, $perm) with $!entry; self
    }

    multi method perm(--> Int)
    {
        archive_entry_perm($_) with $!entry
    }

    method strmode(--> Str)
    {
        archive_entry_strmode($_) with $!entry
    }

    multi method mode(--> Int)
    {
        archive_entry_mode($_) with $!entry
    }

    multi method mode(Int:D $mode)
    {
        archive_entry_set_mode($_, $mode) with $!entry; self
    }

    multi method uname(Str:D $uname)
    {
        archive_entry_copy_uname($_, $uname) with $!entry; self
    }

    multi method uname(--> Str)
    {
        archive_entry_uname($_) with $!entry
    }

    multi method gname(Str:D $gname)
    {
        archive_entry_copy_gname($_, $gname) with $!entry; self
    }

    multi method gname(--> Str)
    {
        archive_entry_gname($_) with $!entry
    }

    multi method atime(DateTime:D $dt)
    {
        $.atime($dt.posix)
    }

    multi method atime(Numeric:D $seconds)
    {
        my $sec = Int($seconds);
        my $nanosec = Int(($seconds - $sec) * 10**9);
        archive_entry_set_atime($_, $sec, $nanosec) with $!entry; self
    }

    multi method atime(--> DateTime)
    {
        DateTime.new(archive_entry_atime($_) || return DateTime) with $!entry
    }

    multi method ctime(DateTime:D $dt)
    {
        $.ctime($dt.posix)
    }

    multi method ctime(Numeric:D $seconds)
    {
        my $sec = Int($seconds);
        my $nanosec = Int(($seconds - $sec) * 10**9);
        archive_entry_set_ctime($_, $sec, $nanosec) with $!entry; self
    }

    multi method ctime(--> DateTime)
    {
        DateTime.new(archive_entry_ctime($_) || return DateTime) with $!entry
    }

    multi method mtime(DateTime:D $dt)
    {
        $.mtime($dt.posix)
    }

    multi method mtime(Numeric:D $seconds)
    {
        my $sec = Int($seconds);
        my $nanosec = Int(($seconds - $sec) * 10**9);
        archive_entry_set_mtime($_, $sec, $nanosec) with $!entry; self
    }

    multi method mtime(--> DateTime)
    {
        DateTime.new(archive_entry_mtime($_) || return DateTime) with $!entry
    }

    multi method birthtime(DateTime:D $dt)
    {
        $.birthtime($dt.posix)
    }

    multi method birthtime(Numeric:D $seconds)
    {
        my $sec = Int($seconds);
        my $nanosec = Int(($seconds - $sec) * 10**9);
        archive_entry_set_birthtime($_, $sec, $nanosec) with $!entry; self
    }

    multi method birthtime(--> DateTime)
    {
        DateTime.new(archive_entry_birthtime($_) || return DateTime) with $!entry
    }

    multi method symlink(--> Str)
    {
        archive_entry_symlink($_) with $!entry
    }

    multi method symlink(Str:D $symlink)
    {
        self.filetype(LINK);
        archive_entry_copy_symlink($_, $symlink) with $!entry; self
    }
}

=begin pod

=head1 NAME

Libarchive::Entry - Class for archive information about a single entry

=head1 SYNOPSIS

  my $entry = Libarchive::Entry.new;

  $entry.set(perm => 0o600, uname => 'foo');

  say $entry.perm;

  $entry.perm(0o600);

=head1 DESCRIPTION

A sort of super stat with all the information related to a single archive
entity.

=head2 METHODS

=head3 set(Str :$sourcepath, Str :$pathname, Int :$size, Bool :$dir,
Str :$symlink, Str :$uname, Str :$gname, Int :$uid, Int :$gid,
Int :$perm, Int :$mode, :$atime, :$mtime, :$ctime, :$birthtime)

Sets the specified fields, the sets some defaults if not otherwise set.

=item filetime = REG
=item uname = ~$*USER
=item gname = ~$*GROUP
=item uid = +$*USER
=item gid = +$*GROUP
=item atime,mtime,ctime,birthtime = now
=item perm = 0o755 for directories and 0o644 for files

=head3 Str()

A one line summary of the entry, similar to 'ls -l' or 'tar xv'

=head3 gist()

same as Str()

=head3 pathname

=head3 sourcepath

=head3 size

=head3 human-size
  Uses C<Number::Bytes::Human> to format the size into a string like
  27B, or 15K, etc.

=head3 uid

=head3 gid

=head3 filetype

=head3 is-file

=head3 is-dir

=head3 fflags

=head3 perm

=head3 strmode

=head3 mode

=head3 uname

=head3 gname

=head3 atime

=head3 ctime

=head3 mtime

=head3 birthtime

=head3 symlink

=end pod

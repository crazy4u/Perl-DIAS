#!perl

# Infos to store
# diskname, path, filename, extension, category, size, crc

use strict;

use FileHandle;
use DirHandle;
use File::Basename;
use Archive::Zip;

my $crc_path        = 'E:/crc_files';
my $script_basename = basename($0);
die
  "usage: $script_basename drive_letter disk-serial (only the last 4 digits/letters) partition_name\n"
  if @ARGV != 3;

my $DiskID = $ARGV[1] . '_' . $ARGV[2];

my $ListName = $crc_path . '/' . $DiskID . '.txt';
my $LogName  = $crc_path . '/' . $DiskID . '.lst';

my $fhlog = new FileHandle(">$LogName");

my %f = ();

my $RewriteFilelist = 0;
my $file_entries    = 0;
my $sum_unchanged   = 0;
my $sum_changed     = 0;
my $sum_deleted     = 0;

##################################################
# Step 1: read existing file list (if it exists)
##################################################
if (-e $ListName) {
  print("Reading existing file list $ListName\n");
  my $fh = new FileHandle($ListName);
  while (<$fh>) {
    chomp;
    s/^\"//;
    s/\"$//;
    my ($size, $crc, $date, $disk, $path, $file, $ext) = split(/\";\"/);

    #next if ($SCHRANKE > 0 && $size < $SCHRANKE);
    my $key1 = "$path/$file";
    $f{$key1}{date} = $date;
    $f{$key1}{ext}  = $ext;
    $f{$key1}{size} = $size;
    $f{$key1}{crc}  = $crc;
    $f{$key1}{op}   = 'O';     # O = Old
    $file_entries++;
  }
  $fh->close;
  print("  $file_entries entries read\n");
  $sum_deleted = $file_entries;
}

##############################
# Step 2: process filesystem
##############################
my $processed = 0;
my $start     = time;
print("Processing filesystem on disk $ARGV[0]\n");
process_dir($ARGV[0] . ':');
print "Total time for disk $DiskID: ", time - $start, " seconds\n";
print "Time per file: ", (time - $start) / $processed, " seconds\n";

###################################
# Step 3: write updated file list
###################################
if ($RewriteFilelist == 0 && $file_entries == $sum_unchanged) {
  print("Disk $DiskID has not changed. File list update not necessary.\n");
}
else {
  print("  Deleted files: $sum_deleted\n");
  print("  Changed files: $sum_changed\n");
  print("Unchanged files: $sum_unchanged\n");
  print("Writing updated file list to $ListName\n");
  my $fh = new FileHandle(">$ListName");
  foreach my $key (sort keys %f) {
    next if ($f{$key}{op} eq 'O');    # don't write old (= deleted) file entries
    my ($path, $filename) = ($key =~ m{ \A (.*) / ([^/]+) \z }xms);

    # size, crc, date, diskname, path, filename, extension, category
    $fh->print(
      '"',
      join('";"',
        $f{$key}{size}, $f{$key}{crc}, $f{$key}{date}, $DiskID,
        $path,          $filename,     $f{$key}{ext}),
      '"', "\n"
    );
  }
  $fh->close;
}
print("--- Finished ---\n");

########################
# END of main program
########################

sub process_dir {
  my ($dir) = @_;

  $fhlog->print("$dir ($processed)\n");

  my @entries;

  my $d = new DirHandle $dir;
  if (defined $d) {
    @entries = $d->read;
    undef $d;
    foreach my $e (sort @entries) {
      next if ($e =~ /^\.+$/);
      if (-d "$dir/$e") {
        process_dir("$dir/$e");
      }
      else {
        process_file("$dir/$e");
      }
    }
  }
}

sub process_file {
  my ($file) = @_;

  my $ext;
  my $crc;

  my $filename = basename($file);
  my $path     = dirname($file);
  $path =~ s{ \A \w : } {\.}xms;

  my $localpath = "$path/$filename";

  my $size = -s $file;
  $size = '0' x (11 - length($size)) . $size;

  if (exists($f{$localpath}) && $f{$localpath}{size} == $size) {
    $f{$localpath}{op} = 'U';    # U = Unchanged
    $sum_unchanged++;
    $sum_deleted--;
  }
  else {
    $RewriteFilelist = 1;
    $sum_changed++;
    $sum_deleted--;

    my @aaa  = stat($file);
    my $date = (stat($file))[9];

    $ext                 = $filename =~ /\.([^\.]+)$/ ? $1 : '';
    $crc                 = crc32($file);
    $f{$localpath}{op}   = 'N';                                    # N = New
    $f{$localpath}{size} = $size;
    $f{$localpath}{date} = $date;
    $f{$localpath}{ext}  = $ext;
    $f{$localpath}{crc}  = $crc;
  }

  $processed++;
}

sub crc32 {
  if (-d $_[0]) {
    warn "$_[0]: Is a directory\n";
    return '00000000';
  }
  my $fh = FileHandle->new();
  if (!$fh->open($_[0], 'r')) {
    warn "$_[0]: $!\n";
    return '00000000';
  }
  binmode($fh);
  my $buffer;
  my $bytesRead;
  my $crc = 0;
  $bytesRead = $fh->read($buffer, 32768);
  $crc = Archive::Zip::computeCRC32($buffer, $crc);
  return sprintf("%08x", $crc);
}

#!perl

use strict;
use FileHandle;
use DirHandle;
use File::Basename;
use Archive::Zip;

my %f = ();

# Test results for my whole disk collection with
# different settings of $limit
#-------------------------------------------------
# with $limit=0        ~ 263 GB saved
# with $limit=100000   ~ 239 GB saved
# with $limit=10000000 ~ 156 GB saved
#-------------------------------------------------
# Files with size < $limit bytes are not processed
#-------------------------------------------------
my $limit = 100000;

my $d       = new DirHandle '.';
my @entries = $d->read;
undef $d;

my $total_entries = 0;
foreach my $infile (sort @entries) {
  next if -d $infile;
  next if $infile !~ /\.txt$/;
  next if $infile =~ /_ERRORS.txt$/;
  my $fh = new FileHandle;
  $fh->open($infile);
  my $file_entries = 0;
  print "processing $infile\n";
  while (<$fh>) {
    chomp;
    s/^\"//;
    s/\"$//;
    my ($size, $crc, $date, $disk, $path, $file, $ext) = split(/\";\"/);
    next if ($limit > 0 && $size < $limit);
    my $key = "$size;$crc";
    my $i   = $f{$key}{count}++;
    $f{$key}{date}[$i] = $date;
    $f{$key}{disk}[$i] = $disk;
    $f{$key}{path}[$i] = $path;
    $f{$key}{file}[$i] = $file;
    $f{$key}{ext}[$i]  = $ext;
    $file_entries++;
  }
  $fh->close;
  $total_entries += $file_entries;
  print "$infile ($file_entries entries)\nTotal entries: $total_entries\n";
}

my $fhout = new FileHandle;
$fhout->open(">dups.lst");

my $spar = 0;
foreach my $key (sort { $b cmp $a } keys %f) {
  next if ($f{$key}{count} == 1);
  my ($size, $crc) = split(/;/, $key);

  $fhout->print("------------------------------\n");

  for (my $i = 0 ; $i < $f{$key}{count} ; $i++) {
    if ($i > 0) {
      $spar += $size;
    }
    $fhout->print(
      '"',
      join('";"',
        $size,              $crc,               $f{$key}{date}[$i],
        $f{$key}{disk}[$i], $f{$key}{path}[$i], $f{$key}{file}[$i],
        $f{$key}{ext}[$i]),
      '"', "\n"
    );
  }
}
$fhout->close;
print "You may save $spar bytes\n";

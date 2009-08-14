#!perl

use strict;
use warnings;
use Carp;

use File::Find;
use FileHandle;
use Getopt::Long;

my $ExtRegExp   = '';
my $ExtNegation = '';
my $OrigFormat  = 0;

my $getopt_result = GetOptions(
  "extensions=s"    => \$ExtRegExp,
  "original-format" => \$OrigFormat,
);

if ($ExtRegExp ne '') {
  ($ExtNegation, $ExtRegExp) = ($ExtRegExp =~ m{ \A ([\!]?) (.*) \z }xms);
}

my $StartDir = shift @ARGV;
if (!-d $StartDir) {
  croak "'$StartDir' is not a directory";

  #$StartDir = '.';
}

my %rh;    # result hash

sub wanted {

  # search only main dir ( '.' ). Subdirs are skipped by setting 'prune'.
  if (-d $_ && $_ !~ /^\.$/) {
    $File::Find::prune = 1;
  }

  return if !-f $_ || $_ !~ /\.txt$/i;

  #print STDERR $_, "\n";
  process_list($_);
}

# transform arguments (regular expressions) into anonymous subroutine
my $AnonSubStr = "sub {\n";    #  local \$_ = shift \@_;\n";
foreach my $regexp (@ARGV) {
  my ($negation, $re) = ($regexp =~ m{ \A ([\!]?) (.*) \z }xms);
  if ($negation eq '!') {
    $AnonSubStr .= "  return 0 unless \${\$_[0]} !~ /$re/i;\n";
  }
  else {
    $AnonSubStr .= "  return 0 unless \${\$_[0]} =~ /$re/i;\n";
  }
}
$AnonSubStr .= "  return 1;\n}\n";
my $Is_A_Match;
eval("\$Is_A_Match = $AnonSubStr");

find({wanted => \&wanted}, $StartDir);

sub process_list {
  my ($listname) = @_;

  my $fh = FileHandle->new($listname);
  my ($size, $crc, $date, $disk, $path, $file, $ext);
  my $line;
  my $lc = 0;
LINE:
  while (<$fh>) {
    $line = $_;
    $lc++;
    next LINE
      unless ($Is_A_Match->(\$line));
    chomp;
    s/^"(.*)"$/$1/;
    ($size, $crc, $date, $disk, $path, $file, $ext) = split(/";"/);
    if (!defined($path)) {
      print "ERROR: Input line = \n$line (line $lc)\n";
      confess;
    }

    if ($ExtRegExp ne '') {
      local $_ = $ext;
      if ($ExtNegation eq '!') {
        next LINE
          if /$ExtRegExp/i;
      }
      else {
        next LINE
          unless /$ExtRegExp/i;
      }
    }

    if ($OrigFormat) {
      print $line;
      next LINE;
    }

    my $i;
    if (exists $rh{"$size,$crc"}) {
      $i = @{$rh{"$size,$crc"}};
    }
    else {
      $i = 0;
    }

    #$size += 0;
    $path =~ s/^\.//;
    $rh{"$size,$crc"}[$i]{date} = $date;
    $rh{"$size,$crc"}[$i]{path} = $disk . ':' . $path . '/' . $file;
  }
  $fh->close;
}

if (!$OrigFormat) {
  foreach my $key (sort keys %rh) {
    my ($size, $crc) = split(/,/, $key);
    my $Dup = ' ';
    foreach my $sh (@{$rh{$key}}) {
      printf("%s%9s: %s (%s)\n",
        $Dup, bkm($size), $sh->{path}, scalar(localtime($sh->{date})));
      $Dup = 'D';
    }
  }
}

# calculate size in bytes, kilobytes, megabytes, gigabytes
sub bkm {
  my $size = shift @_;

  my $divcount = 0;
  my $genau;

  my @bez = ('', 'K', 'M', 'G');

  while ($size > 1024) {
    $size /= 1024;
    $divcount++;
  }
  if ($bez[$divcount] eq 'M' || $bez[$divcount] eq 'G') {
    $genau = 100;
  }
  else {
    $genau = 1;
  }
  my $iv  = int($size * $genau + 0.5) / $genau;
  my $ret = $iv . $bez[$divcount] . 'B';
  return $ret;
}

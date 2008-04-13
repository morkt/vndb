#!/usr/bin/perl

use strict;
use warnings;
use Time::HiRes 'gettimeofday', 'tv_interval';
BEGIN {
  our $ST = [ gettimeofday ];
}
use DBI;
use Image::Magick;
use Image::MetaData::JPEG;
use File::Copy 'cp', 'mv';
use Digest::MD5;

our $ST;

my $sql = DBI->connect('dbi:Pg:dbname=vndb', 'vndb', 'passwd',
    { RaiseError => 1, PrintError => 0, AutoCommit => 1, pg_enable_utf8 => 1 });

my $imgpath = '/www/vndb/static/img';
my $tmpimg = '/tmp/vndb-clearimg.jpg';

imgscan();

printf "Finished in %.3f seconds\n", tv_interval($ST);

sub imgscan {
  print "Scanning images...\n";
  my $done = 0;
  for my $c ('0'..'9', 'a'..'f') {
    opendir(my $D, "$imgpath/$c") || die "$imgpath/$c: $!";
    for my $f (readdir($D)) {
      my $cur = "$imgpath/$c/$f";
      next if !-s $cur || $f !~ /^(.+)\.jpg$/;
      my $cmd5 = $1;

     # delete unused images
      if($f =~ /^tmp/ || $f =~ /\.jpg\.jpg$/) {
        printf "Deleting temp image %s/%s\n", $c, $f;
        unlink $cur or die $!;
        next;
      }
      my $q = $sql->prepare('SELECT 1 FROM vn_rev WHERE image = DECODE(?, \'hex\')');
      $q->execute($cmd5);
      my $d = $q->fetchrow_arrayref();
      if(!$d || ref($d) ne 'ARRAY' || $d->[0] <= 0) {
        printf "Deleting %s/%s\n", $c, $f;
        unlink $cur or die $!;
        $done++;
        next;
      }
      $q->finish();

     # remove metadata
      my $i = Image::MetaData::JPEG->new($cur);
      $i->drop_segments('METADATA');
      $i->save($tmpimg);
      if(-s $tmpimg < (-s $cur)-32) {
        printf "Removed metadata from %s/%s: %.2f to %.2f kB\n", $c, $f, (-s $cur)/1024, (-s $tmpimg)/1024;
        cp $tmpimg, $cur;
      }

     # compress large images
      if(-s $cur > 20*1024) { # > 20 KB
        $i = Image::Magick->new;
        $i->Read($cur);
        $i->Set(quality => 80);
        $i->Write($tmpimg);
        undef $i;
        #if(-s $tmpimg > 35*1024) { # extremely large images get a quality of 65
        #  $i = Image::Magick->new;
        #  $i->Read($cur);
        #  $i->Set(quality => 65);
        #  $i->Write($tmpimg);
        #  undef $i;
        #}
        if(-s $tmpimg < (-s $cur)-1024) {
          printf "Compressed %s/%s from %.2f to %.2f kB\n", $c, $f, (-s $cur)/1024, (-s $tmpimg)/1024;
          cp $tmpimg, $cur or die $!;
          $done++;
        }
      }

     # rename file if MD5 is different
      open(my $T, '<:raw:bytes', $cur) || die $!;
      my $md5 = Digest::MD5->new()->addfile($T)->hexdigest;
      close($T);
      if($md5 ne $cmd5) {
        $sql->do('UPDATE vn_rev SET image = DECODE(?, \'hex\') WHERE image = DECODE(?, \'hex\')', undef, $md5, $cmd5);
        mv $cur, sprintf "%s/%s/%s.jpg", $imgpath, substr($md5, 0, 1), $md5 or die $!;
        printf "Renamed %s/%s to %s/%s\n", $c, $cmd5, substr($md5, 0, 1), $md5;
      }
    }
    closedir($D);
  }
  unlink $tmpimg;
  print "Everything seems to be ok\n" if !$done;
}



1;

#!/usr/bin/perl

use strict;
use warnings;

use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/lang\.pl$}{}; }

use lib $ROOT.'/lib';
use LangFile;

my $langtxt = "$ROOT/data/lang.txt";


sub usage {
  print <<__;
$0 stats
  Prints some stats.

$0 add <lang> [<file>]
  Adds new (empty) translation lines for language <lang> to <file> (defaults to
  the global lang.txt) for keys that don't have a TL line yet.

$0 only <lang>[,..] <outfile>
  Makes a copy of lang.txt to <outfile> and removes all translations except the
  ones of langauge <lang> (comma-seperated list of tags)

$0 merge <lang> <file>
  Merges <file> into lang.txt, copying over all the translations of <lang> in
  <file> while ignoring any other changes. Keys in <file> not present in
  lang.txt are silently ignored. Keys in lang.txt but not in <file> remain
  unaffected. Make sure each key in lang.txt already has a line for <lang>,
  otherwise do an 'add' first.

$0 reorder <lang1>,<lang2>,..
  Re-orders the translation lines in lang.txt using the specified order.
__
  exit;
}


sub stats {
  my $r = LangFile->new(read => $langtxt);
  my $keys = 0;
  my %lang;
  while(my $l = $r->read()) {
    $keys++ if $l->[0] eq 'key';
    if($l->[0] eq 'tl') {
      $lang{$l->[1]} ||= [0,0];
      $lang{$l->[1]}[0]++;
      $lang{$l->[1]}[1]++ if $l->[2];
    }
  }
  print  "lang  lines        sync         unsync\n";
  printf "%3s   %4d (%3d%%)  %4d (%3d%%)  %4d\n", $_,
    $lang{$_}[0], $lang{$_}[0]/$keys*100, $lang{$_}[1], $lang{$_}[1]/$keys*100, $keys-$lang{$_}[1]
    for keys %lang;
  printf "Total keys: %d\n", $keys;
}


sub add {
  my($lang, $file) = @_;
  $file ||= $langtxt;
  my $r = LangFile->new(read => $file);
  my $w = LangFile->new(write => "$file~");
  my $k = 0;
  while((my $l = $r->read())) {
    if($k && $l->[0] ne 'tl') {
      $k = 0;
      $w->write('tl', $lang, 0, '');
    }
    $k = 1 if $l->[0] eq 'key';
    $k = 0 if $l->[0] eq 'tl' && $l->[1] eq $lang;
    $w->write(@$l);
  }
  $r->close;
  $w->close;
  rename "$file~", $file or die $!;
}


sub only {
  my($lang, $out) = @_;
  my @lang = split /,/, $lang;
  my $r = LangFile->new(read => $langtxt);
  my $w = LangFile->new(write => $out);
  while((my $l = $r->read())) {
    $w->write(@$l) unless $l->[0] eq 'tl' && !grep $_ eq $l->[1], @lang;
  }
  $r->close;
  $w->close;
}


sub merge {
  my($lang, $file) = @_;

  # read all translations in $lang in $file
  my $trans = LangFile->new(read => $file);
  my($key, %trans);
  while((my $l = $trans->read)) {
    $key = $l->[1] if $l->[0] eq 'key';
    $trans{$key} = [ $l->[2], $l->[3] ] if $l->[0] eq 'tl' && $l->[1] eq $lang;
  }
  $trans->close;

  # now update lang.txt
  my $r = LangFile->new(read => $langtxt);
  my $w = LangFile->new(write => "$langtxt~");
  while((my $l = $r->read)) {
    $key = $l->[1] if $l->[0] eq 'key';
    ($l->[2], $l->[3]) = @{$trans{$key}} if $l->[0] eq 'tl' && $l->[1] eq $lang && $trans{$key};
    $w->write(@$l);
  }
  $r->close;
  $w->close;
  rename "$langtxt~", $langtxt or die $!;
}


sub reorder {
  my @lang = split /,/, shift;
  my $r = LangFile->new(read => $langtxt);
  my $w = LangFile->new(write => "$langtxt~");
  my($key, %tl);
  while((my $l = $r->read)) {
    if($key && $l->[0] ne 'tl') {
      $tl{$_} && $w->write(@{delete $tl{$_}}) for(@lang);
      $w->write(@{$tl{$_}}) for sort keys %tl;
      $key = undef;
      %tl = ();
    }
    $key = $l->[1] if $l->[0] eq 'key';
    $tl{$l->[1]} = $l if $l->[0] eq 'tl';
    $w->write(@$l) unless $l->[0] eq 'tl';
  }
  $r->close;
  $w->close;
  rename "$langtxt~", $langtxt or die $!;
}


usage if !@ARGV;
my $act = shift;
stats if $act eq 'stats';
add @ARGV if $act eq 'add';
only @ARGV if $act eq 'only';
merge @ARGV if $act eq 'merge';
reorder @ARGV if $act eq 'reorder';


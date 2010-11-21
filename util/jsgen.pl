#!/usr/bin/perl

package VNDB;

use strict;
use warnings;
use Encode 'encode_utf8';
use Cwd 'abs_path';
eval { require JavaScript::Minifier::XS; };

our($ROOT, %S);
BEGIN { ($ROOT = abs_path $0) =~ s{/util/jsgen\.pl$}{}; }
require $ROOT.'/data/global.pl';

use lib "$ROOT/lib";
use lib "$ROOT/yawf/lib";
use LangFile;

# The VNDB::L10N module is not really suited to be used outside the VNDB::*
# framework, but it's the central location that defines which languages we have
# and in what order to display them.
use VNDB::L10N;


sub l10n {
  # parse the .js code to find the l10n keys to use
  my $js = shift;
  my @keys;
  push @keys, $1 ? quotemeta($1) : qr/$2/ while($js =~ m{(?:mt\('([a-z0-9_]+)'[,\)]|l10n /([^/]+)/)}g);
  # also add the _lang_* for all languages for which we have a translation
  my $jskeys_lang = join '|', VNDB::L10N::languages();
  push @keys, qr/_lang_(?:$jskeys_lang)/;

  # fetch the corresponding text from lang.txt
  my %lang; # key1 => { lang1 => .., lang2 => .. }, key2 => { .. }
  my $lang = LangFile->new(read => "$ROOT/data/lang.txt");
  my $cur; # 0 = none/excluded, 1 = TL lines
  my $key;
  while((my $l = $lang->read())) {
    my $type = shift @$l;
    if($type eq 'key') {
      my $k = shift @$l;
      $cur = grep $k =~ /$_/, @keys;
      $key = $k;
    }
    if($type eq 'tl' && $cur) {
      my($lang, $sync, $val) = @$l;
      next if !$val;
      $lang{$key}{$lang} = $val;
    }
  }

  # generate JS code
  my $r = "L10N_STR = {\n";
  my $first = 1;
  for my $key (sort keys %lang) {
    $r .= ",\n" if !$first;
    $first = 0;
    $r .= sprintf qq|  %s: {\n|, $key !~ /^[a-z0-9_]+$/ ? "'$key'" : $key;;
    my $firstk = 1;
    for (sort keys %{$lang{$key}}) {
      $r .= ",\n" if !$firstk;
      $firstk = 0;
      my $lang = $_;
      $lang = qq{"$lang"} if $lang =~ /^(?:as|do|if|in|is)$/; # reserved two-char words
      my $val = $lang{$key}{$_};
      $val =~ s/"/\\"/g;
      $val =~ s/\n/\\n/g;
      $r .= sprintf qq|    %s: "%s"|, $lang, $val;
    }
    $r .= "\n  }";
  }
  $r .= "\n};\n";
  $r .= 'L10N_LANG = [ '.join(', ', map qq{"$_"}, VNDB::L10N::languages()).' ];';
  return "$r\n";
}


# screen resolution information, suitable for usage in filFSelect()
sub resolutions {
  my $res_cat = '';
  my $resolutions = '';
  my $comma = 0;
  for my $i (0..$#{$S{resolutions}}) {
    my $r = $S{resolutions}[$i];
    if($res_cat ne $r->[1]) {
      $resolutions .= ']' if $res_cat;
      $resolutions .= ",['$r->[1]',";
      $res_cat = $r->[1];
      $comma = 0;
    }
    $resolutions .= ($comma ? ',' : '')."[$i,'$r->[0]']";
    $comma = 1;
  }
  $resolutions .= ']' if $res_cat;
  return "resolutions = [ $resolutions ];\n";
}


sub jsgen {
  # JavaScript::Minifier::XS doesn't correctly handle perl's unicode,
  #  so just do everything in raw bytes instead.
  open my $JS, '<', "$ROOT/data/script.js" or die $!;
  my $js .= join '', <$JS>;
  close $JS;
  my $head = encode_utf8(l10n($js)) . "\n";
  $head .= sprintf "rlst_rstat = [ %s ];\n", join ', ', map qq{"$_"}, @{$S{rlst_rstat}};
  $head .= sprintf "rlst_vstat = [ %s ];\n", join ', ', map qq{"$_"}, @{$S{rlst_vstat}};
  $head .= sprintf "cookie_prefix = '%s';\n", $S{cookie_prefix};
  $head .= sprintf "age_ratings = [ %s ];\n", join ',', map !defined $_ ? -1 : $_, @{$S{age_ratings}};
  $head .= sprintf "languages = [ %s ];\n", join ', ', map qq{"$_"}, @{$S{languages}};
  $head .= sprintf "platforms = [ %s ];\n", join ', ', map qq{"$_"}, @{$S{platforms}};
  $head .= sprintf "media = [ %s ];\n", join ', ', map qq{"$_"}, sort keys %{$S{media}};
  $head .= sprintf "release_types = [ %s ];\n", join ', ', map qq{"$_"}, sort @{$S{release_types}};
  $head .= resolutions();
  open my $NEWJS, '>', "$ROOT/static/f/script.js" or die $!;
  print $NEWJS $JavaScript::Minifier::XS::VERSION ? JavaScript::Minifier::XS::minify($head.$js) : $head.$js;
  close $NEWJS;
}

jsgen;


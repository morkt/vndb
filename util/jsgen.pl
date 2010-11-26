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



my %lang; # lang1 => { key1 => .., key22 => .. }, lang2 => { .. }

sub l10n_load {
  # fetch all text from lang.txt
  my $lang = LangFile->new(read => "$ROOT/data/lang.txt");
  my $key;
  while((my $l = $lang->read())) {
    my $type = shift @$l;
    $key = shift @$l if $type eq 'key';
    $lang{$l->[0]}{$key} = $l->[2] if $type eq 'tl';
  }
}


sub l10n {
  my($lang, $js) = @_;

  # parse the .js code and replace mt()'s that can be modified in-place, otherwise add to the @keys
  my @keys;
  $js =~ s{(?:mt\('([a-z0-9_]+)'([,\)])|l10n /([^/]+)/)}#
    my($k, $s, $q) = ($1, $2, $3);
    my $v = $k ? $lang{$lang}{$k} || $lang{'en'}{$k} : '';
    if($q) { $q ne '<perl regex>' && push @keys, qr/$q/; '' }
    elsif($s eq ')' && $v && $v !~ /[\~\[\]]/) {
      $v =~ s/"/\\"/g;
      $v =~ s/\n/\\n/g;
      qq{"$v"}
    } else {
      push @keys, quotemeta($k);
      "mt('$k'$s"
    }
  #eg;
  # also add the _lang_* for all languages for which we have a translation
  my $jskeys_lang = join '|', VNDB::L10N::languages();
  push @keys, qr/_lang_(?:$jskeys_lang)/;

  # generate header
  my $r = "L10N_STR = {\n";
  my $first = 1;
  for my $key (sort keys %{$lang{$lang}}) {
    next if !grep $key =~ /$_/, @keys;
    $r .= ",\n" if !$first;
    $first = 0;
    my $val = $lang{$lang}{$key} || $lang{'en'}{$key};
    $val =~ s/"/\\"/g;
    $val =~ s/\n/\\n/g;
    $r .= sprintf qq|  %s: "%s"|, $key !~ /^[a-z0-9_]+$/ ? "'$key'" : $key, $val;
  }
  $r .= "\n};";
  return ("$r\n", $js);
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
  l10n_load();
  my $common = '';
  $common .= resolutions();
  $common .= sprintf "rlst_rstat = [ %s ];\n", join ', ', map qq{"$_"}, @{$S{rlst_rstat}};
  $common .= sprintf "rlst_vstat = [ %s ];\n", join ', ', map qq{"$_"}, @{$S{rlst_vstat}};
  $common .= sprintf "cookie_prefix = '%s';\n", $S{cookie_prefix};
  $common .= sprintf "age_ratings = [ %s ];\n", join ',', map !defined $_ ? -1 : $_, @{$S{age_ratings}};
  $common .= sprintf "languages = [ %s ];\n", join ', ', map qq{"$_"}, @{$S{languages}};
  $common .= sprintf "platforms = [ %s ];\n", join ', ', map qq{"$_"}, @{$S{platforms}};
  $common .= sprintf "media = [ %s ];\n", join ', ', map qq{"$_"}, sort keys %{$S{media}};
  $common .= sprintf "release_types = [ %s ];\n", join ', ', map qq{"$_"}, @{$S{release_types}};
  $common .= sprintf "animated = [ %s ];\n", join ', ', @{$S{animated}};
  $common .= sprintf "L10N_LANG = [ %s ];\n", join(', ', map qq{"$_"}, VNDB::L10N::languages());

  open my $JS, '<:utf8', "$ROOT/data/script.js" or die $!;
  my $js .= join '', <$JS>;
  close $JS;

  for my $l (VNDB::L10N::languages()) {
    my($head, $body) = l10n($l, $js);
    # JavaScript::Minifier::XS doesn't correctly handle perl's unicode, so manually encode
    my $content = encode_utf8($head . $common . $body);
    open my $NEWJS, '>', "$ROOT/static/f/js/$l.js" or die $!;
    print $NEWJS $JavaScript::Minifier::XS::VERSION ? JavaScript::Minifier::XS::minify($content) : $content;
    close $NEWJS;
  }
}

jsgen;


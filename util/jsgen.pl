#!/usr/bin/perl

package VNDB;

use strict;
use warnings;
use Encode 'encode_utf8';
use Cwd 'abs_path';
use JSON::XS;
eval { require JavaScript::Minifier::XS; };

our($ROOT, %S, %O);
BEGIN { ($ROOT = abs_path $0) =~ s{/util/jsgen\.pl$}{}; }
require $ROOT.'/data/global.pl';

use lib "$ROOT/lib";
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

  my %keys;
  for my $key (sort keys %{$lang{$lang}}) {
    next if !grep $key =~ /$_/, @keys;
    my $val = $lang{$lang}{$key} || $lang{'en'}{$key};
    $val =~ s/"/\\"/g;
    $val =~ s/\n/\\n/g;
    $val =~ s/\[index,.+$// if $key =~ /^_vnlength_/; # special casing the VN lengths, since the JS mt() doesn't handle [index]
    $keys{$key} = $val;
  }
  (\%keys, $js);
}


# screen resolution information, suitable for usage in filFSelect()
sub resolutions {
  my $ln = shift;
  my $cat = '';
  my @r;
  my $push = \@r;
  for my $i (0..$#{$S{resolutions}}) {
    my $r = $S{resolutions}[$i];
    if($cat ne $r->[1]) {
      push @r, [$r->[1] =~ /^_/ ? $lang{$ln}{$r->[1]}||$lang{'en'}{$r->[1]} : $r->[1]];
      $cat = $r->[1];
      $push = $r[$#r];
    }
    my $n = $r->[0] =~ /^_/ ? $lang{$ln}{$r->[0]}||$lang{'en'}{$r->[0]} : $r->[0];
    push @$push, [$i, $n];
  }
  \@r
}


sub vars {
  my($lang, $l10n) = @_;
  my %vars = (
    rlist_status  => $S{rlist_status},
    cookie_prefix => $O{cookie_prefix},
    age_ratings   => $S{age_ratings},
    languages     => $S{languages},
    platforms     => $S{platforms},
    char_roles    => $S{char_roles},
    media         => [sort keys %{$S{media}}],
    release_types => $S{release_types},
    animated      => $S{animated},
    voiced        => $S{voiced},
    vn_lengths    => $S{vn_lengths},
    blood_types   => $S{blood_types},
    genders       => $S{genders},
    char_roles    => $S{char_roles},
    staff_roles   => $S{staff_roles},
    resolutions   => scalar resolutions($lang),
    l10n_lang     => [ map [ $_, $lang{$_}{"_lang_$_"}||$lang{en}{"_lang_$_"} ], VNDB::L10N::languages() ],
    l10n_str      => $l10n,
  );
  JSON::XS->new->encode(\%vars);
}


# Reads main.js and any included files.
sub readjs {
  my $f = shift || 'main.js';
  open my $JS, '<:utf8', "$ROOT/data/js/$f" or die $!;
  local $/ = undef;
  local $_ = <$JS>;
  close $JS;
  s{^//include (.+)$}{'(function(){'.readjs($1).'})();'}meg;
  $_;
}


sub jsgen {
  my $js = readjs 'main.js';

  for my $l (VNDB::L10N::languages()) {
    my($l10n, $body) = l10n($l, $js);
    $body =~ s{/\*VARS\*/}{vars($l, $l10n)}eg;

    # JavaScript::Minifier::XS doesn't correctly handle perl's unicode, so manually encode
    my $content = encode_utf8($body);
    open my $NEWJS, '>', "$ROOT/static/f/js/$l.js" or die $!;
    print $NEWJS $JavaScript::Minifier::XS::VERSION ? JavaScript::Minifier::XS::minify($content) : $content;
    close $NEWJS;
  }
}

l10n_load;
jsgen;

#!/usr/bin/perl

package VNDB;

use strict;
use warnings;
use Encode 'encode_utf8';
use Cwd 'abs_path';
use JSON::XS;

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


# Remove formatting codes from L10N strings that the Javascript mt() does not support.
#   [quant,_n,x,..] -> x
#   [index,_n,x,..] -> x
# [_n] is supported by Javascript mt(). It is left alone if no arguments are
# given, otherwise it is replaced. All other codes result in an error.
sub l10nstr {
  my($lang, $key, @args) = @_;
  local $_ = $lang{$lang}{$key} || $lang{'en'}{$key} || '';

  # Simplify parsing
  s/~\[/JSGEN_QBEGIN/g;
  s/~]/JSGEN_QENDBR/g;
  s/~,/JSGEN_QCOMMA/g;

  # Replace quant/index
  s/\[(?:quant|index),_[0-9]+,([^,\]]*)[^\]]*\]/$1/g;

  # Replace [_n]
  for my $i (0..$#args) {
    my $v = $i+1;
    s/\[_$v\]/$args[$i]/g;
  }

  # Check for unhandled codes
  die "Unsupported formatting code in $lang:$key\n" if /\[[^_]/;

  # Convert back
  s/JSGEN_QBEGIN/~[/g;
  s/JSGEN_QENDBR/~]/g;
  s/JSGEN_QCOMMA/,/g; # No need to escape, at this point there are no codes with arguments
  $_;
}


sub l10n {
  my($lang, $js) = @_;

  # parse the .js code and replace mt()'s that can be modified in-place, otherwise add to the @keys
  my @keys;
  $js =~ s{(?:mt\('([a-z0-9_]+)'([,\)])|l10n /([^/]+)/)}#
    my($k, $s, $q) = ($1, $2, $3);
    my $v = $k && l10nstr($lang, $k);
    if($q) {
      $q ne '<perl regex>' && push @keys, qr/$q/; ''
    } elsif($s eq ')' && $v && $v !~ /[\~\[\]]/) {
      $v =~ s/"/\\"/g;
      $v =~ s/\n/\\n/g;
      qq{"$v"}
    } else {
      push @keys, '^'.quotemeta($k).'$';
      "mt('$k'$s"
    }
  #eg;

  my %keys;
  for my $key (sort keys %{$lang{$lang}}) {
    next if !grep $key =~ /$_/, @keys;
    $keys{$key} = l10nstr($lang, $key);
  }
  (\%keys, $js);
}


# screen resolution information, suitable for usage in filFSelect()
sub resolutions {
  my $cat = '';
  my @r;
  my $push = \@r;
  for my $i (0..$#{$S{resolutions}}) {
    my $r = $S{resolutions}[$i];
    if($cat ne $r->[1]) {
      push @r, [$r->[1]];
      $cat = $r->[1];
      $push = $r[$#r];
    }
    push @$push, [$i, $r->[0]];
  }
  \@r
}


sub vars {
  my($lang, $l10n) = @_;
  my %vars = (
    rlist_status  => $S{rlist_status},
    cookie_prefix => $O{cookie_prefix},
    age_ratings   => [ map [ $_, l10nstr($lang, $_ == -1 ? ('_unknown') : $_ == 0 ? ('_minage_all') : ('_minage_age', $_)) ], @{$S{age_ratings}} ],
    languages     => [ map [ $_, $S{languages}{$_} ], keys %{$S{languages}} ],
    platforms     => [ map [ $_, $S{platforms}{$_} ], keys %{$S{platforms}} ],
    char_roles    => [ map [ $_, $S{char_roles}{$_} ], keys %{$S{char_roles}} ],
    media         => [ map [ $_, $S{media}{$_}[1], $S{media}{$_}[0] ], keys %{$S{media}} ],
    release_types => [ map [ $_, ucfirst $_ ], @{$S{release_types}} ],
    animated      => [ map [ $_, $S{animated}[$_] ], 0..$#{$S{animated}} ],
    voiced        => [ map [ $_, $S{voiced}[$_] ], 0..$#{$S{voiced}} ],
    vn_lengths    => [ map [ $_, $S{vn_lengths}[$_][0] ], 0..$#{$S{vn_lengths}} ],
    blood_types   => [ map [ $_, $S{blood_types}{$_} ], keys %{$S{blood_types}} ],
    genders       => [ map [ $_, $S{genders}{$_} ], keys %{$S{genders}} ],
    staff_roles   => [ map [ $_, $S{staff_roles}{$_} ], keys %{$S{staff_roles}} ],
    resolutions   => scalar resolutions(),
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


sub save {
  my($f, $body) = @_;
  my $content = encode_utf8($body);

  unlink "$f~";
  if(!$VNDB::JSGEN{compress}) {
    open my $F, '>', "$f~" or die $!;
    print $F $content;
    close $F;

  } elsif($VNDB::JSGEN{compress} eq 'JavaScript::Minifier::XS') {
    require JavaScript::Minifier::XS;
    open my $F, '>', "$f~" or die $!;
    print $F JavaScript::Minifier::XS::minify($content);
    close $F;

  } elsif($VNDB::JSGEN{compress} =~ /^\|/) { # External command
    (my $cmd = $VNDB::JSGEN{compress}) =~ s/^\|//;
    open my $C, '|-', "$cmd >'$f~'" or die $!;
    print $C $content;
    close $C or die $!;

  } else {
    die "Unrecognized compression option: '$VNDB::JSGEN{compress}'\n";
  }

  rename "$f~", $f or die $!;

  if($VNDB::JSGEN{gzip}) {
    `$VNDB::JSGEN{gzip} -c '$f' >'$f.gz~'`;
    rename "$f.gz~", "$f.gz";
  }
}

sub jsgen {
  my $js = readjs 'main.js';

  for my $l (VNDB::L10N::languages()) {
    my($l10n, $body) = l10n($l, $js);
    $body =~ s{/\*VARS\*/}{vars($l, $l10n)}eg;
    save "$ROOT/static/f/js/$l.js", $body;
  }
}

l10n_load;
jsgen;

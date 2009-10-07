#!/usr/bin/perl

use strict;
use warnings;
use Encode 'encode_utf8';
use Cwd 'abs_path';
eval { require JavaScript::Minifier::XS; };

our($ROOT, %O);
BEGIN { ($ROOT = abs_path $0) =~ s{/util/jsgen\.pl$}{}; }

use lib "$ROOT/lib";
use lib "$ROOT/yawf/lib";
use LangFile;

# The VNDB::L10N module is not really suited to be used outside the VNDB::*
# framework, but it's the central location that defines which languages we have
# and in what order to display them.
use VNDB::L10N;


my $jskeys = qr{^_menu_emptysearch$};


sub l10n {
  # Using JSON::XS or something may be shorter and less error prone,
  #  although I would have less power over the output (mostly the quoting of the keys)

  my $lang = LangFile->new(read => "$ROOT/data/lang.txt");
  my @r;
  push @r, 'L10N_STR = {';
  my $cur; # undef = none/excluded, 1 = awaiting first TL line, 2 = after first TL line
  my %lang;
  while((my $l = $lang->read())) {
    my $type = shift @$l;
    if($type eq 'key') {
      my $key = shift @$l;
      push @r, '  }' if $cur;
      $cur = $key =~ $jskeys ? 1 : undef;
      if($cur) {
        $r[$#r] .= ',' if $r[$#r] =~ /}$/;
        # let's assume key names don't trigger a reserved word in JS
        $key = qq{"$key"} if $key !~ /^[a-z_][a-z0-9_]*$/i;
        push @r, qq|  $key: {|;
      }
    }
    $lang{$l->[0]} = 1 if $type eq 'tl';
    if($type eq 'tl' && $cur) {
      my($lang, $sync, $val) = @$l;
      $val =~ s/"/\\"/g;
      $val =~ s/\n/\\n/g;
      $r[$#r] .= ',' if $cur == 2;
      $lang = q{"$l->[0]"} if $lang =~ /^(?:as|do|if|in|is)$/; # reserved two-char words
      push @r, qq|    $lang: "$val"|;
      $cur = 2;
    }
  }
  push @r, '  }' if $cur;
  push @r, '};';
  push @r, 'L10N_LANG = [ '.join(', ', map qq{"$_"}, VNDB::L10N::languages()).' ];';
  return join "\n", @r;
}


sub jsgen {
  # JavaScript::Minifier::XS doesn't correctly handle perl's unicode,
  #  so just do everything in raw bytes instead.
  my $js = encode_utf8(l10n()) . "\n\n";
  open my $JS, '<', "$ROOT/data/script.js" or die $!;
  $js .= join '', <$JS>;
  close $JS;
  open my $NEWJS, '>', "$ROOT/static/f/script.js" or die $!;
  print $NEWJS $JavaScript::Minifier::XS::VERSION ? JavaScript::Minifier::XS::minify($js) : $js;
  close $NEWJS;
}

jsgen;


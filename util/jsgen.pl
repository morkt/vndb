#!/usr/bin/perl

use strict;
use warnings;
use Cwd 'abs_path';
eval { require JavaScript::Minifier::XS; };

our($ROOT, %O);
BEGIN { ($ROOT = abs_path $0) =~ s{/util/jsgen\.pl$}{}; }


sub jsgen {
  # JavaScript::Minifier::XS doesn't correctly handle perl's unicode,
  #  so just do everything in raw bytes instead.
  open my $JS, '<', "$ROOT/data/script.js" or die $!;
  my $js = join '', <$JS>;
  close $JS;
  open my $NEWJS, '>', "$ROOT/static/f/script.js" or die $!;
  print $NEWJS $JavaScript::Minifier::XS::VERSION ? JavaScript::Minifier::XS::minify($js) : $js;
  close $NEWJS;
}

jsgen;


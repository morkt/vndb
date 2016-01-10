#!/usr/bin/perl


package VNDB;

use strict;
use warnings;
use Cwd 'abs_path';
use Image::Magick;
eval { require CSS::Minifier::XS };

our($ROOT, %S);
BEGIN { ($ROOT = abs_path $0) =~ s{/util/skingen\.pl$}{}; }

use lib "$ROOT/lib";
use SkinFile;

require $ROOT.'/data/global.pl';


my $iconcss = do {
  open my $F, '<', "$ROOT/data/icons/icons.css" or die $!;
  local $/=undef;
  <$F>;
};


sub writeskin { # $name
  my $name = shift;
  my $skin = SkinFile->new("$ROOT/static/s", $name);
  my %o = map +($_ => $skin->get($_)), $skin->get;
  $o{iconcss} = $iconcss;

  # get the right top image
  if($o{imgrighttop}) {
    my $path = "/s/$name/$o{imgrighttop}";
    my $img = Image::Magick->new;
    $img->Read("$ROOT/static$path");
    $o{_bgright} = sprintf 'background: url(%s?%s) no-repeat; width: %dpx; height: %dpx',
      $path, $S{version}, $img->Get('width'), $img->Get('height');
  } else {
    $o{_bgright} = 'display: none';
  }

  # body background
  if($o{imglefttop}) {
    $o{_bodybg} = sprintf 'background: %s url(/s/%s/%s?%s) no-repeat', $o{bodybg}, $name, $o{imglefttop}, $S{version};
  } else {
    $o{_bodybg} = sprintf 'background-color: %s', $o{bodybg};
  }

  # main title
  $o{_maintitle} = $o{maintitle} ? "color: ".$o{maintitle} : 'display: none';

  # create boxbg.png
  my $img = Image::Magick->new(size => '1x1');
  $img->Read("xc:$o{boxbg}");
  $img->Write(filename => "$ROOT/static/s/$name/boxbg.png");
  $o{_boxbg} = "/s/$name/boxbg.png?$S{version}";

  # get the blend color
  $img = Image::Magick->new(size => '1x1');
  $img->Read("xc:$o{bodybg}", "xc:$o{boxbg}");
  $img = $img->Flatten();
  $o{_blendbg} = '#'.join '', map sprintf('%02x', $_*255), $img->GetPixel(x=>1,y=>1);

  # version
  $o{version} = $S{version};

  # write the CSS
  open my $CSS, '<', "$ROOT/data/style.css" or die $!;
  my $css = join '', <$CSS>;
  close $CSS;
  $css =~ s/\$$_\$/$o{$_}/g for (keys %o);

  my $f = "$ROOT/static/s/$name/style.css";
  open my $SKIN, '>', "$f~" or die $!;
  print $SKIN $CSS::Minifier::XS::VERSION ? CSS::Minifier::XS::minify($css) : $css;
  close $SKIN;

  rename "$f~", $f;

  if($VNDB::SKINGEN{gzip}) {
    `$VNDB::SKINGEN{gzip} -c '$f' >'$f.gz~'`;
    rename "$f.gz~", "$f.gz";
  }
}


if(@ARGV) {
  writeskin($_) for (@ARGV);
} else {
  writeskin($_) for (SkinFile->new("$ROOT/static/s")->list);
}



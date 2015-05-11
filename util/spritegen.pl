#!/usr/bin/perl

use strict;
use warnings;
use Image::Magick;
use Cwd 'abs_path';

our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/spritegen\.pl$}{}; }

my $path = "$ROOT/data/icons";
my $icons = "$ROOT/static/f/icons.png";
my $css = "$ROOT/data/icons/icons.css";

my @img = map {
  my $i = Image::Magick->new();
  $i->Read($_) and die $_;
  {
    f => /^\Q$path\E\/(.+)\.png/ && $1,
    i => $i,
    h => scalar $i->Get('height'),
    w => scalar $i->Get('width')
  }
} glob("$path/*.png"), glob("$path/*/*.png");


@img = sort { $b->{h} <=> $a->{h} || $b->{w} <=> $a->{w} } @img;

my $minpixels = 0;
$minpixels += $_->{w}*$_->{h} for @img;


# Simple strip packing algortihm, First-Fit Decreasing Height.
sub genstrip {
  my $w = shift;
  my @l;
  my $h = 0;
  for my $i (@img) {
    my $found = 0;
    # @img is assumed to be sorted by height, so image always fits
    # (height-wise) in any of the previously created levels.
    for my $l (@l) {
      next if $l->{left} + $i->{w} > $w;
      # Image fits, add to level
      $i->{x} = $l->{left};
      $i->{y} = $l->{top};
      $l->{left} += $i->{w};
      $found = 1;
      last;
    }
    next if $found;

    # No level found, create a new one
    push @l, { top => $h, left => $i->{w} };
    $i->{x} = 0;
    $i->{y} = $h;
    $h += $i->{h};
  }
  return $h;
}


# Tries to find the width of the strip for which the number of unused pixels is
# the minimum. Simple and dumb linear search; it's fast enough.
#
# Note that minimum number of unused pixels does not imply minimum file size,
# although there is some correlation. To further minimize the file size, it's
# possible to attempt to group similar-looking images close together so that
# the final png image might compress better. Finding a good (and fast)
# algorithm for this is not a trivial task, however.
sub minstrip {
  my($minwidth, $maxwidth) = (0,0);
  for(@img) {
    $minwidth = $_->{w} if $_->{w} > $minwidth;
    $maxwidth += $_->{w};
  }
  my $optw;
  my $optsize = 1e10;
  for my $w ($minwidth..$maxwidth) {
    my $size = genstrip($w)*$w;
    # To optimize for file size, uncommment below line. It's slow, but saves about 150 bytes (while using pngcrush).
    #$size = img();
    if($size < $optsize) {
      $optw = $w;
      $optsize = $size;
    }
  }
  genstrip($optw);
}


sub calcdim {
  my($w, $h) = (0,0);
  for (@img) {
    $w = $_->{x}+$_->{w} if $w < $_->{x}+$_->{w};
    $h = $_->{y}+$_->{h} if $h < $_->{y}+$_->{h};
  }
  ($w, $h)
}


sub img {
  my($w, $h) = calcdim;
  my $img = Image::Magick->new;
  print $img->Set(size => "${w}x$h");
  print $img->ReadImage('canvas:rgba(0,0,0,0)');
  my $pixels = $w*$h;
  for my $i (@img) {
    print $img->Composite(image => $i->{i}, x => $i->{x}, y => $i->{y});
  }
  print $img->Write($icons);
  undef $img;

  `pngcrush -q "$icons" "$icons~" 2>/dev/null && mv "$icons~" "$icons"`;

  my $size = -s $icons;
  #printf "Dim: %dx%d, size: %d, pixels wasted: %d\n", $w, $h, $size, $w*$h-$minpixels;
  $size;
}


sub css {
  # The gender icons need special treatment, they're 3 icons in one image.
  my $gender;

  open my $F, '>', $css or die $!;
  for my $i (@img) {
    if($i->{f} eq 'gender') {
      $gender = $i;
      next;
    }
    $i->{f} =~ /([^\/]+)$/;
    printf $F ".icons.%s { background-position: %dpx %dpx }\n", $1, -$i->{x}, -$i->{y};
  }
  printf $F ".icons.gen.f, .icons.gen.b { background-position: %dpx %dpx }\n", -$gender->{x}, -$gender->{y};
  printf $F ".icons.gen.m { background-position: %dpx %dpx }\n", -($gender->{x}+14), -$gender->{y};
}


#genstrip 80;
minstrip;
img;
css;

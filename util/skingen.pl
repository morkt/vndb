#!/usr/bin/perl

package VNDB;

use strict;
use warnings;
use Cwd 'abs_path';
use Data::Dumper 'Dumper';
use Image::Magick;


our($ROOT, %O);
BEGIN { ($ROOT = abs_path $0) =~ s{/util/skingen\.pl$}{}; }
require $ROOT.'/data/global.pl';


if(@ARGV) {
  writeskin(readskin($_)) for (@ARGV);
} else {
  /([^\/]+)$/ && writeskin(readskin($1)) for (glob($ROOT.'/static/s/*'));
}


sub readskin { # skin name
  my $name = shift;
  my %o;
  open my $F, '<', $ROOT.'/static/s/'.$name.'/conf' or die $!;
  while(<$F>) {
    chomp;
    s/\r//g;
    s{[\t\s]*//.+$}{};
    next if !/^([a-z0-9]+)[\t\s]+(.+)$/;
    $o{$1} = $2;
  }
  close $F;
  $o{_name} = $name;
  return \%o;
}


sub writeskin { # $obj
  my $o = shift;

  # fix image locations
  $o->{$_} && ($o->{$_} = '/s/'.$o->{_name}.'/'.$o->{$_}) for (qw|imglefttop imgrighttop|);

  # get the right top image
  if($o->{imgrighttop}) {
    my $img = Image::Magick->new;
    $img->Read($ROOT.'/static'.$o->{imgrighttop});
    $o->{_bgright} = sprintf 'background: url(%s) no-repeat; width: %dpx; height: %dpx',
      $o->{imgrighttop}, $img->Get('width'), $img->Get('height');
  } else {
    $o->{_bgright} = 'display: none';
  }

  # body background
  if(!$o->{imglefttop}) {
    $o->{_bodybg} = "background-color: $o->{bodybg}";
  } else {
    $o->{_bodybg} = "background: $o->{bodybg} url($o->{imglefttop}) no-repeat";
  }

  # main title
  $o->{_maintitle} = $o->{maintitle} ? "color: $o->{maintitle}" : 'display: none';

  # create boxbg.png
  my $img = Image::Magick->new(size => '1x1');
  $img->Read('xc:'.$o->{boxbg});
  $img->Write(filename => $ROOT.'/static/s/'.$o->{_name}.'/boxbg.png');
  $o->{_boxbg} = '/s/'.$o->{_name}.'/boxbg.png';

  # get the blend color
  $img = Image::Magick->new(size => '1x1');
  $img->Read('xc:'.$o->{bodybg}, 'xc:'.$o->{boxbg});
  $img = $img->Flatten();
  $o->{_blendbg} = '#'.join '', map sprintf('%02x', $_*255), $img->GetPixel(x=>1,y=>1);

  # write the CSS
  open my $CSS, '<', "$ROOT/data/style.css" or die $!;
  open my $SKIN, '>', "$ROOT/static/s/$o->{_name}/style.css" or die $!;
  while((my $d = <$CSS>)) {
    if($O{debug}) {
      chomp $d;
      $d =~ s/^\s*/ /;
      $d =~ s{/\*.+\*/}{}; # NOTE: multiline comments or multiple comments per line won't work
      next if $d !~ /[^\s\t]/;
    }
    $d =~ s/\$$_\$/$o->{$_}/g for (keys %$o);
    print $SKIN $d;
  }
  close $SKIN;
  close $CSS;
}



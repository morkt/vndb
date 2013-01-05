
#
#  Multi::Image  -  Image compressing and resizing
#

package Multi::Image;

use strict;
use warnings;
use POE;
use Image::Magick;
use Time::HiRes 'time';
use VNDBUtil 'imgsize';


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start
        _start shutdown scr_check scr_process
      |],
    ],
    heap => {
      sfpath  => $VNDB::ROOT.'/static/sf',
      stpath  => $VNDB::ROOT.'/static/st',
      check_delay => 3600,
      @_,
    },
  );
}


sub _start {
  $_[KERNEL]->alias_set('image');
  $_[KERNEL]->sig(shutdown => 'shutdown');
  $_[KERNEL]->post(pg => listen => screenshot => 'scr_check');
  $_[KERNEL]->yield('scr_check');
}


sub shutdown {
  $_[KERNEL]->post(pg => unlisten => 'charimage', 'screenshot');
  $_[KERNEL]->delay('scr_check');
  $_[KERNEL]->alias_remove('image');
}


sub scr_check {
  $_[KERNEL]->delay('scr_check');
  $_[KERNEL]->post(pg => query => 'SELECT id FROM screenshots WHERE processed = false LIMIT 1', undef, 'scr_process');
}


sub scr_process { # num, res
  return $_[KERNEL]->delay(scr_check => $_[HEAP]{check_delay}) if $_[ARG0] == 0;

  my $id = $_[ARG1][0]{id};
  my $start = time;
  my $sf = sprintf '%s/%02d/%d.jpg', $_[HEAP]{sfpath}, $id%100, $id;
  my $st = sprintf '%s/%02d/%d.jpg', $_[HEAP]{stpath}, $id%100, $id;
  my $os = -s $sf;

  # convert/compress full-size image
  my $im = Image::Magick->new;
  $im->Read($sf);
  $im->Set(magick => 'JPEG');
  $im->Set(quality => 90);
  $im->Write($sf);

  # create thumbnail
  my($ow, $oh) = ($im->Get('width'), $im->Get('height'));
  my($nw, $nh) = imgsize($ow, $oh, @{$VNDB::S{scr_size}});
  $im->Thumbnail(width => $nw, height => $nh);
  $im->Set(quality => 90);
  $im->Write($st);

  $_[KERNEL]->post(pg => do =>
    'UPDATE screenshots SET processed = true, width = ?, height = ? WHERE id = ?',
    [ $ow, $oh, $id ]
  );
  $_[KERNEL]->call(core => log =>
    'Processed screenshot #%d in %.2fs: %.1fkB -> %.1fkB (%dx%d), thumb: %.1fkB (%dx%d)',
    $id, time-$start, $os/1024, (-s $sf)/1024, $ow, $oh, (-s $st)/1024, $nw, $nh
  );

  $_[KERNEL]->yield('scr_check');
}


1;


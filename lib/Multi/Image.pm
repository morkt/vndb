
#
#  Multi::Image  -  Image compressing and resizing
#

package Multi::Image;

use strict;
use warnings;
use POE;
use Image::Magick;
use Time::HiRes 'time';


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start
        _start shutdown cv_check cv_process scr_check scr_process
      |],
    ],
    heap => {
      cvpath  => $VNDB::ROOT.'/static/cv',
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
  $_[KERNEL]->post(pg => listen => coverimage => 'cv_check', screenshot => 'scr_check');
  $_[KERNEL]->yield('cv_check');
  $_[KERNEL]->yield('scr_check');
}


sub shutdown {
  $_[KERNEL]->post(pg => unlisten => 'coverimage', 'screenshot');
  $_[KERNEL]->delay('cv_check');
  $_[KERNEL]->delay('scr_check');
  $_[KERNEL]->alias_remove('image');
}


sub cv_check {
  $_[KERNEL]->delay('cv_check');
  $_[KERNEL]->post(pg => query => 'SELECT image FROM vn_rev WHERE image < 0 LIMIT 1', undef, 'cv_process');
}


sub cv_process { # num, res
  return $_[KERNEL]->delay(cv_check => $_[HEAP]{check_delay}) if $_[ARG0] == 0;

  my $id = -1*$_[ARG1][0]{image};
  my $start = time;
  my $img = sprintf '%s/%02d/%d.jpg', $_[HEAP]{cvpath}, $id%100, $id;
  my $os = -s $img;

  my $im = Image::Magick->new;
  $im->Read($img);
  $im->Set(magick => 'JPEG');
  my($old, $new) = do_resize($im, $VNDB::S{cv_size});
  $im->Set(quality => 80);
  $im->Write($img);

  $_[KERNEL]->post(pg => do => 'UPDATE vn_rev SET image = image*-1 WHERE image = ?', [ -1*$id ]);
  $_[KERNEL]->call(core => log => 'Processed cover image %d in %.2fs: %.2fkB (%dx%d) -> %.2fkB (%dx%d)',
    $id, time-$start, $os/1024, $$old[0], $$old[1], (-s $img)/1024, $$new[0], $$new[1]);

  $_[KERNEL]->yield('cv_check');
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
  my($old, $new) = do_resize($im, $VNDB::S{scr_size});
  $im->Set(quality => 90);
  $im->Write($st);

  $_[KERNEL]->post(pg => do =>
    'UPDATE screenshots SET processed = true, width = ?, height = ? WHERE id = ?',
    [ $$old[0], $$old[1], $id ]
  );
  $_[KERNEL]->call(core => log =>
    'Processed screenshot #%d in %.2fs: %.1fkB -> %.1fkB (%dx%d), thumb: %.1fkB (%dx%d)',
    $id, time-$start, $os/1024, (-s $sf)/1024, $$old[0], $$old[1], (-s $st)/1024, $$new[0], $$new[1]
  );

  $_[KERNEL]->yield('scr_check');
}




# non-POE helper function
sub do_resize { # im, [ maxwidth, maxheight ]
  my($im, $dim) = @_;

  my($w, $h) = ($im->Get('width'), $im->Get('height'));
  $dim = [ $w, $h ] if !$dim;
  my($ow, $oh) = ($w, $h);
  if($w > $$dim[0] || $h > $$dim[1]) {
    if($w/$h > $$dim[0]/$$dim[1]) { # width is the limiting factor
      $h *= $$dim[0]/$w;
      $w = $$dim[0];
    } else {
      $w *= $$dim[1]/$h;
      $h = $$dim[1];
    }
  }
  $im->Thumbnail(width => $w, height => $h);

  return ([$ow, $oh], [$w, $h]);
}


1;


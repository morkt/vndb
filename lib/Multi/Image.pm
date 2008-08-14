
#
#  Multi::Image  -  Image compressing and resizing
#

package Multi::Image;

use strict;
use warnings;
use POE;
use Image::Magick;
use Image::MetaData::JPEG;
use Time::HiRes 'time';


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start
        cmd_coverimage cv_process cv_update cv_finish
        cmd_screenshot scr_process scr_clean scr_finish
      |],
    ],
    heap => {
      cvsize  => [ 256, 400 ],
      scrsize => [ 136, 102 ],
    },
  );
}


sub _start {
  $_[KERNEL]->alias_set('image');
  $_[KERNEL]->sig(shutdown => 'shutdown');
  $_[KERNEL]->call(core => register => qr/^coverimage(?: ([0-9]+)|)$/, 'cmd_coverimage');
  $_[KERNEL]->call(core => register => qr/^screenshot ([0-9]+|all|clean)$/, 'cmd_screenshot');

 # daily check for unprocessed cover images
  $_[KERNEL]->post(core => addcron => '0 0 * * *', 'coverimage');
}


sub cmd_coverimage {
  $_[HEAP]{curcmd} = $_[ARG0];

  if($_[ARG1]) {
    $_[HEAP]{todo} = [ $_[ARG1] ];
  } else {
    my $q = $Multi::SQL->prepare('SELECT image FROM vn_rev WHERE image < 0');
    $q->execute();
    $_[HEAP]{todo} = [ map { -1*$_->[0]} @{$q->fetchall_arrayref([])} ];
    if(!@{$_[HEAP]{todo}}) {
      $_[KERNEL]->call(core => log => 2, 'No images to process');
      $_[KERNEL]->yield('cv_finish');
      return;
    }
  }
  $_[KERNEL]->yield(cv_process => $_[HEAP]{todo}[0]);
}


sub cv_process { # id
  my $start = time;

  my $img = sprintf '%s/%02d/%d.jpg', $VNDB::VNDBopts{imgpath}, $_[ARG0]%100, $_[ARG0];

  my $os = -s $img;
  my $im = Image::Magick->new;
  $im->Read($img);
  $im->Set(magick => 'JPEG');
  my($w, $h) = ($im->Get('width'), $im->Get('height'));
  my($ow, $oh) = ($w, $h);
  if($w > $_[HEAP]{cvsize}[0] || $h > $_[HEAP]{cvsize}[1]) {
    if($w/$h > $_[HEAP]{cvsize}[0]/$_[HEAP]{cvsize}[1]) { # width is the limiting factor
      $h *= $_[HEAP]{cvsize}[0]/$w;
      $w = $_[HEAP]{cvsize}[0];
    } else {
      $w *= $_[HEAP]{cvsize}[1]/$h;
      $h = $_[HEAP]{cvsize}[1];
    }
    $im->Thumbnail(width => $w, height => $h);
  } 
  $im->Set(quality => 80);
  $im->Write($img);
  undef $im;

  my $md = Image::MetaData::JPEG->new($img);
  $md->drop_segments('METADATA');
  $md->save($img);

  $_[KERNEL]->call(core => log => 2, 'Processed cover image %d in %.2fs: %.2fkB (%dx%d) -> %.2fkB (%dx%d)',
    $_[ARG0], time-$start, $os/1024, $ow, $oh, (-s $img)/1024, $w, $h);
  $_[KERNEL]->yield(cv_update => $_[ARG0]);
}


sub cv_update { # id
  if($Multi::SQL->do('UPDATE vn_rev SET image = ? WHERE image = ?', undef, $_[ARG0], -1*$_[ARG0])) {
    $_[KERNEL]->yield(cv_finish => $_[ARG0]);
  } elsif(!$_[ARG0]) {
    $_[KERNEL]->delay(cv_update => 5 => $_[ARG0]);
  } else {
    $_[KERNEL]->call(core => log => 1, 'Image %d not present in the database!', $_[ARG0]);
    $_[KERNEL]->yield(cv_finish => $_[ARG0]);
  }
}


sub cv_finish { # [id]
  if($_[ARG0]) {
    $_[HEAP]{todo} = [ grep $_[ARG0]!=$_, @{$_[HEAP]{todo}} ];
    return $_[KERNEL]->yield(cv_process => $_[HEAP]{todo}[0])
      if @{$_[HEAP]{todo}};
  }

  $_[KERNEL]->post(core => finish => $_[HEAP]{curcmd});
  delete @{$_[HEAP]}{qw| curcmd todo |};
}




sub cmd_screenshot {
  my($cmd, $id) = @_[ARG0, ARG1];
  $_[HEAP]{curcmd} = $_[ARG0];
  $_[HEAP]{id} = $_[ARG1];

  if($id eq 'clean') {
    return $_[KERNEL]->yield('scr_clean');
  } elsif($id eq 'all') {
    my $q = $Multi::SQL->prepare('SELECT DISTINCT scr FROM vn_screenshots');
    $q->execute();
    $_[HEAP]{todo} = [ map $_->[0], @{$q->fetchall_arrayref([])} ];
  } else {
    $_[HEAP]{todo} = [ $_[ARG1] ];
  }

  $_[KERNEL]->yield(scr_process => $_[HEAP]{todo}[0]);
}


sub scr_process { # id
  my $start = time;

  my $sf  = sprintf '%s/%02d/%d.jpg', $VNDB::VNDBopts{sfpath}, $_[ARG0]%100, $_[ARG0];
  my $st  = sprintf '%s/%02d/%d.jpg', $VNDB::VNDBopts{stpath}, $_[ARG0]%100, $_[ARG0];

 # convert/compress full-size image
  my $os = -s $sf;
  my $im = Image::Magick->new;
  $im->Read($sf);
  $im->Set(magick => 'JPEG');
  $im->Set(quality => 80);
  $im->Write($sf);

 # create thumbnail
  my($w, $h) = ($im->Get('width'), $im->Get('height'));
  my($ow, $oh) = ($w, $h);
  if($w/$h > $_[HEAP]{scrsize}[0]/$_[HEAP]{scrsize}[1]) { # width is the limiting factor
    $h *= $_[HEAP]{scrsize}[0]/$w;
    $w = $_[HEAP]{scrsize}[0];
  } else {
    $w *= $_[HEAP]{scrsize}[1]/$h;
    $h = $_[HEAP]{scrsize}[1];
  }
  $im->Thumbnail(width => $w, height => $h);
  $im->Set(quality => 90);
  $im->Write($st);
  undef $im;

 # remove metadata in both files
  my $md = Image::MetaData::JPEG->new($sf);
  $md->drop_segments('METADATA');
  $md->save($sf);
  $md = Image::MetaData::JPEG->new($st);
  $md->drop_segments('METADATA');
  $md->save($st);
  undef $md;

  $_[KERNEL]->call(core => log => 2, 'Processed screenshot #%d in %.2fs: %.1fkB -> %.1fkB (%dx%d), thumb: %.1fkB (%dx%d)',
    $_[ARG0], time-$start, $os/1024, (-s $sf)/1024, $ow, $oh, (-s $st)/1024, $w, $h);
  $_[KERNEL]->yield(scr_finish => $_[ARG0]);
}


sub scr_clean {
 # not very efficient...
  my $q = $Multi::SQL->prepare('SELECT DISTINCT scr FROM vn_screenshots');
  $q->execute();
  my @exists = map $_->[0], @{$q->fetchall_arrayref([])};

 # not very efficient either...
  my @files = map /\/([0-9]+)\.jpg$/?$1:(), glob "$VNDB::VNDBopts{sfpath}/*/*.jpg";

  my($files, $thumbs, $bytes) = (0,0,0);
  for my $id (@files) {
    if(!grep $_==$id, @exists) {
      my $f = sprintf '%s/%02d/%d.jpg', $VNDB::VNDBopts{stpath}, $id%100, $id;
      my $t = sprintf '%s/%02d/%d.jpg', $VNDB::VNDBopts{stpath}, $id%100, $id;
      $bytes += -s $f;
      $files++;
      unlink $f;
      if(-f $t) {
        $bytes += -s $t;
        $thumbs++;
        unlink $t;
      }
      $_[KERNEL]->call(core => log => 3, 'Removing screenshot #%d', $id);
    }
  }

  $_[KERNEL]->call(core => log => 2, 'Removed %d + %d unused files, total of %.2fMB freed.',
    $files, $thumbs, $bytes/1024/1024) if $files;
  $_[KERNEL]->call(core => log => 2, 'No unused screenshots found') if !$files;
  $_[KERNEL]->yield('scr_finish');
}


sub scr_finish { # [id]
  if($_[ARG0]) {
    $_[HEAP]{todo} = [ grep $_!=$_[ARG0], @{$_[HEAP]{todo}} ];
    return $_[KERNEL]->yield(scr_process => $_[HEAP]{todo}[0])
      if @{$_[HEAP]{todo}};
  }

  $_[KERNEL]->post(core => finish => $_[HEAP]{curcmd});
  delete @{$_[HEAP]}{qw| curcmd todo |};
}



1;


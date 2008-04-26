
#
#  Multi::Image  -  Image compressing and resizing
#

package Multi::Image;

use strict;
use warnings;
use POE;
use Image::Magick;
use Image::MetaData::JPEG;


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start cmd_coverimage format compress update finish |],
    ],
    heap => {
      imgpath => '/www/vndb/static/cv'
    },
  );
}


sub _start {
  $_[KERNEL]->alias_set('image');
  $_[KERNEL]->sig(shutdown => 'shutdown');
  $_[KERNEL]->call(core => register => qr/^coverimage(?: ([0-9]+)|)$/, 'cmd_coverimage');

 # check for unprocessed cover images every day on 0:00 and 12:00 local time
  $_[KERNEL]->post(core => addcron => '0 0,12 * * *', 'coverimage');
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
      $_[KERNEL]->yield('finish');
      return;
    }
  }
  $_[KERNEL]->yield(format => $_[HEAP]{todo}[0]);
}


sub format { # imgid
  $_[HEAP]{imgid} = $_[ARG0];
  $_[HEAP]{img} = sprintf '%s/%02d/%d.jpg', $_[HEAP]{imgpath}, $_[ARG0]%100, $_[ARG0];
  $_[KERNEL]->call(core => log => 3, 'Processing image %d', $_[HEAP]{imgid});

  $_[HEAP]{im} = Image::Magick->new;
  $_[HEAP]{im}->Read($_[HEAP]{img});
  $_[HEAP]{im}->Set(magick => 'JPEG');
  my($w, $h) = ($_[HEAP]{im}->Get('width'), $_[HEAP]{im}->Get('height'));
  if($w > 256 || $h > 400) {
    $_[KERNEL]->call(core => log => 3, 'Image too large (%dx%d), resizing', $w, $h);
    if($w/$h > 256/400) { # width is the limiting factor
      $h *= 256/$w;
      $w = 256;
    } else {
      $w *= 400/$h;
      $h = 400;
    }
    $_[HEAP]{im}->Thumbnail(width => $w, height => $h);
  } 

  $_[KERNEL]->yield('compress');
}


sub compress {
  $_[HEAP]{im}->Set(quality => 80);
  $_[HEAP]{im}->Write($_[HEAP]{img});
  undef $_[HEAP]{im};

  $_[HEAP]{md} = Image::MetaData::JPEG->new($_[HEAP]{img});
  $_[HEAP]{md}->drop_segments('METADATA');
  $_[HEAP]{md}->save($_[HEAP]{img});
  undef $_[HEAP]{md};

  $_[KERNEL]->call(core => log => 3, 'Compressed image %d to %.2fkB', $_[HEAP]{imgid}, (-s $_[HEAP]{img})/1024);
  $_[KERNEL]->yield('update');
}


sub update {
  $Multi::SQL->do('UPDATE vn_rev SET image = ? WHERE image = ?', undef, $_[HEAP]{imgid}, -1*$_[HEAP]{imgid});

  $_[KERNEL]->yield('finish');
}


sub finish {
  if($_[HEAP]{imgid}) {
    $_[HEAP]{todo} = [ grep { $_[HEAP]{imgid} != $_ } @{$_[HEAP]{todo}} ];
    if(@{$_[HEAP]{todo}}) {
      $_[KERNEL]->yield(format => $_[HEAP]{todo}[0]);
      return;
    }
  }

  $_[KERNEL]->post(core => finish => $_[HEAP]{curcmd});
  delete @{$_[HEAP]}{qw| curcmd imgid img im md todo |};
}


1;


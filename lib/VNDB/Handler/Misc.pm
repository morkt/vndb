
package VNDB::Handler::Misc;


use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{},                              \&homepage,
  qr{(?:([upvr])([1-9]\d*)/)?hist},  \&history,
  qr{d([1-9]\d*)},                   \&docpage,
  qr{nospam},                        \&nospam,
  qr{([vrp])([1-9]\d*)/(lock|hide)}, \&itemmod,
  qr{we-dont-like-ie6},              \&ie6message,

  # redirects for old URLs
  qr{(.*[^/]+)/+}, sub { $_[0]->resRedirect("/$_[1]", 'perm') },
  qr{([pv])},      sub { $_[0]->resRedirect("/$_[1]/all", 'perm') },
  qr{v/search},    sub { $_[0]->resRedirect("/v/all?q=".$_[0]->reqParam('q'), 'perm') },
  qr{notes},       sub { $_[0]->resRedirect('/d8', 'perm') },
  qr{faq},         sub { $_[0]->resRedirect('/d6', 'perm') },
  qr{v([1-9]\d*)/(?:stats|scr|votes)},
    sub { $_[0]->resRedirect("/v$_[1]", 'perm') },
  qr{u/list(/[a-z0]|/all)?},
    sub { my $l = defined $_[1] ? $_[1] : '/all'; $_[0]->resRedirect("/u$l", 'perm') },
  qr{d([1-9]\d*)\.([1-9]\d*)},
    sub { $_[0]->resRedirect("/d$_[1]#$_[2]", 'perm') },

  # rewrite the old category browser to the new-ish search function
  qr{v/cat}, sub {
    my $f = $_[0]->formValidate(
      {name=>'i',required=>0,default=>''},{name=>'e',required=>0,default=>''},{name=>'l',required=>0,default=>''},
      {name=>'p',required=>0},{name=>'o',required=>0},{name=>'s',required=>0});
    my %f;
    $f{$_} = $f->{$_} for (qw|p o s|);
    $f{q} = join ' ', (map $_[0]{categories}{substr($_,0,1)}[1]{substr($_,1,2)}, split /,/, $f->{i}),
                      (map '-'.$_[0]{categories}{substr($_,0,1)}[1]{substr($_,1,2)}, split /,/, $f->{e}),
                      (map $_[0]{languages}{$_}, split /,/, $f->{l});
    !$f{$_} && delete $f{$_} for keys %f;
    $_[0]->resRedirect('/v/all'.(!(keys %f)?'':'?'.join(';', map $_.'='.$f{$_}, keys %f) ), 'perm');
  },

);


sub homepage {
  my $self = shift;
  $self->htmlHeader(title => $self->{site_title});

  div class => 'mainbox';
   h1 $self->{site_title};
   p class => 'description';
    lit qq|
     VNDB.org strives to be a comprehensive database for information about visual novels and
     eroge.<br />
     This website is built as a wiki, meaning that anyone can freely add and contribute information
     to the database, allowing us to create the largest, most accurate and most up-to-date visual novel
     database on the web.<br />
     Registered users are also able to keep track of a personal list of games they want to play or have finished
     and they can vote on all visual novels.<br />
     <br />
     Feel free to <a href="/v/all">browse around</a>, <a href="/u/register">register an account</a>
     or to participate in the discussions about visual novels or VNDB on our <a href="/t">discussion board</a>.
    |;
   end;

   my $scr = $self->dbScreenshotRandom;
   p class => 'screenshots';
    for (@$scr) {
      a href => "/v$_->{vid}", title => $_->{title};
       img src => sprintf("%s/st/%02d/%d.jpg", $self->{url_static}, $_->{scr}%100, $_->{scr}), alt => $_->{title};
      end;
    }
   end;
  end;

  # Recent changes
  div class => 'mainbox threelayout';
   h1 'Recent changes';
   my $changes = $self->dbRevisionGet(what => 'item user', results => 10, auto => 1, hidden => 1);
   ul;
    for (@$changes) {
      my $t = (qw|v r p|)[$_->{type}];
      li;
       b "$t:";
       a href => "/$t$_->{iid}.$_->{rev}", title => $_->{ioriginal}||$_->{ititle}, shorten $_->{ititle}, 30;
       txt ' by ';
       a href => "/u$_->{requester}", $_->{username};
      end;
    }
   end;
  end;

  # Announcements
  div class => 'mainbox threelayout';
   my $an = $self->dbThreadGet(type => 'an', order => 't.id DESC', results => 2);
   a class => 'right', href => '/t/an', 'News archive';
   h1 'Announcements';
   for (@$an) {
     my $post = $self->dbPostGet(tid => $_->{id}, num => 1)->[0];
     h2;
      a href => "/t$_->{id}", $_->{title};
     end;
     p;
      lit bb2html $post->{msg}, 150;
     end;
   }
  end;

  # Recent posts
  div class => 'mainbox threelayout last';
   h1 'Recent posts';
   my $posts = $self->dbThreadGet(what => 'lastpost', results => 10, order => 'tpl.date DESC');
   ul;
    for (@$posts) {
      li;
       txt age($_->{ldate}).' ';
       a href => "/t$_->{id}.$_->{count}", title => $_->{title}, shorten $_->{title}, 20;
       txt ' by ';
       a href => "/u$_->{luid}", $_->{lusername};
      end;
    }
   end;
  end;

  # Random visual novels
  div class => 'mainbox threelayout';
   h1 'Random visual novels';
   my $random = $self->dbVNGet(results => 10, order => 'RANDOM()');
   ul;
    for (@$random) {
      li;
       a href => "/v$_->{id}", title => $_->{original}||$_->{title}, shorten $_->{title}, 40;
      end;
    }
   end;
  end;

  # Upcoming releases
  div class => 'mainbox threelayout';
   h1 'Upcoming releases';
   my $upcoming = $self->dbReleaseGet(results => 10, unreleased => 1);
   ul;
    for (@$upcoming) {
      li;
       lit datestr $_->{released};
       txt ' ';
       a href => "/r$_->{id}", title => $_->{original}||$_->{title}, shorten $_->{title}, 30;
      end;
    }
   end;
  end;

  # Just released
  div class => 'mainbox threelayout last';
   h1 'Just released';
   my $justrel = $self->dbReleaseGet(results => 10, order => 'rr.released DESC', unreleased => 0);
   ul;
    for (@$justrel) {
      li;
       lit datestr $_->{released};
       txt ' ';
       a href => "/r$_->{id}", title => $_->{original}||$_->{title}, shorten $_->{title}, 30;
      end;
    }
   end;
  end;

  clearfloat;
  $self->htmlFooter;
}


sub history {
  my($self, $type, $id) = @_;
  $type ||= '';
  $id ||= 0;

  my $f = $self->formValidate(
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'm', required => 0, default => !$type, enum => [ 0, 1 ] },
    { name => 'h', required => 0, default => 1, enum => [ -1..1 ] },
    { name => 't', required => 0, default => '', enum => [ 'v', 'r', 'p' ] },
    { name => 'e', required => 0, default => 0, enum => [ -1..1 ] },
    { name => 'r', required => 0, default => 0, enum => [ 0, 1 ] },
  );
  return 404 if $f->{_err};

  # get item object and title
  my $obj = $type eq 'u' ? $self->dbUserGet(uid => $id)->[0] :
            $type eq 'p' ? $self->dbProducerGet(id => $id)->[0] :
            $type eq 'r' ? $self->dbReleaseGet(id => $id)->[0] :
                           $self->dbVNGet(id => $id)->[0];
  my $title = $type ? 'Edit history of '.($obj->{title} || $obj->{name} || $obj->{username}) : 'Recent changes';
  return 404 if $type && !$obj->{id};

  # get the edit history
  my($list, $np) = $self->dbRevisionGet(
    what => 'item user',
    $type && $type ne 'u' ? ( type => $type, iid => $id ) : (),
    $type eq 'u' ? ( uid => $id ) : (),
    $f->{t} ? ( type => $f->{t} ) : (),
    page => $f->{p},
    results => 50,
    auto => $f->{m},
    hidden => $f->{h},
    edit => $f->{e},
    releases => $f->{r},
  );

  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs($type, $obj, 'hist') if $type;

  # url generator
  my $u = sub {
    my($n, $v) = @_;
    $n ||= '';
    local $_ = ($type ? "/$type$id" : '').'/hist';
    $_ .= '?m='.($n eq 'm' ? $v : $f->{m});
    $_ .= ';h='.($n eq 'h' ? $v : $f->{h});
    $_ .= ';t='.($n eq 't' ? $v : $f->{t});
    $_ .= ';e='.($n eq 'e' ? $v : $f->{e});
    $_ .= ';r='.($n eq 'r' ? $v : $f->{r});
  };

  # filters
  div class => 'mainbox';
   h1 $title;
   if($type ne 'u') {
     p class => 'browseopts';
      a !$f->{m} ? (class => 'optselected') : (), href => $u->(m => 0), 'Show automated edits';
      a  $f->{m} ? (class => 'optselected') : (), href => $u->(m => 1), 'Hide automated edits';
     end;
   }
   if(!$type || $type eq 'u') {
     if($self->authCan('del')) {
       p class => 'browseopts';
        a $f->{h} == 1  ? (class => 'optselected') : (), href => $u->(h =>  1), 'Hide deleted items';
        a $f->{h} == -1 ? (class => 'optselected') : (), href => $u->(h => -1), 'Show deleted items';
       end;
     }
     p class => 'browseopts';
      a !$f->{t}        ? (class => 'optselected') : (), href => $u->(t => ''),  'Show all items';
      a  $f->{t} eq 'v' ? (class => 'optselected') : (), href => $u->(t => 'v'), 'Only visual novels';
      a  $f->{t} eq 'r' ? (class => 'optselected') : (), href => $u->(t => 'r'), 'Only releases';
      a  $f->{t} eq 'p' ? (class => 'optselected') : (), href => $u->(t => 'p'), 'Only producers';
     end;
     p class => 'browseopts';
      a !$f->{e}       ? (class => 'optselected') : (), href => $u->(e =>  0), 'Show all changes';
      a  $f->{e} == 1  ? (class => 'optselected') : (), href => $u->(e =>  1), 'Only edits';
      a  $f->{e} == -1 ? (class => 'optselected') : (), href => $u->(e => -1), 'Only newly created pages';
     end;
   }
   if($type eq 'v') {
     p class => 'browseopts';
      a !$f->{r} ? (class => 'optselected') : (), href => $u->(r => 0), 'Exclude';
      a $f->{r}  ? (class => 'optselected') : (), href => $u->(r => 1), 'Include edits of releases';
     end;
   }
  end;

  $self->htmlHistory($list, $f, $np, $u->());
  $self->htmlFooter;
}


sub docpage {
  my($self, $did) = @_;

  open my $F, '<', sprintf('%s/data/docs/%d', $VNDB::ROOT, $did) or return 404;
  my @c = <$F>;
  close $F;

  (my $title = shift @c) =~ s/^:TITLE://;
  chomp $title;

  my $sec = 0;
  for (@c) {
    s{^:SUB:(.+)\r?\n$}{
      $sec++;
      qq|<h3><a href="#$sec" name="$sec">$sec. $1</a></h3>\n|
    }eg;
    s{^:INC:(.+)\r?\n$}{
      open $F, '<', sprintf('%s/data/docs/%s', $VNDB::ROOT, $1) or die $!;
      my $ii = join('', <$F>);
      close $F;
      $ii;
    }eg;
  }

  $self->htmlHeader(title => $title);
  div class => 'mainbox';
   h1 $title;
   div class => 'docs';
    lit join '', @c;
   end;
  end;
  $self->htmlFooter;
}


sub nospam {
  my $self = shift;
  $self->htmlHeader(title => 'Could not send form', noindex => 1);

  div class => 'mainbox';
   h1 'Could not send form';
   div class => 'warning';
    h2 'Error';
    p 'The form could not be sent, please make sure you have Javascript enabled in your browser.';
   end;
  end;

  $self->htmlFooter;
}


# /hide and /lock for v/r/p+ pages
sub itemmod {
  my($self, $type, $iid, $act) = @_;
  return $self->htmlDenied if !$self->authCan($act eq 'hide' ? 'del' : 'lock');

  my $obj = $type eq 'v' ? $self->dbVNGet(id => $iid)->[0] :
            $type eq 'r' ? $self->dbReleaseGet(id => $iid)->[0] :
                           $self->dbProducerGet(id => $iid)->[0];
  return 404 if !$obj->{id};

  $self->dbItemMod($type, $iid, $act eq 'hide' ? (hidden => !$obj->{hidden}) : (locked => !$obj->{locked}));

  $self->resRedirect("/$type$iid", 'temp');
}


sub ie6message {
  my $self = shift;

  if($self->reqParam('i-still-want-access')) {
    (my $ref = $self->reqHeader('Referer') || '/') =~ s/^\Q$self->{url}//;
    $ref = '/' if $ref eq '/we-dont-like-ie6';
    $self->resRedirect($ref, 'temp');
    $self->resHeader('Set-Cookie', "ie-sucks=1; path=/; domain=$self->{cookie_domain}");
    return;
  }

  html;
   head;
    title 'Your browser sucks';
    style type => 'text/css',
      q|body { background: black }|
     .q|div  { position: absolute; left: 50%; top: 50%; width: 500px; margin-left: -250px; height: 180px; margin-top: -90px; background-color: #012; border: 1px solid #258; text-align: center; }|
     .q|p    { color: #ddd; margin: 10px; font: 9pt "Tahoma"; }|
     .q|h1   { color: #258; font-size: 14pt; font-family: "Futura", "Century New Gothic", "Arial", Serif; font-weight: normal; margin: 10px 0 0 0; } |
     .q|a    { color: #fff }|;
   end;
   body;
    div;
     h1 'Oops, we were too lazy support your browser!';
     p;
      lit qq|We decided to stop supporting Internet Explorer 6, as it's a royal pain in |
         .qq|the ass to make our site look good in a browser that doesn't want to cooperate with us.<br />|
         .qq|You can try one of the following free alternatives: |
         .qq|<a href="http://www.mozilla.com/firefox/">Firefox</a>, |
         .qq|<a href="http://www.opera.com/">Opera</a>, |
         .qq|<a href="http://www.apple.com/safari/">Safari</a>, or |
         .qq|<a href="http://www.google.com/chrome">Chrome</a>.<br /><br />|
         .qq|If you're really stubborn about using Internet Explorer, upgrading to version 7 will also work.<br /><br />|
         .qq|...and if you're mad, you can also choose to ignore this warning and |
         .qq|<a href="/we-dont-like-ie6?i-still-want-access=1">open the site anyway</a>.|;
     end;
    end;
   end;
  end;
}


1;


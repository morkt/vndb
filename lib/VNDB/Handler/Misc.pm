
package VNDB::Handler::Misc;


use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{},                              \&homepage,
  qr{(?:([upvr])([1-9]\d*)/)?hist},  \&history,
  qr{nospam},                        \&nospam,
  qr{([vrp])([1-9]\d*)/(lock|hide)}, \&itemmod,
 
  # redirects for old URLs
  qr{(.*[^/]+)/+}, sub { $_[0]->resRedirect("/$_[1]", 'perm') },
  qr{p},           sub { $_[0]->resRedirect('/p/all', 'perm') },
  qr{notes},       sub { $_[0]->resRedirect('/d8', 'perm') },
  qr{faq},         sub { $_[0]->resRedirect('/d6', 'perm') },
  qr{v([1-9]\d*)/(?:stats|scr|votes)},
    sub { $_[0]->resRedirect("/v$_[1]", 'perm') },
  qr{u/list(/[a-z0]|/all)?},
    sub { my $l = defined $_[1] ? $_[1] : '/all'; $_[0]->resRedirect("/u$l", 'perm') },
);


sub homepage {
  my $self = shift;
  $self->htmlHeader(title => 'The Visual Novel Database');

  div class => 'mainbox';
   h1 'The Visual Novel Database';
  end;

  $self->htmlFooter;
}


sub history {
  my($self, $type, $id) = @_;
  $type ||= '';
  $id ||= 0;

  my $f = $self->formValidate(
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'm', required => 0, default => 1, enum => [ 0, 1 ] },
    { name => 'h', required => 0, default => 1, enum => [ -1..1 ] },
    { name => 't', required => 0, default => '', enum => [ 'v', 'r', 'p' ] },
    { name => 'e', required => 0, default => 0, enum => [ -1..1 ] },
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
  end;

  # actual browse box
  $self->htmlBrowse(
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => $u->(),
    class    => 'history',
    header   => [
      sub { td colspan => 2, class => 'tc1', 'Rev.' },
      [ 'Date' ],
      [ 'User' ],
      [ 'Page' ],
    ],
    row      => sub {
      my($s, $n, $i) = @_;
      my $tc = [qw|v r p|]->[$i->{type}];
      my $revurl = "/$tc$i->{iid}.$i->{rev}";

      Tr $n % 2 ? ( class => 'odd' ) : ();
       td class => 'tc1_1'; 
        a href => $revurl, "$tc$i->{iid}";  
       end;
       td class => 'tc1_2'; 
        a href => $revurl, ".$i->{rev}";   
       end;
       td date $i->{added};
       td;
        lit userstr($i);
       end;
       td;
        a href => $revurl, title => $i->{ioriginal}, shorten $i->{ititle}, 80;
       end;
      end;
      if($i->{comments}) {
        Tr $n % 2 ? ( class => 'odd' ) : ();
         td colspan => 5, class => 'editsum';
          lit bb2html $i->{comments}, 150;
         end;
        end;
      }
    },
  );

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


1;


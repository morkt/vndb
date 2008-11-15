
package VNDB::Handler::Misc;


use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{},                              \&homepage,
  qr{(?:([upvr])([1-9]\d*)/)?hist},  \&history,
  qr{nospam},                        \&nospam,
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
    { name => 'm', required => 0, default => 0, enum => [ 0, 1 ] },
    { name => 'h', required => 0, default => 1, enum => [ -1..1 ] },
    { name => 't', required => 0, default => '', enum => [ 'v', 'r', 'p' ] },
  );
  return 404 if $f->{_err};

  # get item object and title
  my $obj = $type eq 'u' ? $self->dbUserGet(uid => $id)->[0] :
            $type eq 'p' ? $self->dbProducerGet(id => $id)->[0] :
                           {};
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
  );

  $self->htmlHeader(title => $title);
  $self->htmlMainTabs($type, $obj, 'hist') if $type;

  my $u = sub {
    my($n, $v) = @_;
    $n ||= '';
    local $_ = ($type ? "/$type$id" : '').'/hist';
    $_ .= '?m='.($n eq 'm' ? $v : $f->{m});
    $_ .= '&h='.($n eq 'h' ? $v : $f->{h});
    $_ .= '&t='.($n eq 't' ? $v : $f->{t});
  };

  div class => 'mainbox';
   h1 $title;
   if($type ne 'u') {
     p class => 'browseopts';
      a !$f->{m} ? (class => 'optselected') : (), href => $u->(m => 0), 'Show automated edits';
      a  $f->{m} ? (class => 'optselected') : (), href => $u->(m => 1), 'Hide automated edits';
     end;
   }
   if($self->authCan('del')) {
     p class => 'browseopts';
      a $f->{h} == 1  ? (class => 'optselected') : (), href => $u->(h =>  1), 'Hide deleted items';
      a $f->{h} == -1 ? (class => 'optselected') : (), href => $u->(h => -1), 'Show deleted items';
     end;
   }
   if(!$type || $type eq 'u') {
     p class => 'browseopts';
      a !$f->{t}        ? (class => 'optselected') : (), href => $u->(t => ''),  'Show all items';
      a  $f->{t} eq 'v' ? (class => 'optselected') : (), href => $u->(t => 'v'), 'Only visual novels';
      a  $f->{t} eq 'r' ? (class => 'optselected') : (), href => $u->(t => 'r'), 'Only releases';
      a  $f->{t} eq 'p' ? (class => 'optselected') : (), href => $u->(t => 'p'), 'Only producers';
     end;
   }
  end;

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
  $self->htmlHeader(title => 'Could not send form');

  div class => 'mainbox';
   h1 'Could not send form';
   div class => 'warning';
    h2 'Error';
    p 'The form could not be sent, please make sure you have Javascript enabled in your browser.';
   end;
  end;

  $self->htmlFooter;
}


1;


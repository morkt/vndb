
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
    page => $f->{p},
    results => 50,
  );

  $self->htmlHeader(title => $title);
  $self->htmlMainTabs($type, $obj, 'hist') if $type;

  div class => 'mainbox';
   h1 $title;
   p class => 'center', 'Some filter or search options here';
  end;

  $self->htmlBrowse(
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => ($type ? "/$type$id" : '').'/hist',
    class    => 'history',
    header   => [
      sub { td colspan => 2, class => 'tc1', 'Rev.' },
      [ 'Date' ],
      [ 'User' ],
      [ 'Page' ],
      #[ 'Edit summary' ],
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
        a href => "/u$i->{requester}", $i->{username}; 
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


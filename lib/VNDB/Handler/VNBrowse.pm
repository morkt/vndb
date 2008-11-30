
package VNDB::Handler::VNBrowse;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{v/([a-z0]|all)}  => \&list,
);


sub list {
  my($self, $char) = @_;

  my $f = $self->formValidate(
    { name => 's', required => 0, default => 'title', enum => [ qw|title rel| ] },
    { name => 'o', required => 0, default => 'a', enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'q', required => 0, default => '' },
  );
  return 404 if $f->{_err};

  my($list, $np) = $self->dbVNGet(
    $char ne 'all' ? ( char => $char ) : (),
    $f->{q} ? ( search => $f->{q} ) : (),
    results => 50,
    page => $f->{p},
    order => ($f->{s} eq 'rel' ? 'c_released' : 'title').($f->{o} eq 'a' ? ' ASC' : ' DESC'),
  );

  $self->htmlHeader(title => 'Browse visual novels');

  div class => 'mainbox';
   h1 'Browse visual novels';
   form class => 'search', action => '/v/all', 'accept-charset' => 'UTF-8', method => 'get';
    fieldset;
     input type => 'text', name => 'q', id => 'q', class => 'text', value => $f->{q};
     input type => 'submit', class => 'submit', value => 'Search!';
    end;
   end;
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/v/$_", $_ eq $char ? (class => 'optselected') : (), $_ ? uc $_ : '#';
    }
   end;
  end;
  
  $self->htmlBrowse(
    class    => 'vnbrowse',
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => "/v/$char?o=$f->{o};s=$f->{s};q=$f->{q}",
    sorturl  => "/v/$char?q=$f->{q}",
    header   => [
      [ 'Title',    'title' ],
      [ '',         0       ],
      [ '',         0       ],
      [ 'Released', 'rel'   ],
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       td class => 'tc1';
        a href => '/v'.$l->{id}, title => $l->{original}||$l->{title}, shorten $l->{title}, 100;
       end;
       td class => 'tc2';
        $_ ne 'oth' && acronym class => "icons $_", title => $self->{platforms}{$_}, ' '
          for (sort split /\//, $l->{c_platforms});
       end;
       td class => 'tc3';
        acronym class => "icons lang $_", title => $self->{languages}{$_}, ' '
          for (reverse sort split /\//, $l->{c_languages});
       end;
       td class => 'tc4';
        lit monthstr $l->{c_released};
       end;
      end;
    },
  );
  $self->htmlFooter;
}


1;


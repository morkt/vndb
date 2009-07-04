
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
    { name => 's', required => 0, default => 'title', enum => [ qw|title rel pop| ] },
    { name => 'o', required => 0, default => 'a', enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'q', required => 0, default => '' },
    { name => 'sq', required => 0, default => '' },
    { name => 'ln', required => 0, multi => 1, enum => [ keys %{$self->{languages}} ], default => '' },
    { name => 'pl', required => 0, multi => 1, enum => [ keys %{$self->{platforms}} ], default => '' },
  );
  return 404 if $f->{_err};
  $f->{q} ||= $f->{sq};

  if($f->{q}) {
    return $self->resRedirect('/'.$1.$2.(!$3 ? '' : $1 eq 'd' ? '#'.$3 : '.'.$3), 'temp')
      if $f->{q} =~ /^([gvrptud])([0-9]+)(?:\.([0-9]+))?$/;

    # for URL compatibilty with older versions
    my @lang;
    $f->{q} =~ s/\s*$self->{languages}{$_}\s*//&&push @lang, $_ for (keys %{$self->{languages}});
    $f->{ln} = $f->{ln}[0] ? [ @{$f->{ln}}, @lang ] : \@lang;
  }

  my($list, $np) = $self->dbVNGet(
    $char ne 'all' ? ( char => $char ) : (),
    $f->{q} ? ( search => $f->{q} ) : (),
    results => 50,
    page => $f->{p},
    order => ($f->{s} eq 'rel' ? 'c_released' : $f->{s} eq 'pop' ? 'c_popularity' : 'title').($f->{o} eq 'a' ? ' ASC' : ' DESC'),
    $f->{pl}[0] ? ( platform => $f->{pl} ) : (),
    $f->{ln}[0] ? ( lang => $f->{ln} ) : (),
  );

  $self->resRedirect('/v'.$list->[0]{id}, 'temp')
    if $f->{q} && @$list == 1;

  $self->htmlHeader(title => 'Browse visual novels', search => $f->{q});
  _filters($self, $f, $char);
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
      [ 'Popularity', 'pop' ],
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       td class => 'tc1';
        a href => '/v'.$l->{id}, title => $l->{original}||$l->{title}, shorten $l->{title}, 100;
       end;
       td class => 'tc2';
        $_ ne 'oth' && cssicon $_, $self->{platforms}{$_}
          for (sort split /\//, $l->{c_platforms});
       end;
       td class => 'tc3';
        cssicon "lang $_", $self->{languages}{$_}
          for (reverse sort split /\//, $l->{c_languages});
       end;
       td class => 'tc4';
        lit monthstr $l->{c_released};
       end;
       td class => 'tc5', sprintf '%.2f', $l->{c_popularity}*100;
      end;
    },
  );
  $self->htmlFooter;
}


sub _filters {
  my($self, $f, $char) = @_;

  form action => '/v/all', 'accept-charset' => 'UTF-8', method => 'get';
  div class => 'mainbox';
   h1 'Browse visual novels';
   $self->htmlSearchBox('v', $f->{q});
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/v/$_", $_ eq $char ? (class => 'optselected') : (), $_ ? uc $_ : '#';
    }
   end;
   a id => 'advselect', href => '#';
    lit '<i>&#9656;</i> advanced search';
   end;
   div id => 'advoptions', class => 'hidden vnoptions';
    h2;
     lit 'Languages <b>(boolean or, selecting more gives more results)</b>';
    end;
    for my $i (sort @{$self->dbLanguages}) {
      span;
       input type => 'checkbox', name => 'ln', value => $i, id => "lang_$i",
         (scalar grep $_ eq $i, @{$f->{ln}}) ? (checked => 'checked') : ();
       label for => "lang_$i";
        cssicon "lang $i", $self->{languages}{$i};
        txt $self->{languages}{$i};
       end;
      end;
    }

    h2;
     lit 'Platforms <b>(boolean or, selecting more gives more results)</b>';
    end;
    for my $i (sort keys %{$self->{platforms}}) {
      next if $i eq 'oth';
      span;
       input type => 'checkbox', id => "plat_$i", name => 'pl', value => $i,
         (scalar grep $_ eq $i, @{$f->{pl}}) ? (checked => 'checked') : ();
       label for => "plat_$i";
        cssicon $i, $self->{platforms}{$i};
        txt $self->{platforms}{$i};
       end;
      end;
    }

    clearfloat;
   end;
  end;
  end;
}


1;


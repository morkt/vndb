
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
  );
  return 404 if $f->{_err};
  $f->{q} ||= $f->{sq};

  my(@plat, @lang);
  my $q = $f->{q};
  if($q) {
   # VNDBID
    return $self->resRedirect('/'.$1.$2.(!$3 ? '' : $1 eq 'd' ? '#'.$3 : '.'.$3), 'temp')
      if $q =~ /^([gvrptud])([0-9]+)(?:\.([0-9]+))?$/;

    if(!($q =~ s/^title://)) {
     # platforms
      $_ ne 'oth' && $q =~ s/(?:$self->{platforms}{$_}|p:$_)//ig && push @plat, $_ for keys %{$self->{platforms}};

     # languages
      $q =~ s/($self->{languages}{$_}|l:$_)//ig && push @lang, $_ for keys %{$self->{languages}};
    }
  }
  $q =~ s/ +$//;
  $q =~ s/^ +//;

  my($list, $np) = $self->dbVNGet(
    $char ne 'all' ? ( char => $char ) : (),
    $q ? ( search => $q ) : (),
    results => 50,
    page => $f->{p},
    order => ($f->{s} eq 'rel' ? 'c_released' : $f->{s} eq 'pop' ? 'c_popularity' : 'title').($f->{o} eq 'a' ? ' ASC' : ' DESC'),
    @lang ? ( lang => \@lang ) : (),
    @plat ? ( platform => \@plat ) : (),
  );

  $self->resRedirect('/v'.$list->[0]{id}, 'temp')
    if $q && @$list == 1;

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

  div class => 'mainbox';
   h1 'Browse visual novels';
   form action => '/v/all', 'accept-charset' => 'UTF-8', method => 'get';
    $self->htmlSearchBox('v', $f->{q});
   end;
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
    for(sort @{$self->dbLanguages}) {
      span;
       input type => 'checkbox', id => "lang_$_";
       label for => "lang_$_";
        cssicon "lang $_", $self->{languages}{$_};
        txt $self->{languages}{$_};
       end;
      end;
    }

    h2;
     lit 'Platforms <b>(boolean or, selecting more gives more results)</b>';
    end;
    for(sort keys %{$self->{platforms}}) {
      next if $_ eq 'oth';
      span;
       input type => 'checkbox', id => "plat_$_";
       label for => "plat_$_";
        cssicon $_, $self->{platforms}{$_};
        txt $self->{platforms}{$_};
       end;
      end;
    }

    clearfloat;
   end;
  end;
}


1;


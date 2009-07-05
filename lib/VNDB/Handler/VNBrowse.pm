
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
    { name => 's', required => 0, default => 'tagscore', enum => [ qw|title rel pop tagscore| ] },
    { name => 'o', required => 0, enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'q', required => 0, default => '' },
    { name => 'sq', required => 0, default => '' },
    { name => 'ln', required => 0, multi => 1, enum => [ keys %{$self->{languages}} ], default => '' },
    { name => 'pl', required => 0, multi => 1, enum => [ keys %{$self->{platforms}} ], default => '' },
    { name => 'ti', required => 0, default => '', maxlength => 200 },
    { name => 'te', required => 0, default => '', maxlength => 200 },
    { name => 'sp', required => 0, default => $self->reqCookie('tagspoil') =~ /^([0-2])$/ ? $1 : 1, enum => [0..2] },
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

  my @ignored;
  my $tagfind = sub {
    return map {
      my $i = $self->dbTagGet(name => $_)->[0];
      push @ignored, [$_, 0] if !$i;
      push @ignored, [$_, 1] if $i && $i->{meta};
      $i && !$i->{meta} ? $i->{id} : ();
    } grep $_, split /\s*,\s*/, $_[0];
  };
  my @ti = $tagfind->($f->{ti});
  my @te = $tagfind->($f->{te});

  $f->{s} = 'title' if !@ti && $f->{s} eq 'tagscore';
  $f->{o} = $f->{s} eq 'tagscore' ? 'd' : 'a' if !$f->{o};

  my($list, $np) = $self->dbVNGet(
    $char ne 'all' ? ( char => $char ) : (),
    $f->{q} ? ( search => $f->{q} ) : (),
    results => 50,
    page => $f->{p},
    order => ($f->{s} eq 'rel' ? 'c_released' : $f->{s} eq 'pop' ? 'c_popularity' : $f->{s}).($f->{o} eq 'a' ? ' ASC' : ' DESC'),
    $f->{pl}[0] ? ( platform => $f->{pl} ) : (),
    $f->{ln}[0] ? ( lang => $f->{ln} ) : (),
    @ti ? (tags_include => [ $f->{sp}, \@ti ]) : (),
    @te ? (tags_exclude => \@te) : (),
  );

  $self->resRedirect('/v'.$list->[0]{id}, 'temp')
    if $f->{q} && @$list == 1;

  $self->htmlHeader(title => 'Browse visual novels', search => $f->{q}, js => 'forms');
  _filters($self, $f, $char, \@ignored);

  my $url = "/v/$char?q=$f->{q};ti=$f->{ti};te=$f->{te}";
  $_ and $url .= ";pl=$_" for @{$f->{pl}};
  $_ and $url .= ";ln=$_" for @{$f->{ln}};
  $self->htmlBrowse(
    class    => 'vnbrowse',
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => "$url;o=$f->{o};s=$f->{s}",
    sorturl  => $url,
    header   => [
      @ti ? [ 'Score', 'tagscore', undef, 'tc_s' ] : (),
      [ 'Title',      'title', undef, @ti ? 'tc_t' : 'tc1' ],
      [ '',           0,       undef, 'tc2' ],
      [ '',           0,       undef, 'tc3' ],
      [ 'Released',   'rel',   undef, 'tc4' ],
      [ 'Popularity', 'pop',   undef, 'tc5' ],
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       if(@ti) {
         td class => 'tc_s';
          tagscore $l->{tagscore}, 0;
         end;
       }
       td class => @ti ? 'tc_t' : 'tc1';
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
  my($self, $f, $char, $ign) = @_;

  form action => '/v/all', 'accept-charset' => 'UTF-8', method => 'get';
  div class => 'mainbox';
   h1 'Browse visual novels';
   $self->htmlSearchBox('v', $f->{q});
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/v/$_", $_ eq $char ? (class => 'optselected') : (), $_ ? uc $_ : '#';
    }
   end;

   if(@$ign) {
     div class => 'warning';
      h2 'The following tags were ignored:';
      ul;
       li $_->[0].' ('.($_->[1]?"can't filter on meta tags":"no such tag found").')' for @$ign;
      end;
     end;
   }

   a id => 'advselect', href => '#';
    lit '<i>&#9656;</i> advanced search';
   end;
   div id => 'advoptions', class => 'hidden vnoptions';

    h2;
     lit 'Tag filters <b>(boolean and, selecting more gives less results)</b>';
    end;
    table class => 'formtable', style => 'margin-left: 0';
     $self->htmlFormPart($f, [ input => short => 'ti', name => 'Tags to include', width => 350 ]);
     $self->htmlFormPart($f, [ radio => short => 'sp', name => '', options => [[0,'Hide spoilers'],[1,'Show minor spoilers'],[2,'Show major spoilers']]]);
     $self->htmlFormPart($f, [ input => short => 'te', name => 'Tags to exclude', width => 350 ]);
    end;

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

    div style => 'text-align: center; clear: left;';
     input type => 'submit', value => 'Apply', class => 'submit';
     input type => 'reset', value => 'Clear', class => 'submit', onclick => 'location.href="/v/all"';
    end;
   end;
  end;
  end;
}


1;


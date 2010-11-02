
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
    { name => 's', required => 0, default => 'tagscore', enum => [ qw|title rel pop tagscore rating| ] },
    { name => 'o', required => 0, enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'q', required => 0, default => '' },
    { name => 'sq', required => 0, default => '' },
    { name => 'ln', required => 0, multi => 1, enum => $self->{languages}, default => '' },
    { name => 'pl', required => 0, multi => 1, enum => $self->{platforms}, default => '' },
    { name => 'ti', required => 0, default => '', maxlength => 200 },
    { name => 'te', required => 0, default => '', maxlength => 200 },
    { name => 'sp', required => 0, default => $self->reqCookie($self->{cookie_prefix}.'tagspoil') =~ /^([0-2])$/ ? $1 : 0, enum => [0..2] },
  );
  return 404 if $f->{_err};
  $f->{q} ||= $f->{sq};

  if($f->{q}) {
    return $self->resRedirect('/'.$1.$2.(!$3 ? '' : $1 eq 'd' ? '#'.$3 : '.'.$3), 'temp')
      if $f->{q} =~ /^([gvrptud])([0-9]+)(?:\.([0-9]+))?$/;

    # for URL compatibilty with older versions (ugly hack to get English strings)
    my @lang;
    $f->{q} =~ s/\s*$VNDB::L10N::en::Lexicon{"_lang_$_"}\s*//&&push @lang, $_ for (@{$self->{languages}});
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
    what => 'rating',
    $char ne 'all' ? ( char => $char ) : (),
    $f->{q} ? ( search => $f->{q} ) : (),
    results => 50,
    page => $f->{p},
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    $f->{pl}[0] ? ( platform => $f->{pl} ) : (),
    $f->{ln}[0] ? ( lang => $f->{ln} ) : (),
    @ti ? (tags_include => [ $f->{sp}, \@ti ]) : (),
    @te ? (tags_exclude => \@te) : (),
  );

  $self->resRedirect('/v'.$list->[0]{id}, 'temp')
    if $f->{q} && @$list == 1 && $f->{p} == 1;

  $self->htmlHeader(title => mt('_vnbrowse_title'), search => $f->{q});
  _filters($self, $f, $char, \@ignored);

  my $url = "/v/$char?q=$f->{q};ti=$f->{ti};te=$f->{te}";
  $_ and $url .= ";pl=$_" for @{$f->{pl}};
  $_ and $url .= ";ln=$_" for @{$f->{ln}};
  $self->htmlBrowseVN($list, $f, $np, $url, scalar @ti);
  $self->htmlFooter;
}


sub _filters {
  my($self, $f, $char, $ign) = @_;

  form action => '/v/all', 'accept-charset' => 'UTF-8', method => 'get';
  div class => 'mainbox';
   h1 mt '_vnbrowse_title';
   $self->htmlSearchBox('v', $f->{q});
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/v/$_", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? mt('_char_all') : $_ ? uc $_ : '#';
    }
   end;

   if(@$ign) {
     div class => 'warning';
      h2 mt '_vnbrowse_tagign_title';
      ul;
       li $_->[0].' ('.mt('_vnbrowse_tagign_'.($_->[1]?'meta':'notfound')).')' for @$ign;
      end;
     end;
   }

   a id => 'advselect', href => '#';
    lit '<i>&#9656;</i> '.mt('_vnbrowse_advsearch');
   end;
   div id => 'advoptions', class => 'hidden vnoptions';

    h2;
     txt mt '_vnbrowse_tags';
     b ' ('.mt('_vnbrowse_booland').')';
    end;
    table class => 'formtable', style => 'margin-left: 0';
     $self->htmlFormPart($f, [ input => short => 'ti', name => mt('_vnbrowse_taginc'), width => 350 ]);
     $self->htmlFormPart($f, [ radio => short => 'sp', name => '', options => [map [$_, mt '_vnbrowse_spoil'.$_], 0..2]]);
     $self->htmlFormPart($f, [ input => short => 'te', name => mt('_vnbrowse_tagexc'), width => 350 ]);
    end;

    h2;
     txt mt '_vnbrowse_lang';
     b ' ('.mt('_vnbrowse_boolor').')';
    end;
    for my $i (@{$self->{languages}}) {
      span;
       input type => 'checkbox', name => 'ln', value => $i, id => "lang_$i",
         (scalar grep $_ eq $i, @{$f->{ln}}) ? (checked => 'checked') : ();
       label for => "lang_$i";
        cssicon "lang $i", mt "_lang_$i";
        txt mt "_lang_$i";
       end;
      end;
    }

    h2;
     txt mt '_vnbrowse_plat';
     b ' ('.mt('_vnbrowse_boolor').')';
    end;
    for my $i (sort @{$self->{platforms}}) {
      next if $i eq 'oth';
      span;
       input type => 'checkbox', id => "plat_$i", name => 'pl', value => $i,
         (scalar grep $_ eq $i, @{$f->{pl}}) ? (checked => 'checked') : ();
       label for => "plat_$i";
        cssicon $i, mt "_plat_$i";
        txt mt "_plat_$i";
       end;
      end;
    }

    div style => 'text-align: center; clear: left;';
     input type => 'submit', value => mt('_vnbrowse_apply'), class => 'submit';
     input type => 'reset', value => mt('_vnbrowse_clear'), class => 'submit', onclick => 'location.href="/v/all"';
    end;
   end;
  end;
  end;
}


1;


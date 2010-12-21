
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
    { name => 'fil',required => 0, default => '' },
  );
  return 404 if $f->{_err};
  $f->{q} ||= $f->{sq};
  my $fil = fil_parse $f->{fil}, qw|length hasani tag_inc tag_exc taginc tagexc tagspoil lang olang plat|;
  _fil_compat($self, $fil);

  if($f->{q}) {
    return $self->resRedirect('/'.$1.$2.(!$3 ? '' : $1 eq 'd' ? '#'.$3 : '.'.$3), 'temp')
      if $f->{q} =~ /^([gvrptud])([0-9]+)(?:\.([0-9]+))?$/;

    # for URL compatibilty with older versions (ugly hack to get English strings)
    my @lang;
    $f->{q} =~ s/\s*$VNDB::L10N::en::Lexicon{"_lang_$_"}\s*//&&push @lang, $_ for (@{$self->{languages}});
    $fil->{lang} = $fil->{lang} ? [ ref($fil->{lang}) ? @{$fil->{lang}} : $fil->{lang}, @lang ] : \@lang if @lang;
  }
  $f->{fil} = fil_serialize $fil;

  $f->{s} = 'title' if !$fil->{tag_inc} && $f->{s} eq 'tagscore';
  $f->{o} = $f->{s} eq 'tagscore' ? 'd' : 'a' if !$f->{o};

  my($list, $np) = $self->dbVNGet(
    what => 'rating',
    $char ne 'all' ? ( char => $char ) : (),
    $f->{q} ? ( search => $f->{q} ) : (),
    results => 50,
    page => $f->{p},
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    %$fil
  );

  $self->resRedirect('/v'.$list->[0]{id}, 'temp')
    if $f->{q} && @$list == 1 && $f->{p} == 1;

  $self->htmlHeader(title => mt('_vnbrowse_title'), search => $f->{q});

  form action => '/v/all', 'accept-charset' => 'UTF-8', method => 'get';
  div class => 'mainbox';
   h1 mt '_vnbrowse_title';
   $self->htmlSearchBox('v', $f->{q});
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/v/$_?q=$f->{q};fil=$f->{fil}", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? mt('_char_all') : $_ ? uc $_ : '#';
    }
   end;

   a id => 'filselect', href => '#v';
    lit '<i>&#9656;</i> '.mt('_rbrowse_filters').'<i></i>'; # TODO: it's not *r*browse
   end;
   input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};
  end;
  end; # /form

  $self->htmlBrowseVN($list, $f, $np, "/v/$char?q=$f->{q};fil=$f->{fil}", $fil->{tag_inc});
  $self->htmlFooter;
}


sub _fil_compat {
  my($self, $fil) = @_;
  my $f = $self->formValidate(
    { name => 'ln', required => 0, multi => 1, enum => $self->{languages}, default => '' },
    { name => 'pl', required => 0, multi => 1, enum => $self->{platforms}, default => '' },
    { name => 'ti', required => 0, default => '', maxlength => 200 },
    { name => 'te', required => 0, default => '', maxlength => 200 },
    { name => 'sp', required => 0, default => $self->reqCookie($self->{cookie_prefix}.'tagspoil') =~ /^([0-2])$/ ? $1 : 0, enum => [0..2] },
  );
  $fil->{lang}     //= $f->{ln} if $f->{ln}[0];
  $fil->{plat}     //= $f->{pl} if $f->{pl}[0];
  $fil->{taginc}   //= $f->{ti} if $f->{ti};
  $fil->{tagexc}   //= $f->{te} if $f->{te};
  $fil->{tagspoil} //= $f->{sp};

  # older tag specification (by name rather than ID)
  my $tagfind = sub {
    return map {
      my $i = $self->dbTagGet(name => $_)->[0];
      $i && !$i->{meta} ? $i->{id} : ();
    } grep $_, ref $_[0] ? @{$_[0]} : ($_[0]||'')
  };
  $fil->{tag_inc} //= [ $tagfind->(delete $fil->{taginc}) ] if $fil->{taginc};
  $fil->{tag_exc} //= [ $tagfind->(delete $fil->{tagexc}) ] if $fil->{tagexc};
}


1;


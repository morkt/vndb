
package VNDB::Handler::VNBrowse;

use strict;
use warnings;
use TUWF ':html', 'uri_escape';
use VNDB::Func;


TUWF::register(
  qr{v/([a-z0]|all)}  => \&list,
);


sub list {
  my($self, $char) = @_;

  my $f = $self->formValidate(
    { get => 's', required => 0, default => 'tagscore', enum => [ qw|title rel pop tagscore rating| ] },
    { get => 'o', required => 0, enum => [ 'a','d' ] },
    { get => 'p', required => 0, default => 1, template => 'int' },
    { get => 'q', required => 0, default => '' },
    { get => 'sq', required => 0, default => '' },
    { get => 'fil',required => 0 },
  );
  return $self->resNotFound if $f->{_err};
  $f->{q} ||= $f->{sq};
  $f->{fil} //= $self->authPref('filter_vn');
  my %compat = _fil_compat($self);

  return $self->resRedirect('/'.$1.$2.(!$3 ? '' : $1 eq 'd' ? '#'.$3 : '.'.$3), 'temp')
    if $f->{q} && $f->{q} =~ /^([gvrptud])([0-9]+)(?:\.([0-9]+))?$/;

  $f->{s} = 'title' if $f->{fil} !~ /tag_inc-/ && $f->{s} eq 'tagscore';
  $f->{o} = $f->{s} eq 'tagscore' ? 'd' : 'a' if !$f->{o};

  my($list, $np) = $self->filFetchDB(vn => $f->{fil}, \%compat, {
    what => 'rating',
    $char ne 'all' ? ( char => $char ) : (),
    $f->{q} ? ( search => $f->{q} ) : (),
    results => 50,
    page => $f->{p},
    sort => $f->{s}, reverse => $f->{o} eq 'd',
  });

  $self->resRedirect('/v'.$list->[0]{id}, 'temp')
    if $f->{q} && @$list == 1 && $f->{p} == 1;

  $self->htmlHeader(title => mt('_vnbrowse_title'), search => $f->{q});

  my $quri = uri_escape($f->{q});
  form action => '/v/all', 'accept-charset' => 'UTF-8', method => 'get';
  div class => 'mainbox';
   h1 mt '_vnbrowse_title';
   $self->htmlSearchBox('v', $f->{q});
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/v/$_?q=$quri;fil=$f->{fil}", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? mt('_char_all') : $_ ? uc $_ : '#';
    }
   end;

   a id => 'filselect', href => '#v';
    lit '<i>&#9656;</i> '.mt('_js_fil_filters').'<i></i>';
   end;
   input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};
  end;
  end 'form';

  $self->htmlBrowseVN($list, $f, $np, "/v/$char?q=$quri;fil=$f->{fil}", $f->{fil} =~ /tag_inc-/);
  $self->htmlFooter(prefs => ['filter_vn']);
}


sub _fil_compat {
  my $self = shift;
  my %c;
  my $f = $self->formValidate(
    { get => 'ln', required => 0, multi => 1, enum => $self->{languages}, default => '' },
    { get => 'pl', required => 0, multi => 1, enum => $self->{platforms}, default => '' },
    { get => 'sp', required => 0, default => $self->reqCookie('tagspoil') =~ /^([0-2])$/ ? $1 : 0, enum => [0..2] },
  );
  return () if $f->{_err};
  $c{lang}     //= $f->{ln} if $f->{ln}[0];
  $c{plat}     //= $f->{pl} if $f->{pl}[0];
  $c{tagspoil} //= $f->{sp};
  return %c;
}


1;



package VNDB::Handler::Traits;

use strict;
use warnings;
use TUWF ':html', ':xml', 'html_escape';
use VNDB::Func;


TUWF::register(
  qr{i([1-9]\d*)},        \&traitpage,
  qr{i([1-9]\d*)/(edit)}, \&traitedit,
  qr{i([1-9]\d*)/(add)},  \&traitedit,
  qr{i/new},              \&traitedit,
  qr{i/list},             \&traitlist,
  qr{i},                  \&traitindex,
  qr{xml/traits\.xml},    \&traitxml,
);


sub traitpage {
  my($self, $trait) = @_;

  my $t = $self->dbTraitGet(id => $trait, what => 'parents(0) childs(2)')->[0];
  return $self->resNotFound if !$t;

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'int' },
    { get => 'm', required => 0, default => undef, enum => [qw|0 1 2|] },
    { get => 'fil', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};
  my $tagspoil = $self->reqCookie('tagspoil')||'';
  $f->{m} //= $tagspoil =~ /^[0-2]$/ ? $tagspoil : 0;

  my $title = mt '_traitp_title', $t->{meta}?0:1, $t->{name};
  $self->htmlHeader(title => $title, noindex => $t->{state} != 2);
  $self->htmlMainTabs('i', $t);

  if($t->{state} != 2) {
    div class => 'mainbox';
     h1 $title;
     if($t->{state} == 1) {
       div class => 'warning';
        h2 mt '_traitp_del_title';
        p;
         lit mt '_traitp_del_msg';
        end;
       end;
     } else {
       div class => 'notice';
        h2 mt '_traitp_pending_title';
        p mt '_traitp_pending_msg';
       end;
     }
    end 'div';
  }

  div class => 'mainbox';
   a class => 'addnew', href => "/i$trait/add", mt '_traitp_addchild' if $self->authCan('charedit') && $t->{state} != 1;
   h1 $title;

   parenttags($t, mt('_traitp_indexlink'), 'i');

   if($t->{description}) {
     p class => 'description';
      lit bb2html $t->{description};
     end;
   }
   if($t->{sexual}) {
     p class => 'center';
      b mt '_traitp_sexual';
     end;
   }
   if($t->{alias}) {
     p class => 'center';
      b mt('_traitp_aliases');
      br;
      lit html_escape($t->{alias});
     end;
   }
  end 'div';

  childtags($self, mt('_traitp_childs'), 'i', $t) if @{$t->{childs}};

  if(!$t->{meta} && $t->{state} == 2) {
    my($chars, $np) = $self->filFetchDB(char => $f->{fil}, {}, {
      trait_inc => $trait,
      tagspoil => $f->{m},
      results => 50,
      page => $f->{p},
      what => 'vns',
    });

    form action => "/i$t->{id}", 'accept-charset' => 'UTF-8', method => 'get';
    div class => 'mainbox';
     h1 mt '_traitp_charlist';

     p class => 'browseopts';
      # Q: tagp!? A: lazyness >_>
      a href => "/i$trait?m=0", $f->{m} == 0 ? (class => 'optselected') : (), onclick => "setCookie('tagspoil', 0);return true;", mt '_tagp_spoil0';
      a href => "/i$trait?m=1", $f->{m} == 1 ? (class => 'optselected') : (), onclick => "setCookie('tagspoil', 1);return true;", mt '_tagp_spoil1';
      a href => "/i$trait?m=2", $f->{m} == 2 ? (class => 'optselected') : (), onclick => "setCookie('tagspoil', 2);return true;", mt '_tagp_spoil2';
     end;

     a id => 'filselect', href => '#c';
      lit '<i>&#9656;</i> '.mt('_js_fil_filters').'<i></i>';
     end;
     input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};

     if(!@$chars) {
       p; br; br; txt mt '_traitp_nochars'; end;
     }
     p; br; txt mt '_traitp_cached'; end;
    end 'div';
    end 'form';
    @$chars && $self->charBrowseTable($chars, $np, $f, "/i$trait?m=$f->{m};fil=$f->{fil}");
  }

  $self->htmlFooter;
}


sub traitedit {
  my($self, $trait, $act) = @_;

  my($frm, $par);
  if($act && $act eq 'add') {
    $par = $self->dbTraitGet(id => $trait)->[0];
    return $self->resNotFound if !$par;
    $frm->{parents} = $par->{id};
    $trait = undef;
  }

  return $self->htmlDenied if !$self->authCan('charedit') || $trait && !$self->authCan('tagmod');

  my $t = $trait && $self->dbTraitGet(id => $trait, what => 'parents(1) addedby')->[0];
  return $self->resNotFound if $trait && !$t;

  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'name',        required => 1, maxlength => 250, regex => [ qr/^[^,]+$/, 'A comma is not allowed in trait names' ] },
      { post => 'state',       required => 0, default => 0,  enum => [ 0..2 ] },
      { post => 'meta',        required => 0, default => 0 },
      { post => 'sexual',      required => 0, default => 0 },
      { post => 'alias',       required => 0, maxlength => 1024, default => '', regex => [ qr/^[^,]+$/s, 'No comma allowed in aliases' ]  },
      { post => 'description', required => 0, maxlength => 10240, default => '' },
      { post => 'parents',     required => !$self->authCan('tagmod'), default => '', regex => [ qr/^(?:$|(?:[1-9]\d*)(?: +[1-9]\d*)*)$/, 'Parent traits must be a space-separated list of trait IDs' ] },
      { post => 'order',       required => 0, default => 0, template => 'int', min => 0 },
    );
    my @parents = split /[\t ]+/, $frm->{parents};
    my $group = undef;
    if(!$frm->{_err}) {
      for(@parents) {
        my $c = $self->dbTraitGet(id => $_);
        push @{$frm->{_err}}, [ 'parents', 'func', [ 0, mt '_tagedit_err_notfound', $_ ]] if !@$c;
        $group //= $c->[0]{group}||$c->[0]{id} if @$c;
      }
    }
    if(!$frm->{_err}) {
      my $c = $self->dbTraitGet(name => $frm->{name}, noid => $trait, group => $group);
      push @{$frm->{_err}}, [ 'name', 'traitexists', $c->[0] ] if @$c;
      for (split /[\t\s]*\n[\t\s]*/, $frm->{alias}) {
        $c = $self->dbTraitGet(name => $_, noid => $trait, group => $group);
        push @{$frm->{_err}}, [ 'alias', 'traitexists', $c->[0] ] if @$c;
      }
    }

    if(!$frm->{_err}) {
      $frm->{state} = $frm->{meta} = 0 if !$self->authCan('tagmod');
      my %opts = (
        name => $frm->{name},
        state => $frm->{state},
        description => $frm->{description},
        meta => $frm->{meta}?1:0,
        sexual => $frm->{sexual}?1:0,
        alias => $frm->{alias},
        order => $frm->{order},
        parents => \@parents,
        group => $group,
      );
      if(!$trait) {
        $trait = $self->dbTraitAdd(%opts);
      } else {
        $self->dbTraitEdit($trait, %opts, upddate => $frm->{state} == 2 && $t->{state} != 2) if $trait;
        _set_childs_group($self, $trait, $group||$trait) if ($group||0) != ($t->{group}||0);
      }
      $self->resRedirect("/i$trait", 'post');
      return;
    }
  }

  if($t) {
    $frm->{$_} ||= $t->{$_} for (qw|name meta sexual description state alias order|);
    $frm->{parents} ||= join ' ', map $_->{id}, @{$t->{parents}};
  }

  my $title = $par ? mt('_traite_title_add', $par->{name}) : $t ? mt('_traite_title_edit', $t->{name}) : mt '_traite_title_new';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('i', $par || $t, 'edit') if $t || $par;

  if(!$self->authCan('tagmod')) {
    div class => 'mainbox';
     h1 mt '_traite_req_title';
     div class => 'notice';
      h2 mt '_traite_req_subtitle';
      p;
       lit mt '_traite_req_msg';
      end;
     end;
    end;
  }

  $self->htmlForm({ frm => $frm, action => $par ? "/i$par->{id}/add" : $t ? "/i$trait/edit" : '/i/new' }, 'traitedit' => [ $title,
    [ input    => short => 'name',     name => mt '_traite_frm_name' ],
    $self->authCan('tagmod') ? (
      $t ?
        [ static   => label => mt('_traite_frm_by'), content => $self->{l10n}->userstr($t->{addedby}, $t->{username}) ] : (),
      [ select   => short => 'state',    name => mt('_traite_frm_state'), options => [
        map [$_, mt '_traite_frm_state'.$_], 0..2 ] ],
      [ checkbox => short => 'meta',     name => mt '_traite_frm_meta' ]
    ) : (),
    [ checkbox => short => 'sexual',   name => mt '_traite_frm_sexual' ],
    [ textarea => short => 'alias',    name => mt('_traite_frm_alias'), cols => 30, rows => 4 ],
    [ textarea => short => 'description', name => mt '_traite_frm_desc' ],
    [ input    => short => 'parents',  name => mt '_traite_frm_parents' ],
    [ static   => content => mt '_traite_frm_parents_msg' ],
    $self->authCan('tagmod') ? (
      [ input    => short => 'order', name => mt('_traite_frm_gorder'), width => 50, post => ' '.mt('_traite_frm_gorder_msg') ],
    ) : (),
  ]);

  $self->htmlFooter;
}

# recursively edit all child traits and set the group field
sub _set_childs_group {
  my($self, $trait, $group) = @_;
  my %done;

  my $e;
  $e = sub {
    my $l = shift;
    for (@$l) {
      $self->dbTraitEdit($_->{id}, group => $group) if !$done{$_->{id}}++;
      $e->($_->{sub}) if $_->{sub};
    }
  };
  $e->($self->dbTTTree(trait => $trait, 25));
}


sub traitlist {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 's', required => 0, default => 'name', enum => ['added', 'name'] },
    { get => 'o', required => 0, default => 'a', enum => ['a', 'd'] },
    { get => 'p', required => 0, default => 1, template => 'int' },
    { get => 't', required => 0, default => -1, enum => [ -1..2 ] },
    { get => 'q', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

  my($t, $np) = $self->dbTraitGet(
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    page => $f->{p},
    results => 50,
    state => $f->{t},
    search => $f->{q}
  );

  $self->htmlHeader(title => mt '_traitb_title');
  div class => 'mainbox';
   h1 mt '_traitb_title';
   form action => '/i/list', 'accept-charset' => 'UTF-8', method => 'get';
    input type => 'hidden', name => 't', value => $f->{t};
    $self->htmlSearchBox('i', $f->{q});
   end;
   p class => 'browseopts';
    a href => "/i/list?q=$f->{q};t=-1", $f->{t} == -1 ? (class => 'optselected') : (), mt '_traitb_state-1';
    a href => "/i/list?q=$f->{q};t=0", $f->{t} == 0 ? (class => 'optselected') : (), mt '_traitb_state0';
    a href => "/i/list?q=$f->{q};t=1", $f->{t} == 1 ? (class => 'optselected') : (), mt '_traitb_state1';
    a href => "/i/list?q=$f->{q};t=2", $f->{t} == 2 ? (class => 'optselected') : (), mt '_traitb_state2';
   end;
   if(!@$t) {
     p mt '_traitb_noresults';
   }
  end 'div';
  if(@$t) {
    $self->htmlBrowse(
      class    => 'taglist',
      options  => $f,
      nextpage => $np,
      items    => $t,
      pageurl  => "/i/list?t=$f->{t};q=$f->{q};s=$f->{s};o=$f->{o}",
      sorturl  => "/i/list?t=$f->{t};q=$f->{q}",
      header   => [
        [ mt('_traitb_col_added'), 'added' ],
        [ mt('_traitb_col_name'),  'name'  ],
      ],
      row => sub {
        my($s, $n, $l) = @_;
        Tr;
         td class => 'tc1', $self->{l10n}->age($l->{added});
         td class => 'tc3';
          if($l->{group}) {
            b class => 'grayedout', $l->{groupname}.' / ';
          }
          a href => "/i$l->{id}", $l->{name};
          if($f->{t} == -1) {
            b class => 'grayedout', ' '.mt '_traitb_note_awaiting' if $l->{state} == 0;
            b class => 'grayedout', ' '.mt '_traitb_note_del' if $l->{state} == 1;
          }
         end;
        end 'tr';
      }
    );
  }
  $self->htmlFooter;
}


sub traitindex {
  my $self = shift;

  $self->htmlHeader(title => mt '_traiti_title');
  div class => 'mainbox';
   a class => 'addnew', href => "/i/new", mt '_traiti_create' if $self->authCan('charedit');
   h1 mt '_traiti_search';
   form action => '/i/list', 'accept-charset' => 'UTF-8', method => 'get';
    $self->htmlSearchBox('i', '');
   end;
  end;

  my $t = $self->dbTTTree(trait => 0, 2);
  childtags($self, mt('_traiti_tree'), 'i', {childs => $t}, 'order');

  table class => 'mainbox threelayout';
   Tr;

    # Recently added
    td;
     a class => 'right', href => '/i/list', mt '_traiti_browseall';
     my $r = $self->dbTraitGet(sort => 'added', reverse => 1, results => 10);
     h1 mt '_traiti_recent';
     ul;
      for (@$r) {
        li;
         txt $self->{l10n}->age($_->{added});
         txt ' ';
         b class => 'grayedout', $_->{groupname}.' / ' if $_->{group};
         a href => "/i$_->{id}", $_->{name};
        end;
      }
     end;
    end;

    # Popular
    td;
     h1 mt '_traiti_popular';
     ul;
      $r = $self->dbTraitGet(sort => 'items', reverse => 1, results => 10);
      for (@$r) {
        li;
         b class => 'grayedout', $_->{groupname}.' / ' if $_->{group};
         a href => "/i$_->{id}", $_->{name};
         txt " ($_->{c_items})";
        end;
      }
     end;
    end;

    # Moderation queue
    td;
     h1 mt '_traiti_queue';
     $r = $self->dbTraitGet(state => 0, sort => 'added', reverse => 1, results => 10);
     ul;
      li mt '_traiti_queue_empty' if !@$r;
      for (@$r) {
        li;
         txt $self->{l10n}->age($_->{added});
         txt ' ';
         b class => 'grayedout', $_->{groupname}.' / ' if $_->{group};
         a href => "/i$_->{id}", $_->{name};
        end;
      }
      li;
       br;
       a href => '/i/list?t=0;o=d;s=added', mt '_traiti_queue_link';
       txt ' - ';
       a href => '/i/list?t=1;o=d;s=added', mt '_traiti_denied';
      end;
     end;
    end;

   end 'tr';
  end 'table';
  $self->htmlFooter;
}


sub traitxml {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 'q', required => 0, maxlength => 500 },
    { get => 'id', required => 0, multi => 1, template => 'int' },
    { get => 'r', required => 0, default => 15, template => 'int', min => 1, max => 100 },
  );
  return $self->resNotFound if $f->{_err} || (!$f->{q} && !$f->{id} && !$f->{id}[0]);

  my($list, $np) = $self->dbTraitGet(
    !$f->{q} ? () : $f->{q} =~ /^i([1-9]\d*)/ ? (id => $1)  : (search => $f->{q}),
    $f->{id} && $f->{id}[0] ? (id => $f->{id}) : (),
    results => $f->{r},
    page => 1,
    sort => 'group'
  );

  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'traits', more => $np ? 'yes' : 'no';
   for(@$list) {
     tag 'item', id => $_->{id}, meta => $_->{meta} ? 'yes' : 'no', group => $_->{group}||'', groupname => $_->{groupname}||'', state => $_->{state}, $_->{name};
   }
  end;
}


1;


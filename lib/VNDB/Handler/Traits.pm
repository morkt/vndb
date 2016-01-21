
package VNDB::Handler::Traits;

use strict;
use warnings;
use TUWF ':html', ':xml', 'html_escape', 'xml_escape';
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
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 'm', required => 0, default => $self->authPref('spoilers')||0, enum => [qw|0 1 2|] },
    { get => 'fil', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

  my $title = sprintf '%s: %s', $t->{meta} ? 'Meta trait' : 'Trait', $t->{name};
  $self->htmlHeader(title => $title, noindex => $t->{state} != 2);
  $self->htmlMainTabs('i', $t);

  if($t->{state} != 2) {
    div class => 'mainbox';
     h1 $title;
     if($t->{state} == 1) {
       div class => 'warning';
        h2 'Trait deleted';
        p;
         txt 'This trait has been removed from the database, and cannot be used or re-added. File a request on the ';
         a href => '/t/db', 'discussion board';
         txt ' if you disagree with this.';
        end;
       end;
     } else {
       div class => 'notice';
        h2 'Waiting for approval';
        p 'This trait is waiting for a moderator to approve it.';
       end;
     }
    end 'div';
  }

  div class => 'mainbox';
   a class => 'addnew', href => "/i$trait/add", 'Create child trait' if $self->authCan('edit') && $t->{state} != 1;
   h1 $title;

   parenttags($t, 'Traits', 'i');

   if($t->{description}) {
     p class => 'description';
      lit bb2html $t->{description};
     end;
   }
   if($t->{sexual}) {
     p class => 'center';
      b 'Sexual content';
     end;
   }
   if($t->{alias}) {
     p class => 'center';
      b 'Aliases';
      br;
      lit html_escape($t->{alias});
     end;
   }
  end 'div';

  childtags($self, 'Child traits', 'i', $t) if @{$t->{childs}};

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
     h1 'Characters';

     p class => 'browseopts';
      a href => "/i$trait?m=0", $f->{m} == 0 ? (class => 'optselected') : (), 'Hide spoilers';
      a href => "/i$trait?m=1", $f->{m} == 1 ? (class => 'optselected') : (), 'Show minor spoilers';
      a href => "/i$trait?m=2", $f->{m} == 2 ? (class => 'optselected') : (), 'Spoil me!';
     end;

     p class => 'filselect';
      a id => 'filselect', href => '#c';
       lit '<i>&#9656;</i> Filters<i></i>';
      end;
     end;
     input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};

     if(!@$chars) {
       p; br; br; txt 'This trait has not been linked to any characters yet, or they were hidden because of your spoiler settings.'; end;
     }
     p; br; txt 'The list below also includes all characters linked to child traits. This list is cached, it can take up to 24 hours after a character has been edited for it to show up on this page.'; end;
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

  return $self->htmlDenied if !$self->authCan('edit') || $trait && !$self->authCan('tagmod');

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
      { post => 'order',       required => 0, default => 0, template => 'uint' },
    );
    my @parents = split /[\t ]+/, $frm->{parents};
    my $group = undef;
    if(!$frm->{_err}) {
      for(@parents) {
        my $c = $self->dbTraitGet(id => $_);
        push @{$frm->{_err}}, "Trait '$_' not found" if !@$c;
        $group //= $c->[0]{group}||$c->[0]{id} if @$c;
      }
    }
    if(!$frm->{_err}) {
      my @dups = @{$self->dbTraitGet(name => $frm->{name}, noid => $trait, group => $group)};
      push @dups, @{$self->dbTraitGet(name => $_, noid => $trait, group => $group)} for split /[\t\s]*\n[\t\s]*/, $frm->{alias};
      push @{$frm->{_err}}, \sprintf 'Trait <a href="/c%d">%s</a> already exists within the same group.', $_->{id}, xml_escape $_->{name} for @dups;
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

  my $title = $par ? "Add child trait to $par->{name}" : $t ? "Edit trait: $t->{name}" : 'Add new trait';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('i', $par || $t, 'edit') if $t || $par;

  if(!$self->authCan('tagmod')) {
    div class => 'mainbox';
     h1 'Requesting new trait';
     div class => 'notice';
      h2 'Your trait must be approved';
      p;
       lit 'Because all traits have to be approved by moderators, it can take a while before your trait will show up in the listings or can be used on character entries.';
      end;
     end;
    end;
  }

  $self->htmlForm({ frm => $frm, action => $par ? "/i$par->{id}/add" : $t ? "/i$trait/edit" : '/i/new' }, 'traitedit' => [ $title,
    [ input    => short => 'name',     name => 'Primary name' ],
    $self->authCan('tagmod') ? (
      $t ?
        [ static   => label => 'Added by', content => fmtuser($t->{addedby}, $t->{username}) ] : (),
      [ select   => short => 'state',    name => 'State', options => [
        [0,'Awaiting moderation'], [1,'Deleted/hidden'], [2,'Approved'] ] ],
      [ checkbox => short => 'meta',     name => 'This is a meta trait (only to be used as parent for other traits, not for direct use with characters)' ]
    ) : (),
    [ checkbox => short => 'sexual',   name => 'Indicates sexual content' ],
    [ textarea => short => 'alias',    name => "Aliases\n(Separated by newlines)", cols => 30, rows => 4 ],
    [ textarea => short => 'description', name => 'Description' ],
    [ input    => short => 'parents',  name => 'Parent traits' ],
    [ static   => content => 'List of trait IDs to be used as parent for this trait, separated by a space.' ],
    $self->authCan('tagmod') ? (
      [ input    => short => 'order', name => 'Group number', width => 50, post => ' (Only used if this trait is a group. Used for ordering, lowest first)' ],
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
    { get => 'p', required => 0, default => 1, template => 'page' },
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

  $self->htmlHeader(title => 'Browse traits');
  div class => 'mainbox';
   h1 'Browse traits';
   form action => '/i/list', 'accept-charset' => 'UTF-8', method => 'get';
    input type => 'hidden', name => 't', value => $f->{t};
    $self->htmlSearchBox('i', $f->{q});
   end;
   p class => 'browseopts';
    a href => "/i/list?q=$f->{q};t=-1", $f->{t} == -1 ? (class => 'optselected') : (), 'All';
    a href => "/i/list?q=$f->{q};t=0", $f->{t} == 0 ? (class => 'optselected') : (), 'Awaiting moderation';
    a href => "/i/list?q=$f->{q};t=1", $f->{t} == 1 ? (class => 'optselected') : (), 'Deleted';
    a href => "/i/list?q=$f->{q};t=2", $f->{t} == 2 ? (class => 'optselected') : (), 'Accepted';
   end;
   if(!@$t) {
     p 'No results found';
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
        [ 'Created', 'added' ],
        [ 'Trait',  'name'  ],
      ],
      row => sub {
        my($s, $n, $l) = @_;
        Tr;
         td class => 'tc1', fmtage $l->{added};
         td class => 'tc3';
          if($l->{group}) {
            b class => 'grayedout', $l->{groupname}.' / ';
          }
          a href => "/i$l->{id}", $l->{name};
          if($f->{t} == -1) {
            b class => 'grayedout', ' awaiting moderation' if $l->{state} == 0;
            b class => 'grayedout', ' deleted' if $l->{state} == 1;
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

  $self->htmlHeader(title => 'Trait index');
  div class => 'mainbox';
   a class => 'addnew', href => "/i/new", 'Create new trait' if $self->authCan('edit');
   h1 'Search traits';
   form action => '/i/list', 'accept-charset' => 'UTF-8', method => 'get';
    $self->htmlSearchBox('i', '');
   end;
  end;

  my $t = $self->dbTTTree(trait => 0, 2);
  childtags($self, 'Trait tree', 'i', {childs => $t}, 'order');

  table class => 'mainbox threelayout';
   Tr;

    # Recently added
    td;
     a class => 'right', href => '/i/list', 'Browse all traits';
     my $r = $self->dbTraitGet(sort => 'added', reverse => 1, results => 10);
     h1 'Recently added';
     ul;
      for (@$r) {
        li;
         txt fmtage $_->{added};
         txt ' ';
         b class => 'grayedout', $_->{groupname}.' / ' if $_->{group};
         a href => "/i$_->{id}", $_->{name};
        end;
      }
     end;
    end;

    # Popular
    td;
     h1 'Popular traits';
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
     h1 'Awaiting moderation';
     $r = $self->dbTraitGet(state => 0, sort => 'added', reverse => 1, results => 10);
     ul;
      li 'Moderation queue empty! yay!' if !@$r;
      for (@$r) {
        li;
         txt fmtage $_->{added};
         txt ' ';
         b class => 'grayedout', $_->{groupname}.' / ' if $_->{group};
         a href => "/i$_->{id}", $_->{name};
        end;
      }
      li;
       br;
       a href => '/i/list?t=0;o=d;s=added', 'Moderation queue';
       txt ' - ';
       a href => '/i/list?t=1;o=d;s=added', 'Denied traits';
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
    { get => 'id', required => 0, multi => 1, template => 'id' },
    { get => 'r', required => 0, default => 15, template => 'uint', min => 1, max => 200 },
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


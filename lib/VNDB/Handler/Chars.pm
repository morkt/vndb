
package VNDB::Handler::Chars;

use strict;
use warnings;
use TUWF ':html';
use VNDB::Func;


TUWF::register(
  qr{c([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{c(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit|/new)}
    => \&edit,
);


sub page {
  my($self, $id, $rev) = @_;

  my $r = $self->dbCharGet(
    id => $id,
    what => 'extended'.($rev ? ' changes' : ''),
    $rev ? ( rev => $rev ) : ()
  )->[0];
  return $self->resNotFound if !$r->{id};

  $self->htmlHeader(title => $r->{name});
  $self->htmlMainTabs(c => $r);
  return if $self->htmlHiddenMessage('c', $r);

  if($rev) {
    my $prev = $rev && $rev > 1 && $self->dbCharGet(id => $id, rev => $rev-1, what => 'changes extended')->[0];
    $self->htmlRevision('c', $prev, $r,
      [ name      => diff => 1 ],
      [ original  => diff => 1 ],
      [ alias     => diff => qr/[ ,\n\.]/ ],
      [ desc      => diff => qr/[ ,\n\.]/ ],
      [ image     => htmlize => sub {
        return $_[0] > 0 ? sprintf '<img src="%s/ch/%02d/%d.jpg" />', $self->{url_static}, $_[0]%100, $_[0]
          : mt $_[0] < 0 ? '_chdiff_image_proc' : '_chdiff_image_none';
      }],
    );
  }

  div class => 'mainbox';
   $self->htmlItemMessage('c', $r);
   h1 $r->{name};
   h2 class => 'alttitle', $r->{original} if $r->{original};

   div class => 'chardetails';

    # image
    div class => 'charimg';
     if(!$r->{image}) {
       p mt '_charp_noimg';
     } elsif($r->{image} < 0) {
       p mt '_charp_imgproc';
     } else {
       img src => sprintf('%s/ch/%02d/%d.jpg', $self->{url_static}, $r->{image}%100, $r->{image}),
         alt => $r->{name} if $r->{image};
     }
    end 'div';

    # info table
    table;
     my $i = 0;
     Tr ++$i % 2 ? (class => 'odd') : ();
      td class => 'key', mt '_charp_name';
      td $r->{name};
     end;
     if($r->{original}) {
       Tr ++$i % 2 ? (class => 'odd') : ();
        td mt '_charp_original';
        td $r->{original};
       end;
     }
     if($r->{alias}) {
       $r->{alias} =~ s/\n/, /g;
       Tr ++$i % 2 ? (class => 'odd') : ();
        td mt '_charp_alias';
        td $r->{alias};
       end;
     }
     if($r->{desc}) {
       Tr;
        td class => 'chardesc', colspan => 2;
         h2 mt '_charp_description';
         p;
          lit bb2html $r->{desc};
         end;
        end;
       end;
     }
    end 'table';

   end;
   clearfloat;

  end;
  $self->htmlFooter;
}



sub edit {
  my($self, $id, $rev) = @_;

  my $r = $id && $self->dbCharGet(id => $id, what => 'changes extended', $rev ? (rev => $rev) : ())->[0];
  return $self->resNotFound if $id && !$r->{id};
  $rev = undef if !$r || $r->{cid} == $r->{latest};

  return $self->htmlDenied if !$self->authCan('charedit')
    || $id && ($r->{locked} && !$self->authCan('lock') || $r->{hidden} && !$self->authCan('del'));

  my %b4 = !$id ? () : (
    (map { $_ => $r->{$_} } qw|name original alias desc image ihid ilock|),
  );
  my $frm;

  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'name',          maxlength => 200 },
      { post => 'original',      required  => 0, maxlength => 200,  default => '' },
      { post => 'alias',         required  => 0, maxlength => 500,  default => '' },
      { post => 'desc',          required  => 0, maxlength => 5000, default => '' },
      { post => 'image',         required  => 0, default => 0,  template => 'int' },
      { post => 'editsum',       required  => 0, maxlength => 5000 },
      { post => 'ihid',          required  => 0 },
      { post => 'ilock',         required  => 0 },
    );
    push @{$frm->{_err}}, 'badeditsum' if !$frm->{editsum} || lc($frm->{editsum}) eq lc($frm->{desc});

    # handle image upload
    $frm->{image} = _uploadimage($self, $r, $frm);

    if(!$frm->{_err}) {
      $frm->{ihid}  = $frm->{ihid} ?1:0;
      $frm->{ilock} = $frm->{ilock}?1:0;

      return $self->resRedirect("/c$id", 'post')
        if $id && !grep $frm->{$_} ne $b4{$_}, keys %b4;

      my $nrev = $self->dbItemEdit(c => $id ? $r->{cid} : undef, %$frm);
      return $self->resRedirect("/c$nrev->{iid}.$nrev->{rev}", 'post');
    }
  }

  $frm->{$_} //= $b4{$_} for keys %b4;
  $frm->{editsum} //= sprintf 'Reverted to revision c%d.%d', $id, $rev if $rev;

  my $title = mt $r ? ('_chare_title_edit', $r->{name}) : '_chare_title_add';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('c', $r, 'edit') if $r;
  $self->htmlEditMessage('c', $r, $title);
  $self->htmlForm({ frm => $frm, action => $r ? "/c$id/edit" : '/c/new', editsum => 1, upload => 1 },
  chare_geninfo => [ mt('_chare_form_generalinfo'),
    [ input  => name => mt('_chare_form_name'), short => 'name' ],
    [ input  => name => mt('_chare_form_original'), short => 'original' ],
    [ static => content => mt('_chare_form_original_note') ],
    [ text   => name => mt('_chare_form_alias'), short => 'alias', rows => 3 ],
    [ static => content => mt('_chare_form_alias_note') ],
    [ text   => name => mt('_chare_form_desc').'<br /><b class="standout">'.mt('_inenglish').'</b>', short => 'desc', rows => 6 ],
  ],

  chare_img => [ mt('_chare_image'), [ static => nolabel => 1, content => sub {
    div class => 'img';
     p mt '_chare_image_none' if !$frm->{image};
     p mt '_chare_image_processing' if $frm->{image} && $frm->{image} < 0;
     img src => sprintf("%s/ch/%02d/%d.jpg", $self->{url_static}, $frm->{image}%100, $frm->{image}) if $frm->{image} && $frm->{image} > 0;
    end;

    div;
     h2 mt '_chare_image_id';
     input type => 'text', class => 'text', name => 'image', id => 'image', value => $frm->{image};
     p mt '_chare_image_id_msg';
     br; br;

     h2 mt '_chare_image_upload';
     input type => 'file', class => 'text', name => 'img', id => 'img';
     p mt('_chare_image_upload_msg');
    end;
  }]]);
  $self->htmlFooter;
}


sub _uploadimage {
  my($self, $c, $frm) = @_;
  return $c ? $frm->{image} : 0 if $frm->{_err} || !$self->reqPost('img');

  # perform some elementary checks
  my $imgdata = $self->reqUploadRaw('img');
  $frm->{_err} = [ 'noimage' ] if $imgdata !~ /^(\xff\xd8|\x89\x50)/; # JPG or PNG headers
  $frm->{_err} = [ 'toolarge' ] if length($imgdata) > 1024*1024;
  return undef if $frm->{_err};

  # get image ID and save it, to be processed by Multi
  my $imgid = $self->dbCharImageId;
  my $fn = sprintf '%s/static/ch/%02d/%d.jpg', $VNDB::ROOT, $imgid%100, $imgid;
  $self->reqSaveUpload('img', $fn);
  chmod 0666, $fn;

  return -1*$imgid;
}


1;


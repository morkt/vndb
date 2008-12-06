
package VNDB::Util::FormHTML;

use strict;
use warnings;
use YAWF ':html';
use Exporter 'import';

our @EXPORT = qw| htmlFormError htmlFormPart htmlForm |;


# form error messages
my %formerr_names = (
  alias         => 'Aliases',
  anime         => 'Anime',
  desc          => 'Description',
  editsum       => 'Edit summary',
  gtin          => 'JAN/EAN/UPC',
  lang          => 'Language',
  language      => 'Language',
  length        => 'Length',
  l_wp          => 'Wikipedia link',
  l_encubed     => 'Novelnews link',
  l_renai       => 'Renai.us link',
  l_vnn         => 'V-N.net link',
  mail          => 'Email',
  media         => 'Media',
  minage        => 'Age rating',
  msg           => 'Message',
  name          => 'Name',
  notes         => 'Notes',
  original      => 'Original',
  platforms     => 'Platforms',
  producers     => 'Producers',
  released      => 'Release date',
  tags          => 'Tags',
  title         => 'Title',
  type          => 'Type',
  usrname       => 'Username',
  usrpass       => 'Password',
  usrpass2      => 'Password (confirm)',
  vn            => 'Visual novels',
  website       => 'Website',
);
my %formerr_exeptions = (
  login_failed  => 'Invalid username or password',
  nomail        => 'No user found with that email address',
  passmatch     => 'Passwords do not match',
  usrexists     => 'Someone already has this username, please choose something else',
  mailexists    => 'Someone already registered with that email address',
  noimage       => 'Image must be in JPEG or PNG format',
  toolarge      => 'Image is too large, only 50kB allowed',
);


# Displays friendly error message when form validation failed
# Argument is the return value of formValidate, and an optional
# argument indicating whether we should create a special mainbox
# for the errors.
sub htmlFormError {
  my($self, $frm, $mainbox) = @_;
  return if !$frm->{_err};
  if($mainbox) {
    div class => 'mainbox';
     h1 'Error';
  }
  div class => 'warning';
   h2 'Form could not be sent:';
   ul;
    for my $e (@{$frm->{_err}}) {
      if(!ref $e) {
        li $formerr_exeptions{$e};
        next;
      }
      my($field, $type, $rule) = @$e;
      $field = $formerr_names{$field}||$field;
      li sprintf '%s is a required field!', $field if $type eq 'required';
      li sprintf '%s should have at least %d characters', $field, $rule if $type eq 'minlength';
      li sprintf '%s: only %d characters allowed', $field, $rule if $type eq 'maxlength';
      li sprintf '%s must be one of the following: %s', $field, join ', ', @$rule if $type eq 'enum';
      li sprintf 'Wrong tag: %s', $rule if $type eq 'wrongtag';
      li $rule->[1] if $type eq 'func' || $type eq 'regex';
      if($type eq 'template') {
        li sprintf
          $rule eq 'mail'       ? 'Invalid email address' :
          $rule eq 'url'        ? '%s: Invalid URL' :
          $rule eq 'asciiprint' ? '%s may only contain ASCII characters' :
          $rule eq 'int'        ? '%s: Not a valid number' :
          $rule eq 'pname'      ? '%s can only contain lowercase alphanumberic characters and a hyphen, and must start with a character' : '',
          $field;
      }
    }
   end;
  end;
  end if $mainbox;
}


# Generates a form part.
# A form part is a arrayref, with the first element being the type of the part,
# and all other elements forming a hash with options specific to that type.
# Type      Options
#  hidden    short, (value)
#  input     short, name, (width, pre, post)
#  passwd    short, name
#  static    content, (label, nolabel)
#  check     name, short, (value)
#  select    name, short, options, (width)
#  text      name, short, (rows, cols)
#  part      title
# TODO: Find a way to write this function in a readable way...
sub htmlFormPart {
  my($self, $frm, $fp) = @_;
  my($type, %o) = @$fp;
  local $_ = $type;

  if(/hidden/) {
    Tr class => 'hidden';
     td colspan => 2;
      input type => 'hidden', id => $o{short}, name => $o{short}, value => $o{value}||$frm->{$o{short}}||'';
     end;
    end;
    return
  }

  if(/part/) {
    Tr class => 'newpart';
     td colspan => 2, $o{title};
    end;
    return;
  }

  if(/check/) {
    Tr class => 'newfield';
     td class => 'label';
      lit '&nbsp;';
     end;
     td class => 'field';
      input type => 'checkbox', class => 'checkbox', name => $o{short}, id => $o{short},
        value => $o{value}||'true', $frm->{$o{short}} ? ( checked => 'checked' ) : ();
      label for => $o{short};
       lit $o{name};
      end;
     end;
    end;
    return;
  }

  Tr $o{name}||$o{label} ? (class => 'newfield') : ();
   if(!$o{nolabel}) {
     td class => 'label';
      if($o{short} && $o{name}) {
        label for => $o{short}, $o{name} ;
      } elsif($o{label}) {
        txt $o{label};
      } else {
        lit '&nbsp;';
      }
     end;
   }
   td class => 'field', $o{nolabel} ? (colspan => 2) : ();
    if(/input/) {
      lit $o{pre} if $o{pre};
      input type => 'text', class => 'text', name => $o{short}, id => $o{short},
        value => $frm->{$o{short}}||'', $o{width} ? (style => "width: $o{width}px") : ();
      lit $o{post} if $o{post};
    }
    if(/passwd/) {
      input type => 'password', class => 'text', name => $o{short}, id => $o{short},
        value => $frm->{$o{short}}||'';
    }
    if(/static/) {
      lit ref $o{content} eq 'CODE' ? $o{content}->($self, \%o) : $o{content};
    }
    if(/select/) {
      Select name => $o{short}, id => $o{short}, $o{width} ? (style => "width: $o{width}px") : ();
       option value => $_->[0], defined $frm->{$o{short}} && $frm->{$o{short}} eq $_->[0] ? (selected => 'selected') : (), $_->[1]
         for @{$o{options}};
      end;
    }
    if(/text/) {
      (my $txt = $frm->{$o{short}}||'') =~ s/&/&amp;/;
      $txt =~ s/</&lt;/;
      $txt =~ s/>/&gt;/;
      textarea name => $o{short}, id => $o{short}, rows => $o{rows}||5, cols => $o{cols}||60;
       lit $txt;
      end;
    }
   end;
  end;
}


# Generates a form, first argument is a hashref with global options, keys:
#   frm     => the $frm as returned by formValidate,
#   action  => The location the form should POST to
#   upload  => 1/0, adds an enctype.
#   editsum => 1/0, adds an edit summary field before the submit button
# The other arguments are a list of subforms in the form
# of (subform-name => [form parts]). Each subform is shown as a
# (JavaScript-powered) tab, and has it's own 'mainbox'. This function
# automatically calls htmlFormError
sub htmlForm {
  my($self, $options, @subs) = @_;
  form action => '/nospam?'.$options->{action}, method => 'post', 'accept-charset' => 'utf-8',
    $options->{upload} ? (enctype => 'multipart/form-data') : ();

  $self->htmlFormError($options->{frm}, 1);

  # tabs
  if(@subs > 2) {
    ul class => 'maintabs notfirst', id => 'jt_select';
     for (0..$#subs/2) {
       (my $short = lc $subs[$_*2]) =~ s/[^\w\d]+/_/;
       li class => 'left';
        a href => "#$short", id => "jt_sel_$short", $subs[$_*2];
       end;
     }
    end;
  }

  # form subs
  while(my($name, $parts) = (shift(@subs), shift(@subs))) {
    last if !$name || !$parts;
    (my $short = lc $name) =~ s/[^\w\d]+/_/;
    div class => 'mainbox', id => 'jt_box_'.$short;
     h1 $name;
     fieldset;
      legend $name;
      table class => 'formtable';
       $self->htmlFormPart($options->{frm}, $_) for @$parts;
      end;
     end;
    end;
  }

  # edit summary / submit button
  div class => 'mainbox';
   fieldset class => 'submit';
    if($options->{editsum}) {
      (my $txt = $options->{frm}{editsum}||'') =~ s/&/&amp;/;
      $txt =~ s/</&lt;/;
      $txt =~ s/>/&gt;/;
      h2 'Edit summary';
      textarea name => 'editsum', id => 'editsum', rows => 4, cols => 50;
       lit $txt;
      end;
      br;
    }
    input type => 'submit', value => 'Submit', class => 'submit';
   end;
  end; 

  end;
}


1;


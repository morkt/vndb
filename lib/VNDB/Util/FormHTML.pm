
package VNDB::Util::FormHTML;

use strict;
use warnings;
use YAWF ':html';
use Exporter 'import';

our @EXPORT = qw| htmlFormError htmlFormPart htmlFormSub htmlForm |;


# form error messages
my %formerr_names = (
  usrname       => 'Username',
  usrpass       => 'Password',
  usrpass2      => 'Password (confirm)',
  mail          => 'Email',
);
my %formerr_exeptions = (
  login_failed  => 'Invalid username or password',
  nomail        => 'No user found with that email address',
  passmatch     => 'Passwords do not match',
  usrexists     => 'Someone already has this username, please choose something else',
  mailexists    => 'Someone already registerd with that email address',
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
   h2 'Form could not be send:';
   ul;
    for my $e (@{$frm->{_err}}) {
      if(!ref $e) {
        li $formerr_exeptions{$e};
        next;
      }
      my($field, $type, $rule) = @$e;
      $field = $formerr_names{$field};
      li sprintf '%s is a required field!', $field if $type eq 'required';
      li sprintf '%s should have at least %d characters', $field, $rule if $type eq 'minlength';
      li sprintf '%s: only %d characters allowed', $field, $rule if $type eq 'maxlength';
      li sprintf '%s must be one of the following: %s', $field, join ', ', @$rule if $type eq 'enum';
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
  if($mainbox) {
     end;
    end;
  }
}


# Generates a form part.
# A form part is a arrayref, with the first element being the type of the part,
# and all other elements forming a hash with options specific to that type.
# Type      Options
#  input     short, name, width
#  passwd    short, name
#  static    content
sub htmlFormPart {
  my($self, $frm, $fp) = @_;
  my($type, %o) = @$fp;
  local $_ = $type;
  Tr !/static/ ? (class => 'newfield') : ();
   td class => 'label';
    label for => $o{short}, $o{name} if $o{short} && $o{name};
    lit '&nbsp;' if !$o{short} || !$o{name};
   end;
   td class => 'field';
    if(/input/) {
      input type => 'text', class => 'text', name => $o{short}, id => $o{short},
        value => $frm->{$o{short}}||'', $o{width} ? (style => "width: $o{width}px") : ();
    }
    if(/passwd/) {
      input type => 'password', class => 'text', name => $o{short}, id => $o{short},
        value => $frm->{$o{short}}||'';
    }
    if(/static/) {
      lit $o{content};
    }
   end;
  end;
}


sub htmlFormSub {
  my($self, $frm, $name, $parts) = @_;
  fieldset;
   legend $name;
   table class => 'formtable';
    $self->htmlFormPart($frm, $_) for @$parts;
   end;
  end;
}


# Generates a form, first argument is a hashref with global options, keys:
#   frm    => the $frm as returned by formValidate,
#   action => The location the form should POST to
#   upload => 1/0, adds an enctype.
# The other arguments are a list of subforms in the form
# of (subform-name => [form parts]). Each subform is shown as a
# (JavaScript-powered) tab, if only one subform is specified, no tabs
# are shown and no 'mainbox' is generated. Otherwise, each subform has
# it's own 'mainbox'. This function automatically calls htmlFormError,
# and creates a separate mainbox for that if multiple subforms are specified.
sub htmlForm {
  my($self, $options, @subs) = @_;
  form action => '/nospam?'.$options->{action}, method => 'post', 'accept-charset' => 'utf-8',
    $options->{upload} ? (enctype => 'multipart/form-data') : ();
  if(@subs == 2) {
    $self->htmlFormError($options->{frm});
    $self->htmlFormSub($options->{frm}, @subs);
    fieldset class => 'submit';
     input type => 'submit', value => 'Submit', class => 'submit';
    end;
  } else {
    $self->htmlFormError($options->{frm}, 1);
    # tabs here...
    while(my($name, $parts) = (shift(@subs), shift(@subs))) {
      last if !$name || !$parts;
      (my $short = lc $name) =~ s/ /_/;
      div class => 'mainbox subform', id => 'subform_'.$short;
       h1 $name;
       $self->htmlFormSub($options->{frm}, $name, $parts);
      end;
    }
    div class => 'mainbox';
     fieldset class => 'submit';
      input type => 'submit', value => 'Submit', class => 'submit';
     end;
    end; 
  }
  end;
}


1;


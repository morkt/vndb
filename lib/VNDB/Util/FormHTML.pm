
package VNDB::Util::FormHTML;

use strict;
use warnings;
use YAWF ':html';
use Exporter 'import';
use POSIX 'strftime';
use VNDB::Func;

our @EXPORT = qw| htmlFormError htmlFormPart htmlForm |;


# Displays friendly error message when form validation failed
# Argument is the return value of formValidate, and an optional
# argument indicating whether we should create a special mainbox
# for the errors.
sub htmlFormError {
  my($self, $frm, $mainbox) = @_;
  return if !$frm->{_err};
  if($mainbox) {
    div class => 'mainbox';
     h1 mt '_formerr_title';
  }
  div class => 'warning';
   h2 mt '_formerr_subtitle';
   ul;
    for my $e (@{$frm->{_err}}) {
      if(!ref $e) {
        li mt '_formerr_e_'.$e;
        next;
      }
      my($field, $type, $rule) = @$e;
      li mt '_formerr_required', $field if $type eq 'required';
      li mt '_formerr_minlength', $field, $rule if $type eq 'minlength';
      li mt '_formerr_maxlength', $field, $rule if $type eq 'maxlength';
      li mt '_formerr_enum', $field, join ', ', @$rule if $type eq 'enum';
      li mt '_formerr_wrongboard', $rule if $type eq 'wrongboard';
      li mt '_formerr_tagexists', "/g$rule->{id}", $rule->{name} if $type eq 'tagexists';
      li $rule->[1] if $type eq 'func' || $type eq 'regex';
      li mt "_formerr_tpl_$rule", $field if $type eq 'template';
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
#  select    name, short, options, (width, multi, size)
#  radio     name, short, options
#  text      name, short, (rows, cols)
#  date      name, short
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
      input type => 'checkbox', name => $o{short}, id => $o{short},
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
        label for => $o{short};
         lit $o{name};
        end;
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
      my $l='';
      Select name => $o{short}, id => $o{short}, $o{width} ? (style => "width: $o{width}px") : (), $o{multi} ? (multiple => 'multiple', size => $o{size}||5) : ();
       for my $p (@{$o{options}}) {
         if($p->[2] && $l ne $p->[2]) {
           end if $l;
           $l = $p->[2];
           optgroup label => $l;
         }
         my $sel = defined $frm->{$o{short}} && ($frm->{$o{short}} eq $p->[0] || ref($frm->{$o{short}}) eq 'ARRAY' && grep $_ eq $p->[0], @{$frm->{$o{short}}});
         option value => $p->[0], $sel ? (selected => 'selected') : (), $p->[1];
       }
       end if $l;
      end;
    }
    if(/radio/) {
      for my $p (@{$o{options}}) {
        input type => 'radio', id => "$o{short}_$p->[0]", name => $o{short}, value => $p->[0],
          defined $frm->{$o{short}} && $frm->{$o{short}} eq $p->[0] ? (checked => 'checked') : ();
        label for => "$o{short}_$p->[0]", $p->[1];
      }
    }
    if(/date/) {
      input type => 'hidden', id => $o{short}, name => $o{short}, value => $frm->{$o{short}}||'', class => 'dateinput';
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
       li class => 'left';
        a href => "#$subs[$_*2]", id => "jt_sel_$subs[$_*2]", $subs[$_*2+1][0];
       end;
     }
     li class => 'left';
      a href => '#all', id => 'jt_sel_all', mt '_form_tab_all';
     end;
    end;
  }

  # form subs
  while(my($short, $parts) = (shift(@subs), shift(@subs))) {
    last if !$short || !$parts;
    my $name = shift @$parts;
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

  # db mod / edit summary / submit button
  if(!$options->{nosubmit}) {
    div class => 'mainbox';
     fieldset class => 'submit';
      if($options->{editsum}) {
        # hidden / locked checkbox
        if($self->authCan('del')) {
          input type => 'checkbox', name => 'ihid', id => 'ihid', value => 1, $options->{frm}{ihid} ? (checked => 'checked') : ();
          label for => 'ihid', mt '_form_ihid';
        }
        if($self->authCan('lock')) {
          input type => 'checkbox', name => 'ilock', id => 'ilock', value => 1, $options->{frm}{ilock} ? (checked => 'checked') : ();
          label for => 'ilock', mt '_form_ilock';
        }
        txt "\n".mt('_form_hidlock_note')."\n" if $self->authCan('lock') || $self->authCan('del');

        # edit summary
        (my $txt = $options->{frm}{editsum}||'') =~ s/&/&amp;/;
        $txt =~ s/</&lt;/;
        $txt =~ s/>/&gt;/;
        h2;
         txt mt '_form_editsum';
         b class => 'standout', ' ('.mt('_inenglish').')';
        end;
        textarea name => 'editsum', id => 'editsum', rows => 4, cols => 50;
         lit $txt;
        end;
        br;
      }
      input type => 'submit', value => mt('_form_submit'), class => 'submit';
     end;
    end;
  }

  end;
}


1;


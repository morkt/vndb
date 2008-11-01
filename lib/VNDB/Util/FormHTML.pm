
package VNDB::Util::FormHTML;

use strict;
use warnings;
use YAWF ':html';
use Exporter 'import';

our @EXPORT = 'htmlFormError';


# form error messages
my %formerr_names = (
  usrname       => 'Username',
  usrpass       => 'Password',
);
my %formerr_exeptions = (
  login_failed  => 'Invalid username or password',
);


# Displays friendly error message when form validation failed
# Argument is the return value of formValidate
sub htmlFormError { # $frm
  my($self, $frm) = @_;
  return if !$frm->{_err};
  div class => 'formerr';
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
          $rule eq 'pname'      ? '%s can only contain alphanumberic characters and a hyphen, and must start with a character' : '',
          $field;
      }
    }
   end;
  end;
}


1;

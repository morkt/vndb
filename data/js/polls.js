// Discussion board polls
if(byId('jt_box_postedit') && byId('poll')) {
  var c = byId('poll');
  var parentNode = function(n, tag) {
    while(n && n.nodeName.toLowerCase() != tag)
      n = n.parentNode;
    return n;
  };
  var show = function(v) {
    setClass(parentNode(byId('poll_question'),    'tr'), 'hidden', !v);
    setClass(parentNode(byId('poll_options'),     'tr'), 'hidden', !v);
    setClass(parentNode(byId('poll_max_options'), 'tr'), 'hidden', !v);
    setClass(parentNode(byId('poll_preview'),     'tr'), 'hidden', !v);
    setClass(parentNode(byId('poll_recast'),      'tr'), 'hidden', !v);
  };
  c.onclick = function() {
    show(this.checked);
    return true;
  };
  show(c.checked);
}

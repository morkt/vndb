function addPoll() {
  var a = byId('poll_add');
  setClass(a, 'hidden', false);
  var parentNode = function(n, tag) {
    while(n && n.nodeName.toLowerCase() != tag)
      n = n.parentNode;
    return n;
  };
  var show = function(v) {
    setClass(parentNode(byId('poll_q'),      'tr'), 'hidden', !v);
    setClass(parentNode(byId('poll_opt'),    'tr'), 'hidden', !v);
    setClass(parentNode(byId('poll_max'),    'tr'), 'hidden', !v);
    setClass(parentNode(byId('poll_preview'),'tr'), 'hidden', !v);
    setClass(parentNode(byId('poll_recast'), 'tr'), 'hidden', !v);
    setClass(parentNode(a, 'tr'), 'hidden', v);
  };
  a.onclick = function() {
    show(true);
    return true;
  };
  show(false);
}

// Discussion board polls
if(byId('poll_add'))
  addPoll();

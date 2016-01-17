function dropdown(lnk) {
  var relid = lnk.id.substr(6);
  var st = getText(lnk);
  if(st == 'Loading...')
    return null;

  var o = tag('ul', null);
  for(var i=0; i<VARS.rlist_status.length; i++) {
    var val = VARS.rlist_status[i];
    o.appendChild(tag('li', st == val
      ? tag('i', val)
      : tag('a', {href:'#', rl_rid:relid, rl_act:i, onclick:change}, val)));
  }
  if(st != '--')
    o.appendChild(tag('li', tag('a', {href:'#', rl_rid:relid, rl_act:-1, onclick:change}, 'Remove from list')));

  return tag('div', o);
}

function change() {
  var lnk = byId('rlsel_'+this.rl_rid);
  var code = getText(byId('vnrlist_code'));
  var act = this.rl_act;
  ddHide();
  setContent(lnk, tag('b', {'class': 'grayedout'}, 'Loading...'));
  ajax('/xml/rlist.xml?formcode='+code+';id='+this.rl_rid+';e='+act, function(hr) {
    setText(lnk, act == -1 ? '--' : VARS.rlist_status[act]);
  });
  return false;
}

if(byId('vnrlist_code')) {
  var l = byClass('a', 'vnrlsel');
  for(var i=0; i<l.length; i++)
    ddInit(l[i], 'left', dropdown);
}

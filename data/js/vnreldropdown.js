function rlDropDown(lnk) {
  var relid = lnk.id.substr(6);
  var st = getText(lnk);
  if(st == mt('_js_loading'))
    return null;

  var o = tag('ul', null);
  for(var i=0; i<VARS.rlist_status.length; i++) {
    var val = VARS.rlist_status[i] == 0 ? mt('_unknown') : mt('_rlist_status_'+VARS.rlist_status[i]); // l10n /_rlist_status_\d+/
    if(st == val)
      o.appendChild(tag('li', tag('i', val)));
    else
      o.appendChild(tag('li', tag('a', {href:'#', rl_rid:relid, rl_act:VARS.rlist_status[i], onclick:rlMod}, val)));
  }
  if(st != '--')
    o.appendChild(tag('li', tag('a', {href:'#', rl_rid:relid, rl_act:-1, onclick:rlMod}, mt('_vnpage_uopt_reldel'))));

  return tag('div', o);
}

function rlMod() {
  var lnk = byId('rlsel_'+this.rl_rid);
  var code = getText(byId('vnrlist_code'));
  var act = this.rl_act;
  ddHide();
  setContent(lnk, tag('b', {'class': 'grayedout'}, mt('_js_loading')));
  ajax('/xml/rlist.xml?formcode='+code+';id='+this.rl_rid+';e='+act, function(hr) {
    setText(lnk, act == -1 ? '--' : act == 0 ? mt('_unknown') : mt('_rlist_status_'+act));
  });
  return false;
}

if(byId('vnrlist_code')) {
  var l = byClass('a', 'vnrlsel');
  for(var i=0;i<l.length;i++)
    ddInit(l[i], 'left', rlDropDown);
}

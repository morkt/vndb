function salLoad () {
  byId('alias_tbl').appendChild(tag('tr', {id:'alias_new'},
    tag('td', null),
    tag('td', {colspan:3}, tag('a', {href:'#', onclick:salFormAdd}, 'Add alias'))));

  salAdd(byId('primary').value||0, byId('name').value, byId('original').value);
  var aliases = jsonParse(byId('aliases').value) || [];
  for(var i = 0; i < aliases.length; i++) {
    salAdd(aliases[i].aid, aliases[i].name, aliases[i].orig);
  }

  byName(byId('maincontent'), 'form')[0].onsubmit = salSerialize;
}

function salAdd(aid, name, original) {
  var tbl = byId('alias_tbl');
  var first = tbl.rows.length <= 1;
  tbl.insertBefore(tag('tr', first ? {id:'primary_name'} : null,
    tag('td', {'class':'tc_id' },
      tag('input', {type:'radio', name:'primary_id', value:aid, checked:first, onchange:salPrimary})),
    tag('td', {'class':'tc_name' },     tag('input', {type:'text', 'class':'text', value:name})),
    tag('td', {'class':'tc_original' }, tag('input', {type:'text', 'class':'text', value:original})),
    tag('td', {'class':'tc_add' }, !first ?
      tag('a', {href:'#', onclick:salDel}, 'remove') : null)
  ), byId('alias_new'));
}

function salPrimary() {
  var prev = byId('primary_name')
  prev.removeAttribute('id');
  byClass(prev, 'td', 'tc_add')[0].appendChild(tag('a', {href:'#', onclick:salDel}, 'remove'));
  var tr = this;
  while (tr && tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  tr.setAttribute('id', 'primary_name');
  var td = byClass(tr, 'td', 'tc_add')[0];
  while (td.firstChild)
    td.removeChild(td.firstChild);

  return salSerialize();
}

function salSerialize() {
  var tbl = byName(byId('alias_tbl'), 'tr');
  var a = [];
  for (var i = 0; i < tbl.length; ++i) {
    if(tbl[i].id == 'alias_new')
      continue;
    var id   = byName(byClass(tbl[i], 'td', 'tc_id')[0], 'input')[0].value;
    var name = byName(byClass(tbl[i], 'td', 'tc_name')[0], 'input')[0].value;
    var orig = byName(byClass(tbl[i], 'td', 'tc_original')[0], 'input')[0].value;
    if(tbl[i].id == 'primary_name') {
      byId('name').value = name;
      byId('original').value = orig;
      byId('primary').value = id;
    } else
      a.push({ aid:Number(id), name:name, orig:orig });
  }
  byId('aliases').value = JSON.stringify(a);
  return true;
}

function salDel() {
  var tr = this;
  while (tr && tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  var tbl = byId('alias_tbl');
  tbl.removeChild(tr);
  salSerialize();
  return false;
}

function salFormAdd() {
  salAdd(0, '', '');
  byName(byClass(byId('alias_new').previousSibling, 'td', 'tc_name')[0], 'input')[0].focus();
  return false;
}

if(byId('jt_box_staffe_geninfo'))
  salLoad();

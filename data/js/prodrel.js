function prrLoad() {
  // read the current relations
  var rels = byId('prodrelations').value.split('|||');
  for(var i=0; i<rels.length && rels[0].length>1; i++) {
    var rel = rels[i].split(',', 3);
    prrAdd(rel[0], rel[1], rel[2]);
  }
  prrEmpty();

  // bind the add-link
  byName(byClass(byId('relation_new'), 'td', 'tc_add')[0], 'a')[0].onclick = prrFormAdd;

  // dropdown
  dsInit(byName(byClass(byId('relation_new'), 'td', 'tc_prod')[0], 'input')[0], '/xml/producers.xml?q=', function(item, tr) {
    tr.appendChild(tag('td', { style: 'text-align: right; padding-right: 5px'}, 'p'+item.getAttribute('id')));
    tr.appendChild(tag('td', shorten(item.firstChild.nodeValue, 40)));
  }, function(item) {
    return 'p'+item.getAttribute('id')+':'+item.firstChild.nodeValue;
  }, prrFormAdd);
}

function prrAdd(rel, pid, title) {
  var sel = tag('select', {onchange: prrSerialize});
  var ops = byName(byClass(byId('relation_new'), 'td', 'tc_rel')[0], 'select')[0].options;
  for(var i=0; i<ops.length; i++)
    sel.appendChild(tag('option', {value: ops[i].value, selected: ops[i].value==rel}, getText(ops[i])));

  byId('relation_tbl').appendChild(tag('tr', {id:'relation_tr_'+pid},
    tag('td', {'class':'tc_prod' }, 'p'+pid+':', tag('a', {href:'/p'+pid}, shorten(title, 40))),
    tag('td', {'class':'tc_rel'  }, sel),
    tag('td', {'class':'tc_add'  }, tag('a', {href:'#', onclick:prrDel}, mt('_js_remove')))
  ));

  prrEmpty();
}

function prrEmpty() {
  var tbl = byId('relation_tbl');
  if(byName(tbl, 'tr').length < 1)
    tbl.appendChild(tag('tr', {id:'relation_tr_none'}, tag('td', {colspan:4}, mt('_pedit_rel_none'))));
  else if(byId('relation_tr_none'))
    tbl.removeChild(byId('relation_tr_none'));
}

function prrSerialize() {
  var r = [];
  var trs = byName(byId('relation_tbl'), 'tr');
  for(var i=0; i<trs.length; i++) {
    if(trs[i].id == 'relation_tr_none')
      continue;
    var rel = byName(byClass(trs[i], 'td', 'tc_rel')[0], 'select')[0];
    r[r.length] = [
      rel.options[rel.selectedIndex].value,
      trs[i].id.substr(12),
      getText(byName(byClass(trs[i], 'td', 'tc_prod')[0], 'a')[0])
    ].join(',');
  }
  byId('prodrelations').value = r.join('|||');
}

function prrDel() {
  var tr = this;
  while(tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  byId('relation_tbl').removeChild(tr);
  prrSerialize();
  prrEmpty();
  return false;
}

function prrFormAdd() {
  var relnew = byId('relation_new');
  var txt = byName(byClass(relnew, 'td', 'tc_prod')[0], 'input')[0];
  var sel = byName(byClass(relnew, 'td', 'tc_rel')[0],  'select')[0];
  var lnk = byName(byClass(relnew, 'td', 'tc_add')[0],  'a')[0];
  var input = txt.value;

  if(!input.match(/^p[0-9]+/)) {
    alert(mt('_pedit_rel_findformat'));
    return false;
  }

  txt.disabled = sel.disabled = true;
  txt.value = mt('_js_loading');
  setText(lnk, mt('_js_loading'));

  ajax('/xml/producers.xml?q='+encodeURIComponent(input), function(hr) {
    txt.disabled = sel.disabled = false;
    txt.value = '';
    setText(lnk, mt('_js_add'));

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert(mt('_pedit_rel_notfound'));

    var id = items[0].getAttribute('id');
    if(byId('relation_tr_'+id))
      return alert(mt('_pedit_rel_double'));

    prrAdd(sel.options[sel.selectedIndex].value, id, items[0].firstChild.nodeValue);
    sel.selectedIndex = 0;
    prrSerialize();
  });
  return false;
}

if(byId('prodrelations'))
  prrLoad();

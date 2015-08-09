function vnrLoad() {
  // read the current relations
  var rels = byId('vnrelations').value.split('|||');
  for(var i=0; i<rels.length && rels[0].length>1; i++) {
    var rel = rels[i].split(',', 4);
    vnrAdd(rel[0], rel[1], rel[2]==1?true:false, rel[3]);
  }
  vnrEmpty();

  // make sure the title is up-to-date
  byId('title').onchange = function() {
    var l = byClass(byId('jt_box_vn_rel'), 'td', 'tc_title');
    for(i=0; i<l.length; i++)
      setText(l[i], shorten(this.value, 40));
  };

  // bind the add-link
  byName(byClass(byId('relation_new'), 'td', 'tc_add')[0], 'a')[0].onclick = vnrFormAdd;

  // dropdown
  dsInit(byName(byClass(byId('relation_new'), 'td', 'tc_vn')[0], 'input')[0], '/xml/vn.xml?q=', function(item, tr) {
    tr.appendChild(tag('td', { style: 'text-align: right; padding-right: 5px'}, 'v'+item.getAttribute('id')));
    tr.appendChild(tag('td', shorten(item.firstChild.nodeValue, 40)));
  }, function(item) {
    return 'v'+item.getAttribute('id')+':'+item.firstChild.nodeValue;
  }, vnrFormAdd);
}

function vnrAdd(rel, vid, official, title) {
  var sel = tag('select', {onchange: vnrSerialize});
  var ops = byName(byClass(byId('relation_new'), 'td', 'tc_rel')[0], 'select')[0].options;
  for(var i=0; i<ops.length; i++)
    sel.appendChild(tag('option', {value: ops[i].value, selected: ops[i].value==rel}, getText(ops[i])));

  byId('relation_tbl').appendChild(tag('tr', {id:'relation_tr_'+vid},
    tag('td', {'class':'tc_vn'   }, 'v'+vid+':', tag('a', {href:'/v'+vid}, shorten(title, 40))),
    tag('td', {'class':'tc_rel'  },
      mt('_vnedit_rel_isa')+' ',
      tag('input', {type: 'checkbox', onclick:vnrSerialize, id:'official_'+vid, checked:official}),
      tag('label', {'for':'official_'+vid}, mt('_vnedit_rel_official')),
      sel, ' '+mt('_vnedit_rel_of')),
    tag('td', {'class':'tc_title'}, shorten(byId('title').value, 40)),
    tag('td', {'class':'tc_add'  }, tag('a', {href:'#', onclick:vnrDel}, mt('_js_remove')))
  ));

  vnrEmpty();
}

function vnrEmpty() {
  var tbl = byId('relation_tbl');
  if(byName(tbl, 'tr').length < 1)
    tbl.appendChild(tag('tr', {id:'relation_tr_none'}, tag('td', {colspan:4}, mt('_vnedit_rel_none'))));
  else if(byId('relation_tr_none'))
    tbl.removeChild(byId('relation_tr_none'));
}

function vnrSerialize() {
  var r = [];
  var trs = byName(byId('relation_tbl'), 'tr');
  for(var i=0; i<trs.length; i++) {
    if(trs[i].id == 'relation_tr_none')
      continue;
    var rel = byName(byClass(trs[i], 'td', 'tc_rel')[0], 'select')[0];
    r[r.length] = [
      rel.options[rel.selectedIndex].value,                      // relation
      trs[i].id.substr(12),                                      // vid
      byName(byClass(trs[i], 'td', 'tc_rel')[0], 'input')[0].checked ? '1' : '0', // official
      getText(byName(byClass(trs[i], 'td', 'tc_vn')[0], 'a')[0]) // title
    ].join(',');
  }
  byId('vnrelations').value = r.join('|||');
}

function vnrDel() {
  var tr = this;
  while(tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  byId('relation_tbl').removeChild(tr);
  vnrSerialize();
  vnrEmpty();
  return false;
}

function vnrFormAdd() {
  var relnew = byId('relation_new');
  var txt = byName(byClass(relnew, 'td', 'tc_vn')[0], 'input')[0];
  var off = byName(byClass(relnew, 'td', 'tc_rel')[0], 'input')[0];
  var sel = byName(byClass(relnew, 'td', 'tc_rel')[0], 'select')[0];
  var lnk = byName(byClass(relnew, 'td', 'tc_add')[0], 'a')[0];
  var input = txt.value;

  if(!input.match(/^v[0-9]+/)) {
    alert(mt('_vnedit_rel_findformat'));
    return false;
  }

  txt.disabled = sel.disabled = off.disabled = true;
  txt.value = mt('_js_loading');
  setText(lnk, mt('_js_loading'));

  ajax('/xml/vn.xml?q='+encodeURIComponent(input), function(hr) {
    txt.disabled = sel.disabled = off.disabled = false;
    txt.value = '';
    setText(lnk, mt('_js_add'));

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert(mt('_vnedit_rel_novn'));

    var id = items[0].getAttribute('id');
    if(byId('relation_tr_'+id))
      return alert(mt('_vnedit_rel_double'));

    vnrAdd(sel.options[sel.selectedIndex].value, id, off.checked, items[0].firstChild.nodeValue);
    sel.selectedIndex = 0;
    vnrSerialize();
  });
  return false;
}

if(byId('vnrelations'))
  vnrLoad();

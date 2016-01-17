function rprLoad() {
  var ps = byId('producers').value.split('|||');
  for(var i=0; i<ps.length && ps[i].length>1; i++) {
    var val = ps[i].split(',',3);
    rprAdd(val[0], val[1], val[2]);
  }
  rprEmpty();

  dsInit(byId('producer_input'), '/xml/producers.xml?q=',
    function(item, tr) {
      tr.appendChild(tag('td', {style:'text-align: right; padding-right: 5px'}, 'p'+item.getAttribute('id')));
      tr.appendChild(tag('td', shorten(item.firstChild.nodeValue, 40)));
    }, function(item) {
      return 'p'+item.getAttribute('id')+':'+item.firstChild.nodeValue;
    },
    rprFormAdd
  );
  byId('producer_add').onclick = rprFormAdd;
}

function rprAdd(id, role, name) {
  var roles = byId('producer_role').options;
  var rl = tag('select', {onchange:rprSerialize});
  for(var i=0; i<roles.length; i++)
    rl.appendChild(tag('option', {value: roles[i].value, selected:role==roles[i].value}, getText(roles[i])));

  byId('producer_tbl').appendChild(tag('tr', {id:'rpr_'+id, rpr_id:id},
    tag('td', {'class':'tc_name'}, 'p'+id+':', tag('a', {href:'/p'+id}, shorten(name, 40))),
    tag('td', {'class':'tc_role'}, rl),
    tag('td', {'class':'tc_rm'},   tag('a', {href:'#', onclick:rprDel}, 'remove'))
  ));
  rprEmpty();
}

function rprDel() {
  var tr = this;
  while(tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  tr.parentNode.removeChild(tr);
  rprEmpty();
  rprSerialize();
  return false;
}

function rprEmpty() {
  var tbl = byId('producer_tbl');
  if(byName(tbl, 'tr').length < 1)
    tbl.appendChild(tag('tr', {id:'rpr_tr_none'}, tag('td', {colspan:2}, 'Nothing selected.')));
  else if(byId('rpr_tr_none'))
    tbl.removeChild(byId('rpr_tr_none'));
}

function rprFormAdd() {
  var txt = byId('producer_input');
  var lnk = byId('producer_add');
  var val = txt.value;

  if(!val.match(/^p[0-9]+/)) {
    alert('Producer textbox must start with an ID (e.g. p17)');
    return false;
  }

  txt.disabled = true;
  txt.value = 'Loading...';
  setText(lnk, 'Loading...');

  ajax('/xml/producers.xml?q='+encodeURIComponent(val), function(hr) {
    txt.disabled = false;
    txt.value = '';
    setText(lnk, 'add');

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert('Producer not found!');

    var id = items[0].getAttribute('id');
    if(byId('rpr_'+id))
      return alert('Producer already selected!');

    var role = byId('producer_role');
    role = role[role.selectedIndex].value;

    rprAdd(id, role, items[0].firstChild.nodeValue);
    rprSerialize();
  });
  return false;
}

function rprSerialize() {
  var r = [];
  var l = byName(byId('producer_tbl'), 'tr');
  for(var i=0; i<l.length; i++)
    if(l[i].rpr_id) {
      var role = byName(byClass(l[i], 'td', 'tc_role')[0], 'select')[0];
      r[r.length] = [
        l[i].rpr_id,
        role.options[role.selectedIndex].value,
        getText(byName(byClass(l[i], 'td', 'tc_name')[0], 'a')[0])
      ].join(',');
    }
  byId('producers').value = r.join('|||');
}

if(byId('jt_box_rel_prod'))
  rprLoad();

function rvnLoad() {
  var vns = byId('vn').value.split('|||');
  for(var i=0; i<vns.length && vns[i].length>1; i++)
    rvnAdd(vns[i].split(',',2)[0], vns[i].split(',',2)[1]);
  rvnEmpty();

  dsInit(byId('vn_input'), '/xml/vn.xml?q=',
    function(item, tr) {
      tr.appendChild(tag('td', {style:'text-align: right; padding-right: 5px'}, 'v'+item.getAttribute('id')));
      tr.appendChild(tag('td', shorten(item.firstChild.nodeValue, 40)));
    }, function(item) {
      return 'v'+item.getAttribute('id')+':'+item.firstChild.nodeValue;
    },
    rvnFormAdd
  );
  byId('vn_add').onclick = rvnFormAdd;
}

function rvnAdd(id, title) {
  byId('vn_tbl').appendChild(tag('tr', {id:'rvn_'+id, rvn_id:id},
    tag('td', {'class':'tc_title'}, 'v'+id+':', tag('a', {href:'/v'+id}, shorten(title, 40))),
    tag('td', {'class':'tc_rm'},    tag('a', {href:'#', onclick:rvnDel}, 'remove'))
  ));
  rvnEmpty();
}

function rvnDel() {
  var tr = this;
  while(tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  tr.parentNode.removeChild(tr);
  rvnEmpty();
  rvnSerialize();
  return false;
}

function rvnEmpty() {
  var tbl = byId('vn_tbl');
  if(byName(tbl, 'tr').length < 1)
    tbl.appendChild(tag('tr', {id:'rvn_tr_none'}, tag('td', {colspan:2}, 'Nothing selected.')));
  else if(byId('rvn_tr_none'))
    tbl.removeChild(byId('rvn_tr_none'));
}

function rvnFormAdd() {
  var txt = byId('vn_input');
  var lnk = byId('vn_add');
  var val = txt.value;

  if(!val.match(/^v[0-9]+/)) {
    alert('Visual novel textbox must start with an ID (e.g. v17)');
    return false;
  }

  txt.disabled = true;
  txt.value = 'Loading...';
  setText(lnk, 'Loading...');

  ajax('/xml/vn.xml?q='+encodeURIComponent(val), function(hr) {
    txt.disabled = false;
    txt.value = '';
    setText(lnk, 'add');

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert('Visual novel not found!');

    var id = items[0].getAttribute('id');
    if(byId('rvn_'+id))
      return alert('VN already selected!');

    rvnAdd(id, items[0].firstChild.nodeValue);
    rvnSerialize();
  });
  return false;
}

function rvnSerialize() {
  var r = [];
  var l = byName(byId('vn_tbl'), 'tr');
  for(var i=0; i<l.length; i++)
    if(l[i].rvn_id)
      r[r.length] = l[i].rvn_id + ',' + getText(byName(byClass(l[i], 'td', 'tc_title')[0], 'a')[0]);
  byId('vn').value = r.join('|||');
}

if(byId('jt_box_rel_vn'))
  rvnLoad();

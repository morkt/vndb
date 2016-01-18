function ctrLoad() {
  // load current traits
  var l = byId('traits').value.split(' ');
  var v = {}; // tag id -> spoiler lookup table
  var q = []; // list of id=X parameters
  for(var i=0; i<l.length; i++) {
    if(l[i]) {
      var m = l[i].split(/-/);
      v[m[0]] = Math.floor(m[1]);
      q[i] = 'id='+m[0];
    }
  }
  if(q.length > 0)
    ajax('/xml/traits.xml?r=200;'+q.join(';'), function (ht) {
      var t = ht.responseXML.getElementsByTagName('item');
      for(var i=0; i<t.length; i++)
        ctrAdd(t[i], v[t[i].getAttribute('id')]);
    }, 1);
  else
    ctrEmpty();

  // dropdown
  dsInit(byId('trait_input'), '/xml/traits.xml?q=', function(item, tr) {
    var g = item.getAttribute('groupname');
    g = g ? g+' / ' : '';
    tr.appendChild(tag('td', { style: 'text-align: right; padding-right: 5px'}, 'i'+item.getAttribute('id')));
    tr.appendChild(tag('td',
      tag('b', {'class':'grayedout'}, g), item.firstChild.nodeValue,
      tag('b', {'class':'grayedout'}, item.getAttribute('meta')=='yes' ? 'meta' : '')));
  }, ctrFormAdd);
}

function ctrEmpty() {
  var x = byId('traits_loading');
  var t = byId('traits_tbl');
  if(x)
    t.removeChild(x);
  var l = byName(t, 'tr');
  var e = byId('traits_empty');
  if(e && l.length > 1)
    t.removeChild(e);
  else if(!e && l.length < 1)
    t.appendChild(tag('tr', {id:'traits_empty',colspan:3}, tag('td', 'No traits present yet.')));
}

function ctrAdd(item, spoil) {
  var id = item.getAttribute('id');
  var name = item.firstChild.nodeValue;
  var group = item.getAttribute('groupname');
  var sp = tag('td', {'class':'tc_spoil', onclick:ctrSpoilNext, ctr_spoil:spoil}, fmtspoil(spoil));
  ddInit(sp, 'left', ctrSpoilDD);
  byId('traits_tbl').appendChild(tag('tr', {ctr_id:id, ctr_spoiler:spoil},
    tag('td', {'class':'tc_name'},
      tag('b', {'class':'grayedout'}, group?group+' / ':''),
      tag('a', {'href':'/i'+id}, name)),
    sp,
    tag('td', {'class':'tc_del'}, tag('a', {href:'#', onclick:ctrDel}, 'remove'))
  ));
  ctrEmpty();
  ctrSerialize();
}

function ctrFormAdd(item) {
  var l = byName(byId('traits_tbl'), 'tr');
  for(var i=0; i<l.length; i++)
    if(l[i].ctr_id && l[i].ctr_id == item.getAttribute('id'))
      break;
  if(i < l.length)
    alert('Selected trait is already present.');
  else if(item.getAttribute('meta') == 'yes')
    alert('Meta traits can\'t be used here.');
  else
    ctrAdd(item, 0);
  return '';
}

function ctrSpoilNext() {
  if(++this.ctr_spoil > 2)
    this.ctr_spoil = 0;
  setText(this, fmtspoil(this.ctr_spoil));
  ddRefresh();
  ctrSerialize();
}

function ctrSpoilDD(lnk) {
  var lst = tag('ul', null);
  for(var i=0; i<=2; i++)
    lst.appendChild(tag('li', i == lnk.ctr_spoil
      ? tag('i', fmtspoil(i))
      : tag('a', {href: '#', onclick:ctrSpoilSet, ctr_td:lnk, ctr_sp:i}, fmtspoil(i))
    ));
  return lst;
}

function ctrSpoilSet() {
  this.ctr_td.ctr_spoil = this.ctr_sp;
  setText(this.ctr_td, fmtspoil(this.ctr_sp));
  ddHide();
  ctrSerialize();
  return false;
}

function ctrDel() {
  var tr = this;
  while(tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  tr.parentNode.removeChild(tr);
  ctrEmpty();
  ctrSerialize();
  return false
}

function ctrSerialize() {
  var l = byName(byId('traits_tbl'), 'tr');
  var v = [];
  for(var i=0; i<l.length; i++)
    if(l[i].ctr_id)
      v.push(l[i].ctr_id+'-'+byClass(l[i], 'tc_spoil')[0].ctr_spoil);
  byId('traits').value = v.join(' ');
}

if(byId('traits_tbl'))
  ctrLoad();

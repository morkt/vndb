function cvnLoad() {
  // load current links
  var l = byId('vns').value.split(' ');
  var v = {}; // vid -> { rid: [ role, spoil ], .. }
  var q = []; // list of v=X parameters
  for(var i=0; i<l.length; i++) {
    if(!l[i])
      continue;
    var m = l[i].split(/-/); // vid, rid, spoil, role
    if(!v[m[0]]) {
      q.push('v='+m[0]);
      v[m[0]] = {};
    }
    v[m[0]][m[1]] = [ m[3], m[2] ];
  }
  if(q.length > 0)
    ajax('/xml/releases.xml?'+q.join(';'), function(hr) {
      var vns = byName(hr.responseXML, 'vn');
      for(var i=0; i<vns.length; i++) {
        var vid = vns[i].getAttribute('id');
        cvnVNAdd(vns[i]);
        var rels = byName(vns[i], 'release');
        for(var r=0; r<rels.length; r++) {
          var rid = rels[r].getAttribute('id');
          if(v[vid][rid])
            cvnRelAdd(vid, rid, v[vid][rid][0], v[vid][rid][1]);
        }
        if(v[vid][0])
          cvnRelAdd(vid, 0, v[vid][0][0], v[vid][0][1]);
      }
      cvnEmpty();
    }, 1);
  else
    cvnEmpty();

  // dropdown search
  dsInit(byId('vns_input'), '/xml/vn.xml?q=', function(item, tr) {
    tr.appendChild(tag('td', { style: 'text-align: right; padding-right: 5px'}, 'v'+item.getAttribute('id')));
    tr.appendChild(tag('td', shorten(item.firstChild.nodeValue, 40)));
  }, cvnFormAdd);
}

function cvnEmpty() {
  var x = byId('vns_loading');
  var t = byId('vns_tbl');
  if(x)
    t.removeChild(x);
  var l = byName(t, 'tr');
  var e = byId('vns_empty');
  if(e && l.length > 1)
    t.removeChild(e);
  else if(!e && l.length < 1)
    t.appendChild(tag('tr', {id:'vns_empty',colspan:3}, tag('td', 'No visual novels selected.')));
}

function cvnVNAdd(vn, rel) {
  var vid = vn.getAttribute('id');
  var rels = byName(vn, 'release');
  byId('vns_tbl').appendChild(tag('tr', {id:'cvn_v'+vid, cvn_vid:vid, cvn_rels:rels},
    tag('td', {'class':'tc_vn',colspan:4}, 'v'+vid+':',
      tag('a', {href:'/v'+vid}, vn.getAttribute('title')),
      tag('i', '(', tag('a', {href:'#', onclick:cvnRelNew}, 'add release'), ')')
    )
  ));
  if(rel)
    cvnRelAdd(vid, 0, 'primary', 0);
  cvnEmpty();
}

function cvnRelAdd(vid, rid, role, spoil) {
  var rels = byId('cvn_v'+vid).cvn_rels;
  var rsel = tag('select', {onchange:cvnRelChange}, tag('option', {value:0}, 'All / others'));
  for(var i=0; i<rels.length; i++) {
    var id = rels[i].getAttribute('id');
    rsel.appendChild(tag('option', {value: id, selected:id==rid},
      '['+rels[i].getAttribute('lang')+'] '+rels[i].firstChild.nodeValue+' (r'+id+')'));
  }

  var lsel = tag('select', {onchange:cvnSerialize});
  for(var i=0; i<VARS.char_roles.length; i++)
    lsel.appendChild(tag('option', {value: VARS.char_roles[i][0], selected:VARS.char_roles[i][0]==role}, VARS.char_roles[i][1]));

  var ssel = tag('select', {onchange:cvnSerialize});
  for(var i=0; i<3; i++)
    ssel.appendChild(tag('option', {value:i, selected:i==spoil}, fmtspoil(i)));

  var tbl = byId('vns_tbl');
  var l = byName(tbl, 'tr');
  var last = null;
  for(var i=1; i<l.length; i++)
    if(l[i-1].cvn_vid == vid && l[i].cvn_vid != vid)
      last = l[i-1];
  tbl.insertBefore(tag('tr', {id:'cvn_v'+vid+'r'+rid, cvn_vid:vid, cvn_rid:rid},
    tag('td', {'class':'tc_rel'}, rsel),
    tag('td', {'class':'tc_rol'}, lsel),
    tag('td', {'class':'tc_spl'}, ssel),
    tag('td', {'class':'tc_del'}, tag('a', {href:'#', onclick:cvnRelDel}, 'remove'))
  ), last);
}

function cvnRelChange() {
  // look for duplicates and disallow the change
  var val = this.options[this.selectedIndex].value;
  var tr = this;
  while(tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  if(byId('cvn_v'+tr.cvn_vid+'r'+val)) {
    alert('Release already present.');
    for(var i=0; i<this.options.length; i++)
      this.options[i].selected = this.options[i].value == tr.cvn_rid;
    return;
  }
  // otherwise, 'rename' this entry
  tr.id = 'cvn_v'+tr.cvn_vid+'r'+val;
  tr.cvn_rid = val;
  cvnSerialize();
}

function cvnRelNew() {
  var tr = this;
  while(tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  var id = 0;
  if(byId('cvn_v'+tr.cvn_vid+'r0')) {
    for(var i=0; i<tr.cvn_rels.length; i++) {
      id = tr.cvn_rels[i].getAttribute('id');
      if(!byId('cvn_v'+tr.cvn_vid+'r'+id))
        break;
    }
    if(i == tr.cvn_rels.length) {
      alert('All releases already selected.');
      return false;
    }
  }
  cvnRelAdd(tr.cvn_vid, id, 'primary', 0);
  cvnSerialize();
  return false;
}

function cvnRelDel() {
  var tbl = byId('vns_tbl');
  var tr = this;
  while(tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  tbl.removeChild(tr);
  var l = byName(tbl, 'tr');
  var c = 0;
  for(var i=0; i<l.length; i++)
    if(l[i].cvn_vid == tr.cvn_vid)
      c++;
  if(c <= 1)
    tbl.removeChild(byId('cvn_v'+tr.cvn_vid));
  cvnSerialize();
  cvnEmpty();
  return false;
}

function cvnFormAdd(item) {
  var inpt = byId('vns_input');
  inpt.disabled = true;

  ajax('/xml/releases.xml?v='+item.getAttribute('id'), function(hr) {
    inpt.disabled = false;
    inpt.value = '';

    var items = byName(hr.responseXML, 'vn');
    if(items.length < 1) // shouldn't happen
      return alert('Oops! Error!');

    var id = items[0].getAttribute('id');
    if(byId('cvn_v'+id))
      return alert('VN already present.');
    cvnVNAdd(items[0], 1);
    cvnSerialize();
  }, 1);
  return 'Loading...';
}

function cvnSerialize() {
  var l = byName(byId('vns_tbl'), 'tr');
  var v = [];
  for(var i=0; i<l.length; i++)
    if(l[i].cvn_rid != null) {
      var rol = byName(byClass(l[i], 'tc_rol')[0], 'select')[0];
      var spl = byName(byClass(l[i], 'tc_spl')[0], 'select')[0];
      v.push(l[i].cvn_vid+'-'+l[i].cvn_rid+'-'+
          spl.options[spl.selectedIndex].value+'-'+
          rol.options[rol.selectedIndex].value);
    }
  byId('vns').value = v.join(' ');
}

if(byId('jt_box_chare_vns'))
  cvnLoad();

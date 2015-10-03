// vnsStaffData maps alias id to staff data { NNN: { id: ..., aid: NNN, name: ...} }
// used to fill form fields instead of ajax queries in vnsLoad() and vncLoad()
// Also used by vncast.js
window.vnsStaffData = {};

function vnsLoad() {
  window.vnsStaffData = jsonParse(getText(byId('staffdata'))) || {};
  var credits = jsonParse(byId('credits').value) || [];
  for(var i = 0; i < credits.length; i++) {
    var aid = credits[i].aid;
    if(window.vnsStaffData[aid])
      vnsAdd(window.vnsStaffData[aid], credits[i].role, credits[i].note);
  }
  vnsEmpty();

  onSubmit(byName(byId('maincontent'), 'form')[0], vnsSerialize);

  // dropdown search
  dsInit(byId('credit_input'), '/xml/staff.xml?q=', function(item, tr) {
    tr.appendChild(tag('td', { style: 'text-align: right; padding-right: 5px'}, 's'+item.getAttribute('id')));
    tr.appendChild(tag('td', item.firstChild.nodeValue));
  }, vnsFormAdd);
}

function vnsAdd(staff, role, note) {
  var tbl = byId('credits_tbl');

  var rlist = tag('select', {onchange:vnsSerialize});
  var r = VARS.staff_roles;
  for (var i = 0; i<r.length; i++)
    rlist.appendChild(tag('option', {value:r[i][0], selected:r[i][0]==role}, r[i][1]));

  tbl.appendChild(tag('tr', {id:'vns_a'+staff.aid},
    tag('td', {'class':'tc_name'},
      tag('input', {type:'hidden', value:staff.aid}),
      tag('a', {href:'/s'+staff.id}, staff.name)),
    tag('td', {'class':'tc_role'}, rlist),
    tag('td', {'class':'tc_note'}, tag('input', {type:'text', 'class':'text', value:note})),
    tag('td', {'class':'tc_del'}, tag('a', {href:'#', onclick:vnsDel}, mt('_js_remove')))
  ));
  vnsEmpty();
  vnsSerialize();
}

function vnsEmpty() {
  var x = byId('credits_loading');
  var tbody = byId('credits_tbl');
  var tbl = tbody.parentNode;
  var thead = byName(tbl, 'thead');
  if(x)
    tbody.removeChild(x);
  if(byName(tbody, 'tr').length < 1) {
    tbody.appendChild(tag('tr', {id:'credits_tr_none'},
      tag('td', {colspan:4}, mt('_vnstaffe_none'))));
    if (thead.length)
      tbl.removeChild(thead[0]);
  } else {
    if(byId('credits_tr_none'))
      tbody.removeChild(byId('credits_tr_none'));
    if (thead.length < 1) {
      thead = tag('thead', tag('tr',
        tag('td', {'class':'tc_name'}, mt('_vnstaffe_form_staff')),
        tag('td', {'class':'tc_role'}, mt('_vnstaffe_form_role')),
        tag('td', {'class':'tc_note'}, mt('_vnstaffe_form_note')),
        tag('td', '')));
      tbl.insertBefore(thead, tbody);
    }
  }
}

function vnsSerialize() {
  var l = byName(byId('credits_tbl'), 'tr');
  var c = [];
  for (var i = 0; i < l.length; i++) {
    if(l[i].id == 'credits_tr_none')
      continue;
    var aid  = byName(byClass(l[i], 'tc_name')[0], 'input')[0];
    var role = byName(byClass(l[i], 'tc_role')[0], 'select')[0];
    var note = byName(byClass(l[i], 'tc_note')[0], 'input')[0];
    c.push({ aid:Number(aid.value), role:role.value, note:note.value });
  }
  byId('credits').value = JSON.stringify(c);
  return true;
}

function vnsDel() {
  var tr = this;
  while (tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  byId('credits_tbl').removeChild(tr);
  vnsEmpty();
  vnsSerialize();
  return false;
}

function vnsFormAdd(item) {
  var s = { id:item.getAttribute('id'), aid:item.getAttribute('aid'), name:item.firstChild.nodeValue };
  vnsAdd(s, 'staff', '');
  return '';
}

if(byId('jt_box_vn_staff'))
  vnsLoad();

var scrRel = [ [ 0, mt('_vnedit_scr_selrel') ] ];
var scrStaticURL;
var scrUplNr = 0;
var scrDefRel;

function scrLoad() {
  // get scrRel and scrStaticURL
  var rel = byId('scr_rel');
  scrStaticURL = rel.className;
  for(var i=0; i<rel.options.length; i++)
    scrRel[scrRel.length] = [ rel.options[i].value, getText(rel.options[i]) ];
  rel.parentNode.removeChild(rel);
  if(scrRel.length <= 2)
    scrRel.shift();
  scrDefRel = scrRel[0][0];

  // load the current screenshots
  var scr = byId('screenshots').value.split(' ');
  var siz = byId('screensizes').value.split(' ');
  for(i=0; i<scr.length && scr[i].length>1; i++) {
    var r = scr[i].split(',');
    var s = siz[i].split(',');
    scrSet(scrAdd(r[0], r[1], r[2]), s[0], s[1]);
  }

  ivInit();
  scrLast();
  scrSetSubmit();
}

function scrSetSubmit() {
  var frm = byId('screenshots');
  while(frm.nodeName.toLowerCase() != 'form')
    frm = frm.parentNode;
  onSubmit(frm, function() {
    var loading = 0;
    var norelease = 0;
    var l = byName(byId('scr_table'), 'tr');
    for(var i=0; i<l.length-1; i++) {
      var rel = byName(l[i], 'select')[0];
      if(l[i].scr_status > 0)
        loading = 1;
      else if(rel.options[rel.selectedIndex].value == 0)
        norelease = 1;
    }
    if(loading) {
      alert(mt('_vnedit_scr_frmloading'));
      return false;
    } else if(norelease) {
      alert(mt('_vnedit_scr_frmnorel'));
      return false;
    }
    return true;
  });
}

function scrURL(id, t) {
  return scrStaticURL+'/s'+t+'/'+(id%100<10?'0':'')+(id%100)+'/'+id+'.jpg';
}

function scrAdd(id, nsfw, rel) {
  // tr.scr_status = 0: done, 1: uploading

  var tr = tag('tr', { id:'scr_tr_'+id, scr_id: id, scr_status: 1, scr_rel: rel, scr_nsfw: nsfw},
    tag('td', { 'class': 'thumb'}, mt('_js_loading')),
    tag('td',
      tag('b', mt('_vnedit_scr_uploading')),
      tag('br', null),
      id ? null : mt('_vnedit_scr_upl_msg'),
      tag('br', null),
      id ? null : tag('a', {href:'#', onclick:scrDel}, mt('_vnedit_scr_cancel'))
    )
  );
  byId('scr_table').appendChild(tr);
  return tr;
}

function scrSet(tr, width, height) {
  var dim = width+'x'+height;
  tr.scr_status = 0;

  // image
  setContent(byName(tr, 'td')[0],
    tag('a', {href: scrURL(tr.scr_id, 'f'), rel:'iv:'+dim+':edit'},
      tag('img', {src: scrURL(tr.scr_id, 't')})
    )
  );

  // check full resolution with the list of DB-defined resolutions
  var odd = true;
  if(dim == '256x384') // special-case NDS resolution (not in the DB)
    odd = false;
  for(var j=0; j<VARS.resolutions.length && odd; j++) {
    if(typeof VARS.resolutions[j][1] != 'object') {
      if(VARS.resolutions[j][0] == dim)
        odd = false;
    } else {
      for(var k=1; k<VARS.resolutions[j].length; k++)
        if(VARS.resolutions[j][k][1] == dim)
          odd = false;
    }
  }

  // content
  var rel = tag('select', {onchange: scrSerialize, 'class':'scr_relsel'});
  for(var j=0; j<scrRel.length; j++)
    rel.appendChild(tag('option', {value: scrRel[j][0], selected: tr.scr_rel == scrRel[j][0]}, scrRel[j][1]));
  var nsfwid = 'scr_sfw_'+tr.scr_id;
  setContent(byName(tr, 'td')[1],
    tag('b', mt('_vnedit_scr_id', tr.scr_id)),
    ' (', tag('a', {href: '#', onclick:scrDel}, mt('_js_remove')), ')',
    tag('br', null),
    mt('_vnedit_scr_fullsize', dim),
    odd ? tag('b', {'class':'standout', 'style':'font-weight: bold'}, ' '+mt('_vnedit_scr_nonstandard')) : null,
    tag('br', null),
    tag('br', null),
    tag('input', {type:'checkbox', onclick:scrSerialize, id:nsfwid, name:nsfwid, checked: tr.scr_nsfw>0, 'class':'scr_nsfw'}),
    tag('label', {'for':nsfwid}, mt('_vnedit_scr_nsfw')),
    tag('br', null),
    rel
  );
}

function scrLast() {
  if(byId('scr_last'))
    byId('scr_table').removeChild(byId('scr_last'));
  var full = byName(byId('scr_table'), 'tr').length >= 10;

  var rel = tag('select', {onchange: function(){scrDefRel=this.options[this.selectedIndex].value}, 'class':'scr_relsel', 'id':'scradd_relsel'});
  for(var j=0; j<scrRel.length; j++)
    rel.appendChild(tag('option', {value: scrRel[j][0], selected: scrDefRel == scrRel[j][0]}, scrRel[j][1]));

  byId('scr_table').appendChild(tag('tr', {id:'scr_last'},
    tag('td', {'class': 'thumb'}),
    full ? tag('td',
      tag('b', mt('_vnedit_scr_full')),
      tag('br', null),
      mt('_vnedit_scr_full_msg')
    ) : tag('td',
      tag('b', mt('_vnedit_scr_add')),
      tag('br', null),
      mt('_vnedit_scr_imgnote'),
      tag('br', null),
      rel,
      tag('br', null),
      tag('input', {name:'scr_upload', id:'scr_upload', type:'file', 'class':'text'}),
      tag('br', null),
      tag('input', {type:'button', value:mt('_vnedit_scr_addbut'), 'class':'submit', onclick:scrUpload})
    )
  ));
}

function scrDel(what) {
  var tr = what && what.scr_status != null ? what : this;
  while(tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  tr.scr_status = null;
  if(tr.scr_upl && byId(tr.scr_upl))
    byId(tr.scr_upl).parentNode.removeChild(byId(tr.scr_upl));
  byId('scr_table').removeChild(tr);
  scrSerialize();
  scrLast();
  ivInit();
  return false;
}

function scrUpload() {
  scrUplNr++;

  // create temporary form
  var ifid = 'scr_upl_'+scrUplNr;
  var frm = tag('form', {method: 'post', action:'/xml/screenshots.xml?upload='+scrUplNr,
    target: ifid, enctype:'multipart/form-data'});
  var ifr = tag('iframe', {id:ifid, name:ifid, src:'about:blank', onload:scrUploadComplete});
  addBody(tag('div', {'class':'scr_uploader'}, ifr, frm));

  // submit form
  var upl = byId('scr_upload');
  upl.id = upl.name = 'scr_upl_file_'+scrUplNr;
  frm.appendChild(upl);
  frm.submit();
  ifr.scr_tr = scrAdd(0, 0, 0);
  ifr.scr_upl = ifid;
  ifr.scr_tr.scr_rel = byId('scradd_relsel').options[byId('scradd_relsel').selectedIndex].value;
  scrLast();
  return false;
}

function scrUploadComplete() {
  var ifr = this;
  var fr = window.frames[ifr.id];
  if(fr.location.href.indexOf('screenshots') < 0)
    return;

  var tr = ifr.scr_tr;
  if(tr && tr.scr_status == 1) {
    try {
      tr.scr_id = fr.window.document.getElementsByTagName('image')[0].getAttribute('id');
    } catch(e) {
      tr.scr_id = -10;
    }
    if(tr.scr_id < 0) {
      alert(tr.scr_id == -10 ? mt('_vnedit_scr_oops') :
            tr.scr_id ==  -1 ? mt('_vnedit_scr_errformat') : mt('_vnedit_scr_errempty'));
      scrDel(tr);
    } else {
      tr.id = 'scr_tr_'+tr.scr_id;
      scrSet(tr, fr.window.document.getElementsByTagName('image')[0].getAttribute('width'), fr.window.document.getElementsByTagName('image')[0].getAttribute('height'));
      scrSerialize();
      ivInit();
    }
  }

  tr.scr_upl = null;
  /* remove the <div> in a timeout, otherwise some browsers think the page is still loading */
  setTimeout(function() { ifr.parentNode.parentNode.removeChild(ifr.parentNode) }, 1000);
}

function scrSerialize() {
  var r = [];
  var l = byName(byId('scr_table'), 'tr');
  for(var i=0; i<l.length-1; i++)
    if(l[i].scr_status == 0)
      r[r.length] = [
        l[i].scr_id,
        byClass(l[i], 'input', 'scr_nsfw')[0].checked ? 1 : 0,
        scrRel[byClass(l[i], 'select', 'scr_relsel')[0].selectedIndex][0]
      ].join(',');
  byId('screenshots').value = r.join(' ');
}

if(byId('jt_box_vn_scr') && byId('scr_table'))
  scrLoad();

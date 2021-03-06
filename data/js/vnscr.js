var rels;
var defRid = 0;
var staticUrl;

function init() {
  var data = jsonParse(getText(byId('screendata'))) || {};
  rels = data.rel;
  rels.unshift([ 0, '-- select release --' ]);
  staticUrl = data.staticurl;

  var scr = jsonParse(byId('screenshots').value) || {};
  for(i=0; i<scr.length; i++) {
    var r = scr[i];
    var s = data.size[r.id];
    loaded(add(r.nsfw, r.rid), r.id, s[0], s[1]);
  }

  var frm = byId('screenshots');
  while(frm.nodeName.toLowerCase() != 'form')
    frm = frm.parentNode;
  onSubmit(frm, handleSubmit);

  addLast();
  ivInit();
}

function handleSubmit() {
  var loading = 0;
  var norelease = 0;

  var r = [];
  var l = byName(byId('scr_table'), 'tr');
  for(var i=0; i<l.length-1; i++)
    if(l[i].scr_loading)
      loading = 1;
    else if(l[i].scr_rid == 0)
      norelease = 1;
    else
      r.push({ rid: l[i].scr_rid, nsfw: l[i].scr_nsfw, id: l[i].scr_id });

  if(loading)
    alert('Please wait for the screenshots to be uploaded before submitting the form.');
  else if(norelease)
    alert('Please select the appropriate release for every screenshot.');
  else
    byId('screenshots').value = JSON.stringify(r);
  return !loading && !norelease;
}

function genRels(sel) {
  var r = tag('select', {'class':'scr_relsel'});
  for(var i=0; i<rels.length; i++)
    r.appendChild(tag('option', {value: rels[i][0], selected: rels[i][0] == sel}, rels[i][1]));
  return r;
}

function URL(id, t) {
  return staticUrl+'/s'+t+'/'+(id%100<10?'0':'')+(id%100)+'/'+id+'.jpg';
}

// Need to run addLast() after this function
function add(nsfw, rid) {
  var tr = tag('tr', { scr_id: 0, scr_loading: 1, scr_rid: rid, scr_nsfw: nsfw?1:0},
    tag('td', { 'class': 'thumb'}, 'Loading...'),
    tag('td',
      tag('b', 'Uploading screenshot'),
      tag('br', null),
      'This can take a while, depending on the file size and your upload speed.',
      tag('br', null),
      tag('a', {href:'#', onclick:del}, 'cancel')
    )
  );
  byId('scr_table').appendChild(tr);
  return tr;
}

function oddDim(dim) {
  if(dim == '256x384') // special-case NDS resolution (not in the DB)
    return false;
  for(var j=0; j<VARS.resolutions.length; j++) {
    if(typeof VARS.resolutions[j][1] != 'object') {
      if(VARS.resolutions[j][0] == dim)
        return false;
    } else {
      for(var k=1; k<VARS.resolutions[j].length; k++)
        if(VARS.resolutions[j][k][1] == dim)
          return false;;
    }
  }
  return true;
}

// Need to run ivInit() after this function
function loaded(tr, id, width, height) {
  var dim = width+'x'+height;
  tr.id = 'scr_tr_'+id;
  tr.scr_id = id;
  tr.scr_loading = 0;

  setContent(byName(tr, 'td')[0],
    tag('a', {href: URL(tr.scr_id, 'f'), 'data-iv':dim+':edit'},
      tag('img', {src: URL(tr.scr_id, 't')})
    )
  );

  var rel = genRels(tr.scr_rid);
  rel.onchange = function() { tr.scr_rid = this.options[this.selectedIndex].value };

  var nsfwid = 'scr_nsfw_'+id;
  setContent(byName(tr, 'td')[1],
    tag('b', 'Screenshot #'+id),
    ' (', tag('a', {href: '#', onclick:del}, 'remove'), ')',
    tag('br', null),
    'Full size: '+dim,
    !oddDim(dim) ? null : tag('b', {'class':'standout', 'style':'font-weight: bold'},
      ' WARNING: Odd resolution! Please check whether the image has been cropped correctly.'),
    tag('br', null),
    tag('br', null),
    tag('input', {type:'checkbox', name:nsfwid, id:nsfwid, checked: tr.scr_nsfw!=0, onclick: function() { tr.scr_nsfw = this.checked?1:0 }, 'class':'scr_nsfw'}),
    tag('label', {'for':nsfwid}, 'This screenshot is NSFW'),
    tag('br', null),
    rel
  );
}

function addLast() {
  if(byId('scr_last'))
    byId('scr_table').removeChild(byId('scr_last'));
  var full = byName(byId('scr_table'), 'tr').length >= 10;

  var rel = genRels(defRid);
  rel.onchange = function() { defRid = this.options[this.selectedIndex].value };
  rel.id = 'scradd_relsel';

  byId('scr_table').appendChild(tag('tr', {id:'scr_last'},
    tag('td', {'class': 'thumb'}),
    full ? tag('td',
      tag('b', 'Enough screenshots'),
      tag('br', null),
      'The limit of 10 screenshots per visual novel has been reached.\nIf you want to add a new screenshot, please remove an existing one first.'
    ) : tag('td',
      tag('b', 'Add screenshot'),
      tag('br', null),
      'Image must be smaller than 5MB and in PNG or JPEG format.',
      tag('br', null),
      rel,
      tag('br', null),
      tag('input', {name:'scr_upload', id:'scr_upload', type:'file', 'class':'text', multiple:true}),
      tag('br', null),
      tag('input', {type:'button', value:'Upload!', 'class':'submit', onclick:upload})
    )
  ));
}

function del(what) {
  var tr = what && what.scr_id != null ? what : this;
  while(tr.scr_id == null)
    tr = tr.parentNode;
  if(tr.scr_ajax)
    tr.scr_ajax.abort();
  byId('scr_table').removeChild(tr);
  addLast();
  ivInit();
  return false;
}

function uploadFile(f) {
  var tr = add(0, defRid);
  var fname = f.name;
  var frm = new FormData();
  frm.append('file', f);
  tr.scr_ajax = ajax('/xml/screenshots.xml', function(hr) {
    tr.scr_ajax = null;
    var img = hr.responseXML.getElementsByTagName('image')[0];
    var id = img.getAttribute('id');
    if(id < 0) {
      alert(fname + ":\n" + (
         id == -1 ? 'Upload failed!\nOnly JPEG or PNG images are accepted.'
                  : 'Upload failed!\nNo file selected, or an empty file?'));
      del(tr);
    } else {
      loaded(tr, id, img.getAttribute('width'), img.getAttribute('height'));
      ivInit();
    }
  }, true, frm);
}

function upload() {
  var files = byId('scr_upload').files;

  if(files.length < 1) {
    alert('Upload failed!\nNo file selected, or an empty file?');
    return false;
  } else if(files.length + byName(byId('scr_table'), 'tr').length - 1 > 10) {
    alert('Too many files selected. The total number of screenshots may not exceed 10.');
    return false;
  }

  for(var i=0; i<files.length; i++)
    uploadFile(files[i]);
  addLast();
  return false;
}

if(byId('jt_box_vn_scr') && byId('screenshots'))
  init();

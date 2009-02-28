// various form functions
// called by script.js

function qq(v) {
  return v.replace(/&/g,"&amp;").replace(/</,"&lt;").replace(/>/,"&gt;").replace(/"/g,'&quot;');
} 
function shorten(v, l) {
  return qq(v.length > l ? v.substr(0, l-3)+'...' : v);
}




   /************************\
   *   C A T E G O R I E S  *
   \************************/


function catLoad() {
  var i;
  var cats=[];
  var ct = x('categories');
  var l = ct.value.split(',');
  for(i=0;i<l.length;i++)
    cats[l[i].substr(0,3)] = Math.floor(l[i].substr(3,1));

  l = x('jt_box_categories').getElementsByTagName('a');
  for(i=0;i<l.length;i++) {
    if(l[i].id.substr(0, 4) != 'cat_')
      continue;
    catSet(l[i].id.substr(4), cats[l[i].id.substr(4)]||0);
    l[i].onclick = function() {
      var c = this.id.substr(4);
      if(!cats[c]) cats[c] = 0;
      if(c.substr(0,1) == 'p' || c == 'gaa' || c == 'gab' || c.substr(0,1) == 'h' || c.substr(0,1) == 'l' || c.substr(0,1) == 't') {
        if(cats[c]++)
          cats[c] = 0;
      } else if(++cats[c] == 4)
        cats[c] = 0;
      catSet(c, cats[c]);

     // has to be ordered before serializing!
      var r;l=[];i=0;
      for(r in cats)
        l[i++] = r;
      l = l.sort();
      r='';
      for(i=0;i<l.length;i++)
        if(cats[l[i]] > 0)
          r+=(r?',':'')+l[i]+cats[l[i]];
      ct.value = r;
      return false;
    };
  }
}

function catSet(id, rnk) {
  x('cat_'+id).className = 'catlvl_'+rnk;
  x('b_'+id).innerHTML = rnk;
}






   /***********************************\
   *   D R O P D O W N   S E A R C H   *
   \***********************************/


function dsInit(obj, url, trfunc, serfunc, retfunc) {
  obj.onkeydown = dsKeyDown;
  obj.onblur = function() {
    // timeout to make sure the tr.onclick event is called before we've hidden the object
    setTimeout(function () {
      if(x('ds_box'))
        x('ds_box').style.top = '-500px';
    }, 500)
  };
 // all local data is stored in the DOM input object
  obj.returnFunc = retfunc;
  obj.trFunc = trfunc;
  obj.serFunc = serfunc;
  obj.searchURL = url;
  obj.selectedId = 0;
}

function dsKeyDown(ev) {
  var c = document.layers ? ev.which : document.all ? event.keyCode : ev.keyCode;
  var obj = this;

  if(c == 9) // tab
    return true;

  // do some processing when the enter key has been pressed
  if(c == 13) {
    var o = obj;
    while(o && o.nodeName.toLowerCase() != 'form')
      o = o.parentNode;
    if(o) {
      var oldsubmit = o.onsubmit;
      o.onsubmit = function() { return false };
      setTimeout(function() { o.onsubmit = oldsubmit }, 100);
    }

    if(obj.selectedId != 0)
      obj.value = obj.serFunc(x('ds_box_'+obj.selectedId).itemData);
    if(obj.returnFunc)
      obj.returnFunc();
    if(x('ds_box'))
      x('ds_box').style.top = '-500px';
    obj.selectedId = 0;

    return false;
  }
 
  // process up/down keys
  if(x('ds_box') && (c == 38 || c == 40)) {
    var l = x('ds_box').getElementsByTagName('tr');
    if(l.length < 1)
      return true;

    if(obj.selectedId == 0) {
      if(c == 38) // up
        obj.selectedId = l[l.length-1].id.substr(7);
      else
        obj.selectedId = l[0].id.substr(7);
    } else {
      var sel = null;
      for(var i=0;i<l.length;i++)
        if(l[i].id == 'ds_box_'+obj.selectedId) {
          if(c == 38) // up
            sel = i>0 ? l[i-1] : l[l.length-1];
          else
            sel = l[i+1] ? l[i+1] : l[0];
        }
      obj.selectedId = sel.id.substr(7);
    }

    for(var i=0;i<l.length;i++)
      l[i].className = l[i].id == 'ds_box_'+obj.selectedId ? 'selected' : '';
    return true;
  }

  // this.value isn't available in a keydown event
  setTimeout(function() {
    dsSearch(obj);
  }, 10);
  
  return true;
}

function dsSearch(obj) {
  var b = x('ds_box');
  
  // show/hide the ds_box div
  if(obj.value.length < 2) {
    if(b)
      b.style.top = '-500px';
    obj.selectedId = 0;
    return;
  }
  if(!b) {
    b = document.createElement('div');
    b.setAttribute('id', 'ds_box');
    b.innerHTML = '<b>Loading...</b>';
    document.body.appendChild(b);
  }

  // position the div
  var ddx=0;
  var ddy=obj.offsetHeight;
  var o = obj;
  do {
    ddx += o.offsetLeft;
    ddy += o.offsetTop;
  } while(o = o.offsetParent);

  b.style.position = 'absolute';
  b.style.left = ddx+'px';
  b.style.top = ddy+'px';
  b.style.width = obj.offsetWidth+'px';

  // perform search
  ajax(obj.searchURL + encodeURIComponent(obj.value), function(hr) {
    dsResults(hr, obj);
  });
}

function dsResults(hr, obj) {
  var l = hr.responseXML.getElementsByTagName('item');
  var b = x('ds_box');
  if(l.length < 1) {
    b.innerHTML = '<b>No results...</b>';
    obj.selectedId = 0;
    return;
  }

  b.innerHTML = '<table><tbody></tbody></table>';
  tb = b.getElementsByTagName('tbody')[0];
  for(var i=0;i<l.length;i++) {
    var id = l[i].getAttribute('id');
    var tr = document.createElement('tr');
    tr.setAttribute('id', 'ds_box_'+id);
    tr.itemData = l[i];
    if(obj.selectedId == id)
      tr.setAttribute('class', 'selected');
    tr.onmouseover = function() {
      obj.selectedId = this.id.substr(7);
      var l = x('ds_box').getElementsByTagName('tr');
      for(var i=0;i<l.length;i++)
        l[i].className = l[i].id == 'ds_box_'+obj.selectedId ? 'selected' : '';
    };
    tr.onclick = function() {
      obj.value = obj.serFunc(this.itemData);
      if(obj.returnFunc)
        obj.returnFunc();
      if(x('ds_box'))
        x('ds_box').style.top = '-500px';
      obj.selectedId = 0;
    };
    obj.trFunc(l[i], tr);
    tb.appendChild(tr);
  }

  if(obj.selectedId != 0 && !x('ds_box_'+obj.selectedId))
    obj.selectedId = 0;
}






   /*****************************\
   *   V N   R E L A T I O N S   *
   \*****************************/


var relTypes = [];
function relLoad() {
  var i;var l;var o;

  // fetch the relation types from the add new relation selectbox
  l = x('relation_new').getElementsByTagName('select')[0].options;
  for(i=0;i<l.length;i++)
    relTypes[Math.floor(l[i].value)] = l[i].text;

  // read the current relations
  l = x('relations').value.split('|||');
  if(l[0]) {
    for(i=0;i<l.length;i++) {
      var rel = l[i].split(',', 3);
      relAdd(rel[0], rel[1], rel[2]);
    }
  }
  relEmpty();

  // make sure the title is up-to-date
  x('title').onchange = function() {
    l = x('jt_box_relations').getElementsByTagName('td');
    for(i=0;i<l.length;i++)
      if(l[i].className == 'tc3')
        l[i].innerHTML = shorten(this.value, 40);
  };

  // bind the add-link
  x('relation_new').getElementsByTagName('a')[0].onclick = relFormAdd;

  // dropdown
  dsInit(x('relation_new').getElementsByTagName('input')[0], '/xml/vn.xml?q=', function(item, tr) {
    var td = document.createElement('td');
    td.innerHTML = 'v'+item.getAttribute('id');
    td.style.textAlign = 'right';
    td.style.paddingRight = '5px';
    tr.appendChild(td);
    td = document.createElement('td');
    td.innerHTML = shorten(item.firstChild.nodeValue, 40);
    tr.appendChild(td);
  }, function(item) {
    return 'v'+item.getAttribute('id')+':'+item.firstChild.nodeValue;
  }, relFormAdd);
}

function relAdd(rel, vid, title) {
  var o = document.createElement('tr');
  o.setAttribute('id', 'relation_tr_'+vid);

  var t = document.createElement('td');
  t.className = 'tc1';
  t.innerHTML = 'v'+vid+':<a href="/v'+vid+'">'+shorten(title, 40)+'</a>';
  o.appendChild(t);

  var options = '';
  for(var i=0;i<relTypes.length;i++)
    options += '<option value="'+i+'"'+(i == rel ? ' selected="selected"' : '')+'>'+qq(relTypes[i])+'</option>';
  t = document.createElement('td');
  t.className = 'tc2';
  t.innerHTML = 'is a <select onchange="relSerialize()">'+options+'</select> of';
  o.appendChild(t);

  t = document.createElement('td');
  t.className = 'tc3';
  t.innerHTML = shorten(x('title').value, 40);
  o.appendChild(t);

  t = document.createElement('td');
  t.className = 'tc4';
  t.innerHTML = '<a href="#" onclick="return relDel('+vid+')">del</a>';
  o.appendChild(t);

  x('relation_tbl').appendChild(o);
  relEmpty();
}

function relEmpty() {
  if(x('relation_tbl').getElementsByTagName('tr').length > 0) {
    if(x('relation_tr_none'))
      x('relation_tbl').removeChild(x('relation_tr_none'));
    return;
  }
  var o = document.createElement('tr');
  o.setAttribute('id', 'relation_tr_none');
  var t = document.createElement('td');
  t.colspan = 4;
  t.innerHTML = 'No relations selected.';
  o.appendChild(t);
  x('relation_tbl').appendChild(o);
}

function relSerialize() {
  var r='';
  var i;
  var l = x('relation_tbl').getElementsByTagName('tr');
  for(i=0;i<l.length;i++) {
    var title = l[i].getElementsByTagName('td')[0];
    title = title.innerText || title.textContent;
    title = title.substr(title.indexOf(':')+1);
    r += (r ? '|||' : '')
        +l[i].getElementsByTagName('select')[0].selectedIndex
        +','+l[i].id.substr(12)+','+title;
  }
  x('relations').value = r;
}

function relDel(vid) {
  x('relation_tbl').removeChild(x('relation_tr_'+vid));
  relSerialize();
  relEmpty();
  return false;
}

function relFormAdd() {
  var txt = x('relation_new').getElementsByTagName('input')[0];
  var sel = x('relation_new').getElementsByTagName('select')[0];
  var lnk = x('relation_new').getElementsByTagName('a')[0];
  var input = txt.value;

  if(!input.match(/^v[0-9]+/)) {
    alert('Visual novel textbox must start with an ID (e.g. v17)');
    return false;
  }

  txt.disabled = true;
  txt.value = 'loading...';
  sel.disabled = true;
  lnk.innerHTML = 'loading...';

  ajax('/xml/vn.xml?q='+encodeURIComponent(input), function(hr) {
    txt.disabled = false;
    txt.value = '';
    sel.disabled = false;
    lnk.innerHTML = 'add';

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert('Visual novel not found!');

    var id = items[0].getAttribute('id');
    if(x('relation_tr_'+id))
      return alert('This visual novel has already been selected!');

    relAdd(sel.selectedIndex, id, items[0].firstChild.nodeValue);
    sel.selectedIndex = 0;
    relSerialize();
  });
  return false;
}






   /*********************************\
   *   V N   S C R E E N S H O T S   *
   \*********************************/


var scrRel = [ [ 0, '-- select release --' ] ];
var scrStaticURL;
function scrLoad() {
  // load the releases
  scrStaticURL = x('scr_rel').className;
  var l = x('scr_rel').options;
  for(var i=0;i<l.length;i++)
    scrRel[i+1] = [ l[i].value, l[i].text ];
  x('scr_rel').parentNode.removeChild(x('scr_rel'));

  // load the current screenshots
  l = x('screenshots').value.split(' ');
  for(i=0;i<l.length;i++)
    if(l[i].length > 2) {
      var r = l[i].split(',');
      scrAdd(r[0], r[1], r[2]);
    }
  scrLast();
  scrCheckStatus();

  scrSetSubmit();
}

// give an error when submitting the form while still uploading an image
function scrSetSubmit() {
  var o=x('screenshots');
  while(o.nodeName.toLowerCase() != 'form')
    o = o.parentNode;
  oldfunc = o.onsubmit;
  o.onsubmit = function() {
    var c=0;var r=0;
    var l = x('scr_table').getElementsByTagName('tr');
    for(var i=0;i<l.length-1;i++) {
      if(l[i].scrStatus > 0)
        c=1;
      else if(l[i].getElementsByTagName('select')[0].selectedIndex == 0)
        r=1;
    }
    if(c) {
      alert('Please wait for the screenshots to be uploaded before submitting the form.');
      return false;
    } else if(r) {
      alert('Please select the appropriate release for every screenshot');
      return false;
    } else if(oldfunc)
      return oldfunc();
  };
}


function scrURL(id, t) {
  return scrStaticURL+'/s'+t+'/'+(id%100<10?'0':'')+(id%100)+'/'+id+'.jpg';
}

function scrAdd(id, nsfw, rel) {
  var tr = document.createElement('tr');
  tr.scrId = id;
  tr.scrStatus = id ? 2 : 1; // 0: done, 1: uploading, 2: waiting for thumbnail
  tr.scrRel = rel;
  tr.scrNSFW = nsfw;
  
  var td = document.createElement('td');
  td.className = 'thumb';
  td.innerHTML = 'loading...';
  tr.appendChild(td);

  td = document.createElement('td');
  if(id)
    td.innerHTML = '<b>Generating thumbnail...</b><br />'
      +'Note: if this takes longer than 30 seconds, there\'s probably something wrong on our side.'
      +'Please try again later or report a bug if that is the case.';
  else
    td.innerHTML = '<b>Uploading screenshot...</b><br />'
      +'This can take a while, depending on the file size and your upload speed.<br />'
      +'<a href="#" onclick="return scrDel(this)">cancel</a>';
  tr.appendChild(td);
  
  x('scr_table').appendChild(tr);
  scrStripe();
  return tr;
}

function scrLast() {
  if(x('scr_last'))
    x('scr_table').removeChild(x('scr_last'));
  var full = x('scr_table').getElementsByTagName('tr').length >= 10;

  var tr = document.createElement('tr');
  tr.setAttribute('id', 'scr_last');

  var td = document.createElement('td');
  td.className = 'thumb';
  tr.appendChild(td);

  var td = document.createElement('td');
  if(full)
    td.innerHTML = '<b>Enough screenshots</b><br />'
      +'The limit of 10 screenshots per visual novel has been reached. '
      +'If you want to add a new screenshot, please remove an existing one first.';
  else
    td.innerHTML = '<b>Add screenshot</b><br />'
      +'Image must be smaller than 5MB and in PNG or JPEG format.<br />'
      +'<input name="scr_upload" id="scr_upload" type="file" class="text" /><br />'
      +'<input type="button" value="Upload!" class="submit" onclick="scrUpload()" />';

  tr.appendChild(td);
  x('scr_table').appendChild(tr);
  scrStripe();
}

function scrStripe() {
  var l = x('scr_table').getElementsByTagName('tr');
  for(var i=0;i<l.length;i++)
    l[i].className = i%2==0 ? 'odd' : '';
}

function scrCheckStatus() {
  var ids = '';
  var l = x('scr_table').getElementsByTagName('tr');
  for(var i=0;i<l.length-1;i++)
    if(l[i].scrStatus == 2)
      ids += (ids ? ';' : '?')+'id='+l[i].scrId;
  if(!ids)
    return setTimeout(scrCheckStatus, 1000);

  var ti = setTimeout(scrCheckStatus, 10000);
  ajax('/xml/screenshots.xml'+ids, function(hr) {
    var ls = hr.responseXML.getElementsByTagName('item');
    var l = x('scr_table').getElementsByTagName('tr');
    var tr;
    for(var s=0;s<ls.length;s++) {
      for(i=0;i<l.length-1;i++)
        if(l[i].scrId == ls[s].getAttribute('id') && ls[s].getAttribute('status') > 0)
          tr = l[i];
      if(!tr)
        continue;

      tr.scrStatus = 0;
      tr.getElementsByTagName('td')[0].innerHTML = 
         '<a href="'+scrURL(tr.scrId, 'f')+'" rel="iv:'+ls[s].getAttribute('width')+'x'+ls[s].getAttribute('height')+':edit">'
        +'<img src="'+scrURL(tr.scrId, 't')+'" style="margin: 0; padding: 0; border: 0" /></a>';

      var opt='';
      for(var o=0;o<scrRel.length;o++)
        opt += '<option value="'+scrRel[o][0]+'"'+(tr.scrRel && tr.scrRel == scrRel[o][0] ? ' selected="selected"' : '')+'>'+scrRel[o][1]+'</option>';

      tr.getElementsByTagName('td')[1].innerHTML = '<b>Screenshot #'+tr.scrId+'</b>'
        +' (<a href="#" onclick="return scrDel(this)">remove</a>)<br />'
        +'Full size: '+ls[s].getAttribute('width')+'x'+ls[s].getAttribute('height')+'<br /><br />'
        +'<input type="checkbox" onclick="scrSerialize()" id="scr_ser_'+tr.scrId+'" name="scr_ser_'+tr.scrId+'"'
        +' '+(tr.scrNSFW > 0 ? 'checked = "checked"' : '')+' />'
        +'<label for="scr_ser_'+tr.scrId+'">This screenshot is NSFW</label><br />'
        +'<select onchange="scrSerialize()">'+opt+'</select>';
    }
    scrSerialize();
    ivInit();
    clearTimeout(ti);
    setTimeout(scrCheckStatus, 1000);
  });
}

function scrDel(what) {
  while(what.nodeName.toLowerCase() != 'tr')
    what = what.parentNode;
  what.scrStatus = 3;
  x('scr_table').removeChild(what);
  scrSerialize();
  scrLast();
  return false;
}

var scrUplNr=0;
function scrUpload() {
  scrUplNr++;

  // create temporary form
  var d = document.createElement('div');
  d.style.cssText = 'visibility: hidden; overflow: hidden; width: 1px; height: 1px; position: absolute; left: -500px; top: -500px';
  d.innerHTML = '<iframe id="scr_upl_'+scrUplNr+'" name="scr_upl_'+scrUplNr+'" style="height: 0px; width: 0px; visibility: hidden"'
    +' src="about:blank" onload="scrUploadComplete(this)"></iframe>'
    +'<form method="post" action="/xml/screenshots.xml" target="scr_upl_'+scrUplNr+'" enctype="multipart/form-data" id="scr_frm_'+scrUplNr+'"></form>';
  document.body.appendChild(d);

  // submit form and delete it
  d = x('scr_frm_'+scrUplNr);
  d.appendChild(x('scr_upload'));
  d.submit();
  d.parentNode.removeChild(d);

  d = scrAdd(0, 0, 0);
  x('scr_upl_'+scrUplNr).theTR = d;
  scrLast();

  return false;
}

function scrUploadComplete(what) {
  var f = window.frames[what.id];
  if(f.location.href.indexOf('screenshots') < 0)
    return;

  var tr = what.theTR;
  if(!tr || tr.scrStatus == 3)
    return;

  try {
    tr.scrId = f.window.document.getElementsByTagName('image')[0].getAttribute('id');
  } catch(e) {
    tr.scrId = -10;
  }
  if(tr.scrId < 0) {
    alert(
      tr.scrId == -10 ?
         'Oops! Seems like something went wrong...\n'
        +'Make sure the file you\'re uploading doesn\'t exceed 5MB in size.\n'
        +'If that isn\'t the problem, then please report a bug.' :
      tr.scrId == -1 ?
        'Upload failed!\nOnly JPEG or PNG images are accepted.' :
        'Upload failed!\nNo file selected, or an empty file?'
    );
    return scrDel(tr);
  }

  tr.scrStatus = 2;
  tr.getElementsByTagName('td')[1].innerHTML = 
     '<b>Generating thumbnail...</b><br />'
    +'Note: if this takes longer than 30 seconds, there\'s probably something wrong on our side.'
    +'Please try again later or report a bug if that is the case.';

  // remove the <div> in a timeout, otherwise some browsers think the page is still loading
  setTimeout(function() { document.body.removeChild(what.parentNode) }, 100);
}

function scrSerialize() {
  var r = '';
  var l = x('scr_table').getElementsByTagName('tr');
  for(var i=0;i<l.length-1;i++)
    if(l[i].scrStatus == 0)
      r += (r ? ' ' : '') + l[i].scrId + ','
        + (l[i].getElementsByTagName('input')[0].checked ? 1 : 0) + ','
        + scrRel[l[i].getElementsByTagName('select')[0].selectedIndex][0];
  x('screenshots').value = r;
}






   /***************\
   *   M E D I A   *
   \***************/


var medTypes = [ [ '', '- medium -', false ] ];
function medLoad() {
  // load the medTypes and clear the div
  var l = x('media_div').getElementsByTagName('select')[0].options;
  for(var i=0;i<l.length;i++)
    medTypes[medTypes.length] = [ l[i].value, l[i].text, l[i].className.indexOf('noqty') ? false : true ];
  x('media_div').innerHTML = '';

  // load the selected media
  l = x('media').value.split(',');
  for(var i=0;i<l.length;i++)
    if(l[i].length > 2)
      medAddNew(l[i].split(' ')[0], Math.floor(l[i].split(' ')[1]));

  medAddNew('', 0);
  medSetSubmit();
}

function medSetSubmit() {
  var o=x('media');
  while(o.nodeName.toLowerCase() != 'form')
    o = o.parentNode;
  oldfunc = o.onsubmit;
  o.onsubmit = function() {
    var l = x('media_div').getElementsByTagName('span');
    for(var i=0;i<l.length-1;i++) {
      var s = l[i].getElementsByTagName('select');
      if(!medTypes[s[1].selectedIndex][2] && s[0].selectedIndex == 0) {
        alert('Media '+medTypes[s[1].selectedIndex][1]+' requires a quantity to be specified!');
        return false;
      }
    }
    return oldfunc ? oldfunc() : true;
  };
}

function medAddNew(med, qty) {
  var o = document.createElement('span');
  var r = '<select class="qty" onchange="medSerialize()"><option value="0">- quantity -</option>';
  for(var i=1;i<=10;i++)
    r += '<option value="'+i+'"'+(qty == i ? ' selected="selected"' : '')+'>'+i+'</option>';
  r += '</select><select class="medium" onchange="return medCheckNew(this)">';
  for(i=0;i<medTypes.length;i++)
    r += '<option value="'+medTypes[i][0]+'"'+(med == medTypes[i][0] ? ' selected="selected"' : '')+'>'+medTypes[i][1]+'</option>';
  r += '</select>';
  if(med != '')
    r += '<input type="button" class="submit" onclick="return medDel(this)" value="remove" />';
  o.innerHTML = r;
  x('media_div').appendChild(o);
}

function medDel(what) {
  what = what.nodeName ? what : this;
  while(what.nodeName.toLowerCase() != 'span')
    what = what.parentNode;
  x('media_div').removeChild(what);
  medSerialize();
  return false;
}

function medCheckNew() {
  // check for non-new items and add remove buttons
  var l = x('media_div').getElementsByTagName('span');
  var createnew=1;
  for(var i=0;i<l.length;i++) {
    var sel = l[i].getElementsByTagName('select')[1].selectedIndex;
    if(sel == 0)
      createnew = 0;
    else if(l[i].getElementsByTagName('input').length < 1) {
      var a = document.createElement('input');
      a.type = 'button';
      a.className = 'submit';
      a.onclick = medDel;
      a.value = 'remove';
      l[i].appendChild(a);
    }
  }
  if(createnew)
    medAddNew('', 0);
  medSerialize();
    
  return true;
}

function medSerialize() {
  var r = '';
  var l = x('media_div').getElementsByTagName('span');
  for(var i=0;i<l.length;i++) {
    var sel = l[i].getElementsByTagName('select');
    if(sel[1].selectedIndex != 0)
      r += (r ? ',' : '') + medTypes[sel[1].selectedIndex][0] + ' ' + (medTypes[sel[1].selectedIndex][2] ? 0 : sel[0].selectedIndex);
  }
  x('media').value = r;
}






   /****************************************************\
   *   V I S U A L   N O V E L S  /  P R O D U C E R S  *
   \****************************************************/


function vnpLoad(type) {
  // load currently selected VNs
  var l = x(type).value.split('|||');
  for(var i=0;i<l.length;i++)
    if(l[i].length > 2)
      vnpAdd(type, l[i].split(',',2)[0], l[i].split(',',2)[1]);
  vnpCheckEmpty(type);

  // dropdown
  var n = x('jt_box_'+(type == 'vn' ? 'visual_novels' : type)).getElementsByTagName('div')[1];
  dsInit(n.getElementsByTagName('input')[0], '/xml/'+type+'.xml?q=', function(item, tr) {
    var td = document.createElement('td');
    td.innerHTML = type.substr(0,1)+item.getAttribute('id');
    td.style.textAlign = 'right';
    td.style.paddingRight = '5px';
    tr.appendChild(td);
    td = document.createElement('td');
    td.innerHTML = shorten(item.firstChild.nodeValue, 40);
    tr.appendChild(td);
  }, function(item) {
    return type.substr(0,1)+item.getAttribute('id')+':'+item.firstChild.nodeValue;
  }, function() { vnpFormAdd(type) });
  n.getElementsByTagName('a')[0].onclick = function() { vnpFormAdd(type); return false };
}

function vnpAdd(type, id, title) {
  var o = document.createElement('span');
  o.innerHTML = '<i>'+type.substr(0,1)+id+':<a href="/'+type.substr(0,1)+id+'">'+shorten(title, 40)+'</a></i>'
    +'<a href="#" onclick="return vnpDel(this, \''+type+'\')">remove</a>';
  x(type+'sel').appendChild(o);
  vnpStripe(type);
  vnpCheckEmpty(type);
}

function vnpDel(what, type) {
  what = what.nodeName ? what : this;
  while(what.nodeName.toLowerCase() != 'span')
    what = what.parentNode;
  x(type+'sel').removeChild(what);
  vnpCheckEmpty(type);
  vnpSerialize(type);
  return false;
}

function vnpCheckEmpty(type) {
  var o = x(type+'sel');
  if(o.getElementsByTagName('span').length < 1) {
    if(o.getElementsByTagName('b').length < 1)
      o.innerHTML = '<b>Nothing selected...</b>';
  } else if(o.getElementsByTagName('b').length == 1)
    o.removeChild(o.getElementsByTagName('b')[0]);
}

function vnpStripe(type) {
  var l = x(type+'sel').getElementsByTagName('span');
  for(var i=0;i<l.length;i++)
    l[i].className = i%2 ? 'odd' : '';
}

function vnpFormAdd(type) {
  var n = x('jt_box_'+(type == 'vn' ? 'visual_novels' : type)).getElementsByTagName('div')[1];
  var txt = n.getElementsByTagName('input')[0];
  var lnk = n.getElementsByTagName('a')[0];
  var input = txt.value;

  if(type == 'vn' && !input.match(/^v[0-9]+/)) {
    alert('Visual novel textbox must start with an ID (e.g. v17)');
    return false;
  }
  if(type == 'producers' && !input.match(/^p[0-9]+/)) {
    alert('Producer textbox must start with an ID (e.g. p5)');
    return false;
  }

  txt.disabled = true;
  txt.value = 'loading...';
  lnk.innerHTML = 'loading...';

  ajax('/xml/'+type+'.xml?q='+encodeURIComponent(input), function(hr) {
    txt.disabled = false;
    txt.value = '';
    lnk.innerHTML = 'add';

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert('Item not found!');

    vnpAdd(type, items[0].getAttribute('id'), items[0].firstChild.nodeValue);
    vnpSerialize(type);
  });
  return false;
}

function vnpSerialize(type) {
  var r = '';
  var l = x(type+'sel').getElementsByTagName('span');
  for(var i=0;i<l.length;i++)
    r += (r ? '|||' : '') + l[i].getElementsByTagName('i')[0].innerHTML.substr(1, l[i].getElementsByTagName('i')[0].innerHTML.indexOf(':')-1)
      + ',' + l[i].getElementsByTagName('a')[0].innerHTML;
  x(type).value = r;
}






   /****************************************************\
   *   V I S U A L   N O V E L   T A G   L I N K I N G  *
   \****************************************************/


function tglLoad() {
  var n = x('tagtable').getElementsByTagName('tfoot')[0].getElementsByTagName('input');
  dsInit(n[0], '/xml/tags.xml?q=', function(item, tr) {
    var td = document.createElement('td');
    td.innerHTML = shorten(item.firstChild.nodeValue, 40);
    if(item.getAttribute('meta') == 'yes')
      td.innerHTML = '<b class="grayedout">'+td.innerHTML+'</b> (meta)';
    tr.appendChild(td);
  }, function(item) {
    return item.firstChild.nodeValue;
  }, tglAdd);
  n[1].onclick = tglAdd;

  tglStripe();
  var l = x('tagtable').getElementsByTagName('tbody')[0].getElementsByTagName('tr');
  for(var i=0; i<l.length;i++) {
    var o = l[i].getElementsByTagName('td')[3];
    tglVoteBar(o, parseInt(o.innerHTML));
  }
}

function tglVoteBar(obj, vote) {
  var r = '';
  for(i=-3;i<=3;i++)
    r += '<a href="#" class="taglvl taglvl'+i+'" onmouseover="tglVoteBarSel(this, '+i+')"'
       + ' onmouseout="tglVoteBarSel(this, '+vote+')" onclick="return tglVoteBar(this.parentNode, '+i+')">&nbsp;</a>';
  obj.innerHTML = r;
  tglVoteBarSel(obj, vote);
  tglSerialize();
  return false;
}

function tglVoteBarSel(obj, vote) {
  if(obj.className.indexOf('taglvl') >= 0)
    obj = obj.parentNode;
  var l = obj.getElementsByTagName('a');
  var num;
  for(var i=0; i<l.length; i++) {
    if((num = l[i].className.replace(/^.*taglvl(-?[0-3]).*$/, "$1")) == l[i].className)
      continue;
    if(num == 0)
      l[i].innerHTML = vote == 0 ? '-' : vote;
    else if(num<0&&vote<=num || num>0&&vote>=num) {
      if(l[i].className.indexOf('taglvlsel') < 0)
        l[i].className += ' taglvlsel';
    } else
      if(l[i].className.indexOf('taglvlsel') >= 0)
        l[i].className = l[i].className.replace(/taglvlsel/, '');
  }
}

function tglAdd() {
  var n = x('tagtable').getElementsByTagName('tfoot')[0].getElementsByTagName('input');
  n[0].disabled = n[1].disabled = true;
  n[1].value = 'loading...';
  ajax('/xml/tags.xml?q=name:'+encodeURIComponent(n[0].value), function(hr) {
    n[0].disabled = n[1].disabled = false;
    n[1].value = 'Add tag';
    n[0].value = '';

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert('Item not found!');
    if(items[0].getAttribute('meta') == 'yes')
      return alert('Can\'t use meta tags here!');
    var name = items[0].firstChild.nodeValue;
    var l = x('tagtable').getElementsByTagName('a');
    for(var i=0; i<l.length; i++)
      if(l[i].innerHTML == shorten(name, 40))
        return alert('Tag is already present!');

    var tr = document.createElement('tr');
    var td = document.createElement('td');
    td.innerHTML = '<a href="/g'+items[0].getAttribute('id')+'">'+name+'</a>';
    td.className = 'tc1';
    tr.appendChild(td);
    td = document.createElement('td');
    td.className = 'tc2';
    td.innerHTML = '0.00 (0)';
    tr.appendChild(td);
    td = document.createElement('td');
    td.innerHTML = '0';
    td.className = 'tc3';
    tr.appendChild(td);
    td = document.createElement('td');
    tglVoteBar(td, 2);
    td.className = 'tc4';
    tr.appendChild(td);
    td = document.createElement('td');
    td.innerHTML = '-';
    td.className = 'tc5';
    tr.appendChild(td);
    x('tagtable').getElementsByTagName('tbody')[0].appendChild(tr);
    tglStripe();
    tglSerialize();
  });
}

function tglStripe() {
  var l = x('tagtable').getElementsByTagName('tbody')[0].getElementsByTagName('tr');
  for(var i=0;i<l.length;i++)
    l[i].className = i%2 ? 'odd' : '';
}

function tglSerialize() {
  var r = '';
  var l = x('tagtable').getElementsByTagName('tbody')[0].getElementsByTagName('tr');
  for(var i=0; i<l.length;i++) {
    var lnk = l[i].getElementsByTagName('a')[0].href;
    var vt = l[i].getElementsByTagName('td')[3].getElementsByTagName('a');
    var id;
    if((id = lnk.replace(/^.*g([1-9][0-9]*)$/, "$1")) != lnk && vt.length > 3 && vt[3].innerHTML != '-')
      r += (r?' ':'')+id+','+vt[3].innerHTML;
  }
  x('taglinks').value = r;
}



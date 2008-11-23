// various form functions
// called by script.js

function qq(v) {
  return v.replace(/&/g,"&amp;").replace(/</,"&lt;").replace(/>/,"&gt;").replace(/"/g,'&quot;');
} 
function shorten(v, l) {
  return qq(v.length > l ? v.substr(0, l-3)+'...' : v);
}
var http_request = false;
function ajax(url, func) {
  if(http_request)
    http_request.abort();
  http_request = (window.ActiveXObject) ? new ActiveXObject('Microsoft.XMLHTTP') : new XMLHttpRequest();
  if(http_request == null) {
    alert("Your browse does not support the functionality this website requires.");
    return;
  }
  http_request.onreadystatechange = function() {
    if(!http_request || http_request.readyState != 4 || !http_request.responseText)
      return;
    if(http_request.status != 200)
      return alert('Whoops, error! :(');
    func(http_request);
  };
  url += (url.indexOf('?')>=0 ? '&' : '?')+(Math.floor(Math.random()*999)+1);
  http_request.open('GET', url, true);
  http_request.send(null);
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
  // doesn't work very nice with skins...
  var c = rnk == 0 ? '' :
          rnk == 1 ? '#0c0' :
          rnk == 2 ? '#cc0' : '#c00';
  x('b_'+id).style.color = c;
  x('cat_'+id).style.color = c;
  x('b_'+id).innerHTML = rnk;
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
  // catch return key
  x('relation_new').getElementsByTagName('input')[0].onkeydown = function(ev) {
    var c = document.layers ? ev.which : document.all ? event.keyCode : ev.keyCode;
    if(c == 13)
      return relFormAdd();
    return true;
  };
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

    var items = hr.responseXML.getElementsByTagName('vn');
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




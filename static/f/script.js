var expanded_icon = '▾';
var collapsed_icon = '▸';

/*  M I N I M A L   J A V A S C R I P T   L I B R A R Y  */

var http_request = false;
function ajax(url, func) {
  if(http_request)
    http_request.abort();
  http_request = (window.ActiveXObject) ? new ActiveXObject('Microsoft.XMLHTTP') : new XMLHttpRequest();
  if(http_request == null)
    return alert("Your browser does not support the functionality this website requires.");
  http_request.onreadystatechange = function() {
    if(!http_request || http_request.readyState != 4 || !http_request.responseText)
      return;
    if(http_request.status != 200)
      return alert('Whoops, error! :(');
    func(http_request);
  };
  url += (url.indexOf('?')>=0 ? ';' : '?')+(Math.floor(Math.random()*999)+1);
  http_request.open('GET', url, true);
  http_request.send(null);
}

function setCookie(n,v) {
  var date = new Date();
  date.setTime(date.getTime()+(365*24*60*60*1000));
  document.cookie = n+'='+v+'; expires='+date.toGMTString()+'; path=/';
}
function getCookie(n) {
  var l = document.cookie.split(';');
  for(var i=0; i<l.length; i++) {
    var c = l[i];
    while(c.charAt(0) == ' ')
      c = c.substring(1,c.length);
    if(c.indexOf(n+'=') == 0)
      return c.substring(n.length+1,c.length);
  }
  return null;
}

function x(y) { // deprecated
  return document.getElementById(y)
}
function byId(n) {
  return document.getElementById(n)
}
function byName(){
  var d = arguments.length > 1 ? arguments[0] : document;
  var n = arguments.length > 1 ? arguments[1] : arguments[0];
  return d.getElementsByTagName(n);
}
function byClass() { // [class], [parent, class], [tagname, class], [parent, tagname, class]
  var par = typeof arguments[0] == 'object' ? arguments[0] : document;
  var tag = arguments.length == 2 && typeof arguments[0] == 'string' ? arguments[0] : arguments.length == 3 ? arguments[1] : '*';
  var c = arguments[arguments.length-1];
  var l = byName(par, tag);
  var ret = [];
  for(var i=0; i<l.length; i++)
    if(hasClass(l[i], c))
      ret[ret.length] = l[i];
  return ret;
}

/* wrapper around DOM element creation
 * tag('string') -> createTextNode
 * tag('tagname', tag(), 'string', ..) -> createElement(), appendChild(), ..
 * tag('tagname', { class: 'meh', title: 'Title' }) -> createElement(), setAttribute()..
 * tag('tagname', { <attributes> }, <elements>) -> create, setattr, append */
function tag() {
  if(arguments.length == 1)
    return typeof arguments[0] != 'object' ? document.createTextNode(arguments[0]) : arguments[0];
  var el = typeof document.createElementNS != 'undefined'
    ? document.createElementNS('http://www.w3.org/1999/xhtml', arguments[0])
    : document.createElement(arguments[0]);
  for(var i=1; i<arguments.length; i++) {
    if(arguments[i] == null)
      continue;
    if(typeof arguments[i] == 'object' && !arguments[i].appendChild) {
      for(attr in arguments[i]) {
        if(attr == 'style')
          el.setAttribute(attr, arguments[i][attr]);
        else
          el[ attr == 'class' ? 'className' : attr ] = arguments[i][attr];
      }
    } else
      el.appendChild(tag(arguments[i]));
  }
  return el;
}
function addBody(el) {
  if(document.body.appendChild)
    document.body.appendChild(el);
  else if(document.documentElement.appendChild)
    document.documentElement.appendChild(el);
  else if(document.appendChild)
    document.appendChild(el);
}
function setContent(el, content) {
  setText(el, '');
  el.appendChild(content);
}
function getText(obj) {
  return obj.textContent || obj.innerText || '';
}
function setText(obj, txt) {
  if(obj.textContent != null)
    obj.textContent = txt;
  else
    obj.innerText = txt;
}

function listClass(obj) {
  var n = obj.className;
  if(!n)
    return [];
  return n.split(/ /);
}
function hasClass(obj, c) {
  var l = listClass(obj);
  for(var i=0; i<l.length; i++)
    if(l[i] == c)
      return true;
  return false;
}
function setClass(obj, c, set) {
  var l = listClass(obj);
  var n = [];
  if(set) {
    n = l;
    if(!hasClass(obj, c))
      n[n.length] = c;
  } else {
    for(var i=0; i<l.length; i++)
      if(l[i] != c)
        n[n.length] = l[i];
  }
  obj.className = n.join(' ');
}

function shorten(v, l) {
  return v.length > l ? v.substr(0, l-3)+'...' : v;
}




/*  I M A G E   V I E W E R  */

function ivInit() {
  var init = 0;
  var l = byName('a');
  for(var i=0;i<l.length;i++)
    if(l[i].rel.substr(0,3) == 'iv:') {
      init++;
      l[i].onclick = ivView;
    }
  if(init && !byId('iv_view')) {
    addBody(tag('div', {id: 'iv_view'},
      tag('b', {id:'ivimg'}, ''),
      tag('br', null),
      tag('a', {href:'#', id:'ivfull'}, ''),
      tag('a', {href:'#', onclick: ivClose, id:'ivclose'}, 'close'),
      tag('a', {href:'#', onclick: ivView, id:'ivprev'}, '« previous'),
      tag('a', {href:'#', onclick: ivView, id:'ivnext'}, 'next »')
    ));
    addBody(tag('b', {id:'ivimgload'}, 'Loading...'));
  }
}

function ivView(what) {
  what = what && what.rel ? what : this;
  var u = what.href;
  var opt = what.rel.split(':');
  var view = byId('iv_view');
  var next = byId('ivnext');
  var prev = byId('ivprev');
  var full = byId('ivfull');

  // fix prev/next links (if any)
  if(opt[2]) {
    var ol = byName('a');
    var l=[];
    for(i=0;i<ol.length;i++)
      if(ol[i].rel.substr(0,3) == 'iv:' && ol[i].rel.indexOf(':'+opt[2]) > 4 && !hasClass(l[i], 'hidden') && ol[i].id != 'ivprev' && ol[i].id != 'ivnext')
        l[l.length] = ol[i];
    for(i=0;i<l.length;i++)
      if(l[i].href == u) {
        next.style.visibility = l[i+1] ? 'visible'   : 'hidden';
        next.href             = l[i+1] ? l[i+1].href : '#';
        next.rel              = l[i+1] ? l[i+1].rel  : '';
        prev.style.visibility = l[i-1] ? 'visible'   : 'hidden';
        prev.href             = l[i-1] ? l[i-1].href : '#';
        prev.rel              = l[i-1] ? l[i-1].rel  : '';
      }
  } else
    next.style.visibility = prev.style.visibility = 'hidden';

  // calculate dimensions
  var w = Math.floor(opt[1].split('x')[0]);
  var h = Math.floor(opt[1].split('x')[1]);
  var ww = typeof(window.innerWidth) == 'number' ? window.innerWidth : document.documentElement.clientWidth;
  var wh = typeof(window.innerHeight) == 'number' ? window.innerHeight : document.documentElement.clientHeight;
  var st = typeof(window.pageYOffset) == 'number' ? window.pageYOffset : document.body && document.body.scrollTop ? document.body.scrollTop : document.documentElement.scrollTop;
  if(w+100 > ww || h+70 > wh) {
    full.href = u;
    setText(full, w+'x'+h);
    full.style.visibility = 'visible';
    if(w/h > ww/wh) { // width++
      h *= (ww-100)/w;
      w = ww-100;
    } else { // height++
      w *= (wh-70)/h;
      h = wh-70;
    }
  } else
    full.style.visibility = 'hidden';
  var dw = w;
  var dh = h+20;
  dw = dw < 200 ? 200 : dw;

  // update document
  view.style.display = 'block';
  setContent(byId('ivimg'), tag('img', {src:u, onclick:ivClose,
    onload: function() { byId('ivimgload').style.top='-400px'; },
    style: 'width: '+w+'px; height: '+h+'px'
  }));
  view.style.width = dw+'px';
  view.style.height = dh+'px';
  view.style.left = ((ww - dw) / 2 - 10)+'px';
  view.style.top = ((wh - dh) / 2 + st - 20)+'px';
  byId('ivimgload').style.left = ((ww - 100) / 2 - 10)+'px';
  byId('ivimgload').style.top = ((wh - 20) / 2 + st)+'px';
  return false;
}

function ivClose() {
  byId('iv_view').style.display = 'none';
  byId('iv_view').style.top = '-5000px';
  byId('ivimgload').style.top = '-400px';
  setText(byId('ivimg'), '');
  return false;
}

ivInit();




/*  D R O P D O W N  */

function ddInit(obj, align, contents) {
  obj.dd_align = align; // only 'left' and 'bottom' supported at the moment
  obj.dd_contents = contents;
  document.onmousemove = ddMouseMove;
  if(!byId('dd_box'))
    addBody(tag('div', {id:'dd_box', dd_used: false}));
}

function ddHide() {
  var box = byId('dd_box');
  setText(box, '');
  box.style.left = '-500px';
  box.dd_used = false;
}

function ddMouseMove(e) {
  e = e || window.event;
  var lnk = e.target || e.srcElement;
  while(lnk && (lnk.nodeType == 3 || !lnk.dd_align))
    lnk = lnk.parentNode;
  var box = byId('dd_box');
  if(!box.dd_used && !lnk)
    return;

  if(box.dd_used) {
    var mouseX = e.pageX || (e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft);
    var mouseY = e.pageY || (e.clientY + document.body.scrollTop  + document.documentElement.scrollTop);
    if((mouseX < ddx-10 || mouseX > ddx+box.offsetWidth+10 || mouseY < ddy-10 || mouseY > ddy+box.offsetHeight+10)
        || (lnk && lnk.id == box.dd_id))
      ddHide();
  }

  if(!box.dd_used && lnk) {
    var content = lnk.dd_contents(lnk, box);
    if(content == null)
      return;
    setContent(box, content);
    box.dd_id = lnk.id;
    box.dd_used = true;

    var o = lnk;
    ddx = ddy = 0;
    do {
      ddx += o.offsetLeft;
      ddy += o.offsetTop;
    } while(o = o.offsetParent);

    if(lnk.dd_align == 'left')
      ddx -= box.offsetWidth;
    if(lnk.dd_align == 'bottom')
      ddy += lnk.offsetHeight;
    box.style.left = ddx+'px';
    box.style.top = ddy+'px';
  }
}


// release list dropdown on VN pages

var rstat = [ 'Unknown', 'Pending', 'Obtained', 'On loan', 'Deleted' ];
var vstat = [ 'Unknown', 'Playing', 'Finished', 'Stalled', 'Dropped' ];
function rlDropDown(lnk) {
  var relid = lnk.id.substr(6);
  var st = getText(lnk).split(' / ');
  if(st[0].indexOf('loading') >= 0)
    return null;

  var rs = tag('ul', tag('li', tag('b', 'Release status')));
  var vs = tag('ul', tag('li', tag('b', 'Play status')));
  for(var i=0;i<rstat.length;i++) {
    if(st[0] && st[0].indexOf(rstat[i]) >= 0)
      rs.appendChild(tag('li', tag('i', rstat[i])));
    else
      rs.appendChild(tag('li', tag('a', {href:'#', rl_rid:relid, rl_act:'r'+i, onclick:rlMod}, rstat[i])));
  }
  for(var i=0;i<vstat.length;i++) {
    if(st[0] && st[0].indexOf(vstat[i]) >= 0)
      vs.appendChild(tag('li', tag('i', vstat[i])));
    else
      vs.appendChild(tag('li', tag('a', {href:'#', rl_rid:relid, rl_act:'v'+i, onclick:rlMod}, vstat[i])));
  }

  return tag('div', {class:'vrdd'}, rs, vs, st[0] == '--' ? null :
    tag('ul', {class:'full'}, tag('li', tag('a', {href:'#', rl_rid: relid, rl_act:'del', onclick:rlMod}, 'Remove from VN List')))
  );
}

function rlMod() {
  var lnk = byId('rlsel_'+this.rl_rid);
  ddHide();
  setContent(lnk, tag('b', {class: 'patch'}, 'loading...'));
  ajax('/xml/rlist.xml?id='+this.rl_rid+';e='+this.rl_act, function(hr) {
    // TODO: get rid of innerHTML here...
    lnk.innerHTML = hr.responseXML.getElementsByTagName('rlist')[0].firstChild.nodeValue;
  });
  return false;
}

{
  var l = byClass('a', 'vnrlsel');
  for(var i=0;i<l.length;i++)
    ddInit(l[i], 'left', rlDropDown);
}




/*  J A V A S C R I P T   T A B S  */

function jtInit() {
  if(!byId('jt_select'))
    return;
  var sel = '';
  var first = '';
  var l = byName(byId('jt_select'), 'a');
  if(l.length < 1)
    return;
  for(var i=0; i<l.length; i++) {
    l[i].onclick = jtSel;
    if(!first)
      first = l[i].id;
    if(location.hash && l[i].id == 'jt_sel_'+location.hash.substr(1))
      sel = l[i].id;
  }
  if(!sel)
    sel = first;
  jtSel(sel, 1);
}

function jtSel(which, nolink) {
  which = typeof(which) == 'string' ? which : which && which.id ? which.id : this.id;
  which = which.substr(7);

  var l = byName(byId('jt_select'), 'a');
  for(var i=0;i<l.length;i++) {
    var name = l[i].id.substr(7);
    if(name != 'all')
      byId('jt_box_'+name).style.display = name == which || which == 'all' ? 'block' : 'none';
    var tab = l[i].parentNode;
    setClass(tab, 'tabselected', name == which);
  }

  if(!nolink)
    location.href = '#'+which;
  return false;
}

jtInit();




/*  V N   P A G E   T A G   S P O I L E R S  */

function tvsInit() {
  if(!byId('tagops'))
    return;
  var l = byName(byId('tagops'), 'a');
  for(var i=0;i<l.length; i++)
    l[i].onclick = tvsClick;
  tvsSet(getCookie('tagspoil'), true);
}

function tvsClick() {
  var sel;
  var l = byName(byId('tagops'), 'a');
  for(var i=0; i<l.length; i++)
    if(l[i] == this) {
      if(i < 3) {
        tvsSet(i, null);
        setCookie('tagspoil', i);
      } else
        tvsSet(null, i == 3 ? true : false);
    }
  return false;
}

function tvsSet(lvl, lim) {
  /* set/get level and limit to/from the links */
  var l = byName(byId('tagops'), 'a');
  for(var i=0; i<l.length; i++) {
    if(i < 3) { /* spoiler level */
      if(lvl != null)
        setClass(l[i], 'tsel', i == lvl);
      if(lvl == null && hasClass(l[i], 'tsel'))
        lvl = i;
    } else { /* display limit (3 = summary) */
      if(lim != null)
        setClass(l[i], 'tsel', lim == (i == 3));
      if(lim == null && hasClass(l[i], 'tsel'))
        lim = i == 3;
    }
  }

  /* update tag visibility */
  l = byName(byId('vntags'), 'span');
  lim = lim ? 15 : 999;
  var s=0;
  for(i=0;i<l.length;i++) {
    var thislvl = l[i].className.substr(6, 1);
    if(thislvl <= lvl && s < lim) {
      setClass(l[i], 'hidden', false);
      s++;
    } else
      setClass(l[i], 'hidden', true);
  }
  return false;
}

tvsInit();




/*  D A T E   I N P U T  */

var months = ['January','February','March','April','May','June','July','August','September','October','November','December'];

function dateLoad(obj) {
  var val = Math.floor(obj.value) || 0;
  val = [ Math.floor(val/10000), Math.floor(val/100)%100, val%100 ];

  var year = tag('select', {style: 'width: 70px', onchange: dateSerialize}, tag('option', {value:0}, '-year-'));
  for(var i=1980; i<=(new Date()).getFullYear()+5; i++)
    year.appendChild(tag('option', {value: i, selected: i==val[0]}, i));
  year.appendChild(tag('option', {value: 9999, selected: val[0]==9999}, 'TBA'));

  var month = tag('select', {style: 'width: 100px', onchange: dateSerialize}, tag('option', {value:99}, '-month-'));
  for(var i=1; i<=12; i++)
    month.appendChild(tag('option', {value: i, selected: i==val[1]}, months[i-1]));

  var day = tag('select', {style: 'width: 70px', onchange: dateSerialize}, tag('option', {value:99}, '-day-'));
  for(var i=1; i<=31; i++)
    day.appendChild(tag('option', {value: i, selected: i==val[2]}, i));

  obj.parentNode.insertBefore(tag('div', {date_obj: obj}, year, month, day), obj);
}

function dateSerialize() {
  var div = this.parentNode;
  var sel = byName(div, 'select');
  var val = [
    sel[0].options[sel[0].selectedIndex].value*1,
    sel[1].options[sel[1].selectedIndex].value*1,
    sel[2].options[sel[2].selectedIndex].value*1
  ];
  div.date_obj.value = val[0] == 0 ? 0 : val[0] == 9999 ? 99999999 : val[0]*10000+val[1]*100+(val[1]==99?99:val[2]);
  alert(div.date_obj.value);
}

{
  var l = byClass('input', 'dateinput');
  for(i=0; i<l.length; i++)
    dateLoad(l[i]);
}




/*  D R O P D O W N   S E A R C H  */

function dsInit(obj, url, trfunc, serfunc, retfunc, parfunc) {
  obj.setAttribute('autocomplete', 'off');
  obj.onkeydown = dsKeyDown;
  obj.onblur = function() { setTimeout(function () { byId('ds_box').style.top = '-500px'; }, 500) };
  obj.ds_returnFunc = retfunc;
  obj.ds_trFunc = trfunc;
  obj.ds_serFunc = serfunc;
  obj.ds_parFunc = parfunc;
  obj.ds_searchURL = url;
  obj.ds_selectedId = 0;
  obj.ds_dosearch = null;
  if(!byId('ds_box'))
    addBody(tag('div', {id: 'ds_box', style: 'position: absolute; top: -500px'}, tag('b', 'Loading...')));
}

function dsKeyDown(ev) {
  var c = document.layers ? ev.which : document.all ? event.keyCode : ev.keyCode;
  var obj = this;

  if(c == 9) // tab
    return true;

  // do some processing when the enter key has been pressed
  if(c == 13) {
    var frm = obj;
    while(frm && frm.nodeName.toLowerCase() != 'form')
      frm = frm.parentNode;
    if(frm) {
      var oldsubmit = frm.onsubmit;
      frm.onsubmit = function() { return false };
      setTimeout(function() { frm.onsubmit = oldsubmit }, 100);
    }

    if(obj.ds_selectedId != 0)
      obj.value = obj.ds_serFunc(byId('ds_box_'+obj.ds_selectedId).ds_itemData, obj);
    if(obj.ds_returnFunc)
      obj.ds_returnFunc();

    byId('ds_box').style.top = '-500px';
    setContent(byId('ds_box'), tag('b', 'Loading...'));
    obj.ds_selectedId = 0;
    if(obj.ds_dosearch) {
      clearTimeout(obj.ds_dosearch);
      obj.ds_dosearch = null;
    }

    return false;
  }

  // process up/down keys
  if(c == 38 || c == 40) {
    var l = byName(byId('ds_box'), 'tr');
    if(l.length < 1)
      return true;

    // get new selected id
    if(obj.ds_selectedId == 0) {
      if(c == 38) // up
        obj.ds_selectedId = l[l.length-1].id.substr(7);
      else
        obj.ds_selectedId = l[0].id.substr(7);
    } else {
      var sel = null;
      for(var i=0; i<l.length; i++)
        if(l[i].id == 'ds_box_'+obj.ds_selectedId) {
          if(c == 38) // up
            sel = i>0 ? l[i-1] : l[l.length-1];
          else
            sel = l[i+1] ? l[i+1] : l[0];
        }
      obj.ds_selectedId = sel.id.substr(7);
    }

    // set selected class
    for(var i=0; i<l.length; i++)
      setClass(l[i], 'selected', l[i].id == 'ds_box_'+obj.ds_selectedId);
    return true;
  }

  // perform search after a timeout
  if(obj.ds_dosearch)
    clearTimeout(obj.ds_dosearch);
  obj.ds_dosearch = setTimeout(function() {
    dsSearch(obj);
  }, 500);

  return true;
}

function dsSearch(obj) {
  var box = byId('ds_box');
  var val = obj.ds_parFunc ? obj.ds_parFunc(obj.value) : obj.value;

  clearTimeout(obj.ds_dosearch);
  obj.ds_dosearch = null;

  // hide the ds_box div
  if(val.length < 2) {
    box.style.top = '-500px';
    setContent(box, tag('b', 'Loading...'));
    obj.ds_selectedId = 0;
    return;
  }

  // position the div
  var ddx=0;
  var ddy=obj.offsetHeight;
  var o = obj;
  do {
    ddx += o.offsetLeft;
    ddy += o.offsetTop;
  } while(o = o.offsetParent);

  box.style.position = 'absolute';
  box.style.left = ddx+'px';
  box.style.top = ddy+'px';
  box.style.width = obj.offsetWidth+'px';

  // perform search
  ajax(obj.ds_searchURL + encodeURIComponent(val), function(hr) {
    dsResults(hr, obj);
  });
}

function dsResults(hr, obj) {
  var lst = hr.responseXML.getElementsByTagName('item');
  var box = byId('ds_box');
  if(lst.length < 1) {
    setContent(box, tag('b', 'No results...'));
    obj.selectedId = 0;
    return;
  }

  var tb = tag('tbody', null);
  for(var i=0; i<lst.length; i++) {
    var id = lst[i].getAttribute('id');
    var tr = tag('tr', {id: 'ds_box_'+id, ds_itemData: lst[i]} );
    setClass(tr, 'selected', obj.selectedId == id);

    tr.onmouseover = function() {
      obj.ds_selectedId = this.id.substr(7);
      var l = byName(box, 'tr');
      for(var j=0; j<l.length; j++)
        setClass(l[j], 'selected', l[j].id == 'ds_box_'+obj.ds_selectedId);
    };
    tr.onmousedown = function() {
      obj.value = obj.ds_serFunc(this.ds_itemData, obj);
      if(obj.ds_returnFunc)
        obj.ds_returnFunc();
      box.style.top = '-500px';
      obj.ds_selectedId = 0;
    };

    obj.ds_trFunc(lst[i], tr);
    tb.appendChild(tr);
  }
  setContent(box, tag('table', tb));

  if(obj.ds_selectedId != 0 && !byId('ds_box_'+obj.ds_selectedId))
    obj.ds_selectedId = 0;
}




/*  V I S U A L   N O V E L   R E L A T I O N S  (/v+/edit)  */

function vnrLoad() {
  // read the current relations
  var rels = byId('vnrelations').value.split('|||');
  for(var i=0; i<rels.length; i++) {
    var rel = rels[i].split(',', 3);
    vnrAdd(rel[0], rel[1], rel[2]);
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

function vnrAdd(rel, vid, title) {
  var sel = tag('select', {onchange: vnrSerialize});
  var ops = byName(byClass(byId('relation_new'), 'td', 'tc_rel')[0], 'select')[0].options;
  for(var i=0; i<ops.length; i++)
    sel.appendChild(tag('option', {value: ops[i].value, selected: ops[i].value==rel}, getText(ops[i])));

  byId('relation_tbl').appendChild(tag('tr', {id:'relation_tr_'+vid},
    tag('td', {class:'tc_vn'   }, 'v'+vid+':', tag('a', {href:'/v'+vid}, shorten(title, 40))),
    tag('td', {class:'tc_rel'  }, 'is a ', sel, ' of'),
    tag('td', {class:'tc_title'}, shorten(byId('title').value, 40)),
    tag('td', {class:'tc_add'  }, tag('a', {href:'#', onclick:vnrDel}, 'del'))
  ));

  vnrEmpty();
}

function vnrEmpty() {
  var tbl = byId('relation_tbl');
  if(byName(tbl, 'tr').length < 1)
    tbl.appendChild(tag('tr', {id:'relation_tr_none'}, tag('td', {colspan:4}, 'No relations selected.')));
  else if(byId('relation_tr_none'))
    tbl.removeChild(byId('relation_tr_none'));
}

function vnrSerialize() {
  var r = [];
  var trs = byName(byId('relation_tbl'), 'tr');
  for(var i=0; i<trs.length; i++) {
    var rel = byName(byClass(trs[i], 'td', 'tc_rel')[0], 'select')[0];
    r[r.length] = [
      rel.options[rel.selectedIndex].value,                      // relation
      trs[i].id.substr(12),                                      // vid
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
  var sel = byName(byClass(relnew, 'td', 'tc_rel')[0], 'select')[0];
  var lnk = byName(byClass(relnew, 'td', 'tc_add')[0], 'a')[0];
  var input = txt.value;

  if(!input.match(/^v[0-9]+/)) {
    alert('Visual novel textbox must start with an ID (e.g. v17)');
    return false;
  }

  txt.disabled = sel.disabled = true;
  txt.value = 'loading...';
  setText(lnk, 'loading...');

  ajax('/xml/vn.xml?q='+encodeURIComponent(input), function(hr) {
    txt.disabled = sel.disabled = false;
    txt.value = '';
    setText(lnk, 'add');

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert('Visual novel not found!');

    var id = items[0].getAttribute('id');
    if(byId('relation_tr_'+id))
      return alert('This visual novel has already been selected!');

    vnrAdd(sel.selectedIndex, id, items[0].firstChild.nodeValue);
    sel.selectedIndex = 0;
    vnrSerialize();
  });
  return false;
}

if(byId('vnrelations'))
  vnrLoad();




/*  M I S C   S T U F F  */

// search box
{
  var i = byId('sq');
  i.onfocus = function () {
    if(this.value == 'search') {
      this.value = '';
      this.style.fontStyle = 'normal'
    }
  };
  i.onblur = function () {
    if(this.value.length < 1) {
      this.value = 'search';
      this.style.fontStyle = 'italic'
    }
  };
}

// VN Voting (/v+)
if(byId('votesel')) {
  byId('votesel').onchange = function() {
    var s = this.options[this.selectedIndex].value;
    if(s == 1 && !confirm(
      "You are about to give this visual novel a 1 out of 10. This is a rather extreme rating, "
      +"meaning this game has absolutely nothing to offer, and that it's the worst game you have ever played.\n"
      +"Are you really sure this visual novel matches that description?"))
      return;
    if(s == 10 && !confirm(
      "You are about to give this visual novel a 10 out of 10. This is a rather extreme rating, "
      +"meaning this is one of the best visual novels you've ever played and it's unlikely "
      +"that any other game could ever be better than this one.\n"
      +"It is generally a bad idea to have more than three games in your vote list with this rating, choose carefully!"))
      return;
    if(s)
      location.href = location.href.replace(/\.[0-9]+/, '')+'/vote?v='+s;
  };
}

// Advanced search (/v/*, /r)
if(byId('advselect')) {
  byId('advselect').onclick = function() {
    var box = byId('advoptions');
    var hidden = !hasClass(box, 'hidden');
    setClass(box, 'hidden', hidden);
    setText(byName(this, 'i')[0], hidden ? collapsed_icon : expanded_icon);
    return false;
  };
}

// Spoiler filters -> cookie (/v/*)
if(byId('sp_0')) {
  byId('sp_0').onclick = function() { setCookie('tagspoil', 0) };
  byId('sp_1').onclick = function() { setCookie('tagspoil', 1) };
  byId('sp_2').onclick = function() { setCookie('tagspoil', 2) };
  var spoil = getCookie('tagspoil');
  byId('sp_'+(spoil == null ? 1 : spoil)).checked = true;
}

// NSFW VN image toggle (/v+)
if(byId('nsfw_show')) {
  var msg = byId('nsfw_show');
  var img = byId('nsfw_hid');
  byName(msg, 'a')[0].onclick = function() {
    msg.style.display = 'none';
    img.style.display = 'block';
    return false;
  };
  img.onclick = function() {
    msg.style.display = 'block';
    img.style.display = 'none';
  };
}

// NSFW toggle for screenshots (/v+)
if(byId('nsfwhide')) {
  byId('nsfwhide').onclick = function() {
    var shown = 0;
    var l = byName(byId('screenshots'), 'div');
    for(var i=0; i<l.length; i++) {
      if(hasClass(l[i], 'nsfw')) {
        var hidden = !hasClass(l[i], 'hidden');
        setClass(l[i], 'hidden', hidden);
        setClass(byName(l[i], 'a')[0], 'hidden', hidden); // for the image viewer
        if(!hidden)
          shown++;
      } else
        shown++;
    }
    setText(byId('nsfwshown'), shown);
    return false;
  };
}

// VN Wishlist dropdown box (/v+)
if(byId('wishsel')) {
  byId('wishsel').onchange = function() {
    if(this.selectedIndex != 0)
      location.href = location.href.replace(/\.[0-9]+/, '')
        +'/wish?s='+this.options[this.selectedIndex].value;
  };
}

// Release list dropdown box (/r+)
if(byId('listsel')) {
  byId('listsel').onchange = function() {
    if(this.selectedIndex != 0)
      location.href = location.href.replace(/\.[0-9]+/, '')
        +'/list?e='+this.options[this.selectedIndex].value;
  };
}

// BBCode spoiler tags
{
  var l = byClass('b', 'spoiler');
  for(var i=0; i<l.length; i++) {
    l[i].onmouseover = function() { setClass(this, 'spoiler', false); setClass(this, 'spoiler_shown', true)  };
    l[i].onmouseout = function()  { setClass(this, 'spoiler', true);  setClass(this, 'spoiler_shown', false) };
  }
}

// vndb.org domain check
if(location.hostname != 'vndb.org') {
  addBody(tag('div', {id:'debug'},
    tag('h2', 'This is not VNDB!'),
    'The real VNDB is ',
    tag('a', {href:'http://vndb.org/'}, 'here'),
    '.'
  ));
}

// make some fields readonly when patch flag is set (/r+/edit)
if(byId('jt_box_rel_geninfo')) {
  var func = function() {
    byId('doujin').disabled =
      byId('resolution').disabled =
      byId('voiced').disabled =
      byId('ani_story').disabled =
      byId('ani_ero').disabled =
      byId('patch').checked;
  };
  func();
  byId('patch').onclick = func;
}

// Batch edit wishlist dropdown box (/u+/wish)
if(byId('batchedit')) {
  byId('batchedit').onchange = function() {
    if(this.selectedIndex == 0)
      return true;
    var frm = this;
    while(frm.nodeName.toLowerCase() != 'form')
      frm = frm.parentNode;
    frm.submit();
  };
}

// expand/collapse listings (/*/hist, /u+/posts)
if(byId('expandlist')) {
  var lnk = byId('expandlist');
  setexpand = function() {
    var exp = getCookie('histexpand') == 1;
    setText(lnk, exp ? 'collapse' : 'expand');
    var tbl = lnk;
    while(tbl.nodeName.toLowerCase() != 'table')
      tbl = tbl.parentNode;
    var l = byClass(tbl, 'tr', 'collapse');
    for(var i=0; i<l.length; i++)
      setClass(l[i], 'hidden', !exp);
  };
  setexpand();
  lnk.onclick = function () {
    setCookie('histexpand', getCookie('histexpand') == 1 ? 0 : 1);
    setexpand();
    return false;
  };
}

// collapse/expand row groups (/u+/tags, /u+/list) (limited to one table on a page)
if(byId('expandall')) {
  var table = byId('expandall');
  while(table.nodeName.toLowerCase() != 'table')
    table = table.parentNode;
  var heads = byClass(table, 'td', 'collapse_but');
  var allhid = false;

  var alltoggle = function() {
    allhid = !allhid;
    var l = byClass(table, 'tr', 'collapse');
    for(var i=0; i<l.length; i++)
      setClass(l[i], 'hidden', allhid);
    setText(byName(byId('expandall'), 'i')[0], allhid ? collapsed_icon : expanded_icon);
    for(var i=0; i<heads.length; i++)
      setText(byName(heads[i], 'i')[0], allhid ? collapsed_icon : expanded_icon);
    return false;
  }
  byId('expandall').onclick = alltoggle;
  alltoggle();

  var singletoggle = function() {
    var l = byClass(table, 'tr', 'collapse_'+this.id);
    if(l.length < 1)
      return;
    var hid = !hasClass(l[0], 'hidden');
    for(var i=0; i<l.length; i++)
      setClass(l[i], 'hidden', hid);
    setText(byName(this, 'i')[0], hid ? collapsed_icon : expanded_icon);
  };
  for(var i=0; i<heads.length; i++)
    heads[i].onclick = singletoggle;
}

// auto-complete tag search (/v/*)
if(byId('advselect') && byId('ti')) {
  var trfunc = function(item, tr) {
    tr.appendChild(tag('td', shorten(item.firstChild.nodeValue, 40),
      item.getAttribute('meta') == 'yes' ? tag('b', {class: 'grayedout'}, ' meta') : null,
      item.getAttribute('state') == 0    ? tag('b', {class: 'grayedout'}, ' awaiting moderation') : null
    ));
  };
  var serfunc = function(item, obj) {
    var tags = obj.value.split(/ *, */);
    tags[tags.length-1] = item.firstChild.nodeValue;
    return tags.join(', ');
  };
  var retfunc = function() { false; };
  var parfunc = function(val) {
    return (val.split(/, */))[val.split(/, */).length-1];
  };
  dsInit(byId('ti'), '/xml/tags.xml?q=', trfunc, serfunc, retfunc, parfunc);
  dsInit(byId('te'), '/xml/tags.xml?q=', trfunc, serfunc, retfunc, parfunc);
}


// spam protection on all forms
setTimeout(function() {
  for(i=1; i<document.forms.length; i++)
    document.forms[i].action = document.forms[i].action.replace(/\/nospam\?/,'');
}, 500);



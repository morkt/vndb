/* function/attribute prefixes:
 *  ctr  -> Character <-> trait linking
 *  cvn  -> Character <-> VN linking
 *  date -> Date selector
 *  dd   -> dropdown
 *  ds   -> dropdown search
 *  fil  -> Filter selector
 *  iv   -> image viewer
 *  jt   -> Javascript Tabs
 *  med  -> Release media selector
 *  prr  -> Producer relation editor
 *  rl   -> Release List dropdown
 *  rpr  -> Release <-> producer linking
 *  rvn  -> Release <-> visual novel linking
 *  scr  -> VN screenshot uploader
 *  tgl  -> VN tag linking
 *  tvs  -> VN page tag spoilers
 *  vnr  -> VN relation editor
 */

/* Internationalization note:
 *   The translation keys to be inserted in the header of this file are parsed
 *   from the source code. So when using mt(), make sure it is in the following
 *   format:
 *     mt('<exact translation key>',<more arguments>
 *   or
 *     mt('<exact translation key>')
 *   The single quotes and (lack of) spaces are significant!
 *
 *   To use non-exact translation keys as argument to mt(), make sure to
 *   indicate which keys should be inserted in the header by adding a comment
 *   containing the following format:
 *     l10n /<perl regex>/
 *   any keys matching that regex will be included.
 *
 *   In the case of an mt('<key>') without any extra arguments, the entire
 *   function call may be replaced by the TL string. In such a case mt()
 *   behaves similar to a preprocessor macro in C.
 */
var expanded_icon = '▾';
var collapsed_icon = '▸';

/*  M I N I M A L   J A V A S C R I P T   L I B R A R Y  */

var http_request = false;
function ajax(url, func, async) {
  if(!async && http_request)
    http_request.abort();
  var req = (window.ActiveXObject) ? new ActiveXObject('Microsoft.XMLHTTP') : new XMLHttpRequest();
  if(req == null)
    return alert("Your browser does not support the functionality this website requires.");
  if(!async)
    http_request = req;
  req.onreadystatechange = function() {
    if(!req || req.readyState != 4 || !req.responseText)
      return;
    if(req.status != 200)
      return alert('Whoops, error! :(');
    func(req);
  };
  url += (url.indexOf('?')>=0 ? ';' : '?')+(Math.floor(Math.random()*999)+1);
  req.open('GET', url, true);
  req.send(null);
}

function setCookie(n,v) {
  var date = new Date();
  date.setTime(date.getTime()+(365*24*60*60*1000));
  document.cookie = cookie_prefix+n+'='+v+'; expires='+date.toGMTString()+'; path=/';
}
function getCookie(n) {
  var l = document.cookie.split(';');
  n = cookie_prefix+n;
  for(var i=0; i<l.length; i++) {
    var c = l[i];
    while(c.charAt(0) == ' ')
      c = c.substring(1,c.length);
    if(c.indexOf(n+'=') == 0)
      return c.substring(n.length+1,c.length);
  }
  return null;
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
  var t = arguments.length == 2 && typeof arguments[0] == 'string' ? arguments[0] : arguments.length == 3 ? arguments[1] : '*';
  var c = arguments[arguments.length-1];
  var l = byName(par, t);
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
          el[ attr == 'class' ? 'className' : attr == 'for' ? 'htmlFor' : attr ] = arguments[i][attr];
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
function setContent() {
  setText(arguments[0], '');
  for(var i=1; i<arguments.length; i++)
    if(arguments[i] != null)
      arguments[0].appendChild(tag(arguments[i]));
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

/* maketext function, less powerful than the Perl equivalent:
 * - Only supports [_n], ~[, ~]
 * - When it finds [quant,_n,..], it will only return the first argument (and doesn't support ~ in an argument)
 * assumes that a TL structure called 'L10N_STR' is defined in the header of this file */
function mt() {
  var key = arguments[0];
  var val = L10N_STR[key] ? L10N_STR[key] : key;
  for(var i=1; i<arguments.length; i++) {
    var expr = '[_'+i+']';
    while(val.indexOf(expr) >= 0)
      val = val.replace(expr, arguments[i]);
  }
  val = val.replace(/\[quant,_\d+\,([^,]+)[^\]]+\]/g, "$1");
  while(val.indexOf('~[') >= 0 || val.indexOf('~]') >= 0)
    val = val.replace('~[', '[').replace('~]', ']');
  return val;
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
    addBody(tag('div', {id: 'iv_view','class':'hidden'},
      tag('b', {id:'ivimg'}, ''),
      tag('br', null),
      tag('a', {href:'#', id:'ivfull'}, ''),
      tag('a', {href:'#', onclick: ivClose, id:'ivclose'}, mt('_js_close')),
      tag('a', {href:'#', onclick: ivView, id:'ivprev'}, '« '+mt('_js_iv_prev')),
      tag('a', {href:'#', onclick: ivView, id:'ivnext'}, mt('_js_iv_next')+' »')
    ));
    addBody(tag('b', {id:'ivimgload','class':'hidden'}, mt('_js_loading')));
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
      if(ol[i].rel.substr(0,3) == 'iv:' && ol[i].rel.indexOf(':'+opt[2]) > 4 && !hasClass(ol[i], 'hidden') && ol[i].id != 'ivprev' && ol[i].id != 'ivnext')
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
  setClass(view, 'hidden', false);
  setContent(byId('ivimg'), tag('img', {src:u, onclick:ivClose,
    onload: function() { setClass(byId('ivimgload'), 'hidden', true); },
    style: 'width: '+w+'px; height: '+h+'px'
  }));
  view.style.width = dw+'px';
  view.style.height = dh+'px';
  view.style.left = ((ww - dw) / 2 - 10)+'px';
  view.style.top = ((wh - dh) / 2 + st - 20)+'px';
  byId('ivimgload').style.left = ((ww - 100) / 2 - 10)+'px';
  byId('ivimgload').style.top = ((wh - 20) / 2 + st)+'px';
  setClass(byId('ivimgload'), 'hidden', false);
  return false;
}

function ivClose() {
  setClass(byId('iv_view'), 'hidden', true);
  setClass(byId('ivimgload'), 'hidden', true);
  setText(byId('ivimg'), '');
  return false;
}

ivInit();




/*  D R O P D O W N  */

function ddInit(obj, align, contents) {
  obj.dd_align = align; // see ddRefresh for details
  obj.dd_contents = contents;
  document.onmousemove = ddMouseMove;
  document.onscroll = ddHide;
  if(!byId('dd_box'))
    addBody(tag('div', {id:'dd_box', 'class':'hidden', dd_used: false}));
}

function ddHide() {
  var box = byId('dd_box');
  setText(box, '');
  setClass(box, 'hidden', true);
  box.dd_used = false;
  box.dd_lnk = null;
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
    if((mouseX < box.dd_x-10 || mouseX > box.dd_x+box.offsetWidth+10 || mouseY < box.dd_y-10 || mouseY > box.dd_y+box.offsetHeight+10)
        || (lnk && lnk == box.dd_lnk))
      ddHide();
  }

  if(!box.dd_used && lnk || box.dd_used && lnk && box.dd_lnk != lnk) {
    box.dd_lnk = lnk;
    box.dd_used = true;
    if(!ddRefresh())
      ddHide();
  }
}

function ddRefresh() {
  var box = byId('dd_box');
  if(!box.dd_used)
    return false;
  var lnk = box.dd_lnk;
  var content = lnk.dd_contents(lnk, box);
  if(content == null)
    return false;
  setContent(box, content);
  setClass(box, 'hidden', false);

  var o = lnk;
  ddx = ddy = 0;
  do {
    ddx += o.offsetLeft;
    ddy += o.offsetTop;
  } while(o = o.offsetParent);

  if(lnk.dd_align == 'left')
    ddx -= box.offsetWidth;
  if(lnk.dd_align == 'tagmod')
    ddx += lnk.offsetWidth-35;
  if(lnk.dd_align == 'bottom')
    ddy += lnk.offsetHeight;
  box.dd_x = ddx;
  box.dd_y = ddy;
  box.style.left = ddx+'px';
  box.style.top = ddy+'px';
  return true;
}


// release list dropdown on VN pages

function rlDropDown(lnk) {
  var relid = lnk.id.substr(6);
  var st = getText(lnk);
  if(st == mt('_js_loading'))
    return null;

  var o = tag('ul', null);
  for(var i=0; i<rlist_status.length; i++) {
    var val = rlist_status[i] == 0 ? mt('_unknown') : mt('_rlist_status_'+rlist_status[i]); // l10n /_rlist_status_\d+/
    if(st == val)
      o.appendChild(tag('li', tag('i', val)));
    else
      o.appendChild(tag('li', tag('a', {href:'#', rl_rid:relid, rl_act:rlist_status[i], onclick:rlMod}, val)));
  }
  if(st != '--')
    o.appendChild(tag('li', tag('a', {href:'#', rl_rid:relid, rl_act:-1, onclick:rlMod}, mt('_vnpage_uopt_reldel'))));

  return tag('div', o);
}

function rlMod() {
  var lnk = byId('rlsel_'+this.rl_rid);
  var code = getText(byId('vnrlist_code'));
  var act = this.rl_act;
  ddHide();
  setContent(lnk, tag('b', {'class': 'grayedout'}, mt('_js_loading')));
  ajax('/xml/rlist.xml?formcode='+code+';id='+this.rl_rid+';e='+act, function(hr) {
    setText(lnk, act == -1 ? '--' : act == 0 ? mt('_unknown') : mt('_rlist_status_'+act));
  });
  return false;
}

if(byId('vnrlist_code')) {
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
  tvsSet(getCookie('tagspoil'), true, (getCookie('tagcat')||'cont,tech').split(','));
}

function tvsClick() {
  var sel;
  var l = byName(byId('tagops'), 'a');
  for(var i=0; i<l.length; i++)
    if(l[i] == this) {
      if(i < 3) { /* categories */
        setClass(l[i], 'tsel', !hasClass(l[i], 'tsel'));
        var c = tvsSet();
        setCookie('tagcat', c.length ? c.join(',') : '-');
      } else if(i < 6) { /* spoiler level */
        tvsSet(i-3, null);
        setCookie('tagspoil', i-3);
      } else /* limit */
        tvsSet(null, i == 6 ? true : false);
    }
  return false;
}

function tvsSet(lvl, lim, cats) {
  /* set/get level and limit to/from the links */
  var l = byName(byId('tagops'), 'a');
  var cat = cats || [];
  for(var i=0; i<l.length; i++) {
    if(i < 3) { /* categories */
      var c = l[i].href.substr(l[i].href.indexOf('#')+1);
      if(cats) {
        for(var j=0; j<cats.length && c != cats[j]; j++) ;
        setClass(l[i], 'tsel', j != cats.length);
      } else {
        if(hasClass(l[i], 'tsel'))
          cat.push(c);
      }
    } else if(i < 6) { /* spoiler level */
      if(lvl != null)
        setClass(l[i], 'tsel', i-3 == lvl);
      if(lvl == null && hasClass(l[i], 'tsel'))
        lvl = i-3;
    } else { /* display limit (6 = summary) */
      if(lim != null)
        setClass(l[i], 'tsel', lim == (i == 6));
      if(lim == null && hasClass(l[i], 'tsel'))
        lim = i == 6;
    }
  }

  /* update tag visibility */
  l = byName(byId('vntags'), 'span');
  lim = lim ? 15 : 999;
  var s=0;
  for(i=0;i<l.length;i++) {
    var thislvl = l[i].className.substr(6, 1);
    for(var j=0; j<cat.length && !hasClass(l[i], 'cat_'+cat[j]); j++) ;
    if(thislvl <= lvl && s < lim && j != cat.length) {
      setClass(l[i], 'hidden', false);
      s++;
    } else
      setClass(l[i], 'hidden', true);
  }
  return cat;
}

tvsInit();




/*  D A T E   I N P U T  */

function dateLoad(obj, serfunc) {
  var year = tag('select', {style: 'width: 70px', onfocus:serfunc, onchange: dateSerialize, tabIndex: 10},
    tag('option', {value:0}, mt('_js_date_year')),
    tag('option', {value: 9999}, 'TBA')
  );
  for(var i=(new Date()).getFullYear()+5; i>=1980; i--)
    year.appendChild(tag('option', {value: i}, i));

  var month = tag('select', {style: 'width: 70px', onfocus:serfunc, onchange: dateSerialize, tabIndex: 10},
    tag('option', {value:99}, mt('_js_date_month'))
  );
  for(var i=1; i<=12; i++)
    month.appendChild(tag('option', {value: i}, i));

  var day = tag('select', {style: 'width: 70px', onfocus:serfunc, onchange: dateSerialize, tabIndex: 10},
    tag('option', {value:99}, mt('_js_date_day'))
  );
  for(var i=1; i<=31; i++)
    day.appendChild(tag('option', {value: i}, i));

  var div = tag('div', {date_obj: obj, date_serfunc: serfunc, date_val: obj ? obj.value : 0}, year, month, day);
  dateSet(div, obj ? obj.value : 0);
  return obj ? obj.parentNode.insertBefore(div, obj) : div;
}

function dateSet(div, val) {
  val = typeof val == 'object' ? val[0] : val;
  val = Math.floor(val) || 0;
  val = [ Math.floor(val/10000), Math.floor(val/100)%100, val%100 ];
  if(val[1] == 0) val[1] = 99;
  if(val[2] == 0) val[2] = 99;
  var l = byName(div, 'select');
  for(var i=0; i<l.length; i++)
    for(var j=0; j<l[i].options.length; j++)
      l[i].options[j].selected = l[i].options[j].value == val[i];
  dateSerialize(div.childNodes[0], true);
}

function dateSerialize(div, nonotify) {
  var div = div && div.parentNode ? div.parentNode : this.parentNode;
  var sel = byName(div, 'select');
  var val = [
    sel[0].options[sel[0].selectedIndex].value*1,
    sel[1].options[sel[1].selectedIndex].value*1,
    sel[2].options[sel[2].selectedIndex].value*1
  ];
  div.date_val = val[0] == 0 ? 0 : val[0] == 9999 ? 99999999 : val[0]*10000+val[1]*100+(val[1]==99?99:val[2]);
  if(div.date_obj)
    div.date_obj.value = div.date_val;
  if(!nonotify && div.date_serfunc)
    div.date_serfunc(div);
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
  obj.onblur = function() { setTimeout(function () { setClass(byId('ds_box'), 'hidden', true) }, 500) };
  obj.ds_returnFunc = retfunc;
  obj.ds_trFunc = trfunc;
  obj.ds_serFunc = serfunc;
  obj.ds_parFunc = parfunc;
  obj.ds_searchURL = url;
  obj.ds_selectedId = 0;
  obj.ds_dosearch = null;
  if(!byId('ds_box'))
    addBody(tag('div', {id: 'ds_box', 'class':'hidden'}, tag('b', mt('_js_loading'))));
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
      obj.ds_returnFunc(obj);

    setClass(byId('ds_box'), 'hidden', true);
    setContent(byId('ds_box'), tag('b', mt('_js_loading')));
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
    setClass(box, 'hidden', true);
    setContent(box, tag('b', mt('_js_loading')));
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
  setClass(box, 'hidden', false);

  // perform search
  ajax(obj.ds_searchURL + encodeURIComponent(val), function(hr) {
    dsResults(hr, obj);
  });
}

function dsResults(hr, obj) {
  var lst = hr.responseXML.getElementsByTagName('item');
  var box = byId('ds_box');
  if(lst.length < 1) {
    setContent(box, tag('b', mt('_js_ds_noresults')));
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
      setClass(box, 'hidden', true);
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
  for(var i=0; i<rels.length && rels[0].length>1; i++) {
    var rel = rels[i].split(',', 4);
    vnrAdd(rel[0], rel[1], rel[2]==1?true:false, rel[3]);
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

function vnrAdd(rel, vid, official, title) {
  var sel = tag('select', {onchange: vnrSerialize});
  var ops = byName(byClass(byId('relation_new'), 'td', 'tc_rel')[0], 'select')[0].options;
  for(var i=0; i<ops.length; i++)
    sel.appendChild(tag('option', {value: ops[i].value, selected: ops[i].value==rel}, getText(ops[i])));

  byId('relation_tbl').appendChild(tag('tr', {id:'relation_tr_'+vid},
    tag('td', {'class':'tc_vn'   }, 'v'+vid+':', tag('a', {href:'/v'+vid}, shorten(title, 40))),
    tag('td', {'class':'tc_rel'  },
      mt('_vnedit_rel_isa')+' ',
      tag('input', {type: 'checkbox', onclick:vnrSerialize, id:'official_'+vid, checked:official}),
      tag('label', {'for':'official_'+vid}, mt('_vnedit_rel_official')),
      sel, ' '+mt('_vnedit_rel_of')),
    tag('td', {'class':'tc_title'}, shorten(byId('title').value, 40)),
    tag('td', {'class':'tc_add'  }, tag('a', {href:'#', onclick:vnrDel}, mt('_js_remove')))
  ));

  vnrEmpty();
}

function vnrEmpty() {
  var tbl = byId('relation_tbl');
  if(byName(tbl, 'tr').length < 1)
    tbl.appendChild(tag('tr', {id:'relation_tr_none'}, tag('td', {colspan:4}, mt('_vnedit_rel_none'))));
  else if(byId('relation_tr_none'))
    tbl.removeChild(byId('relation_tr_none'));
}

function vnrSerialize() {
  var r = [];
  var trs = byName(byId('relation_tbl'), 'tr');
  for(var i=0; i<trs.length; i++) {
    if(trs[i].id == 'relation_tr_none')
      continue;
    var rel = byName(byClass(trs[i], 'td', 'tc_rel')[0], 'select')[0];
    r[r.length] = [
      rel.options[rel.selectedIndex].value,                      // relation
      trs[i].id.substr(12),                                      // vid
      byName(byClass(trs[i], 'td', 'tc_rel')[0], 'input')[0].checked ? '1' : '0', // official
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
  var off = byName(byClass(relnew, 'td', 'tc_rel')[0], 'input')[0];
  var sel = byName(byClass(relnew, 'td', 'tc_rel')[0], 'select')[0];
  var lnk = byName(byClass(relnew, 'td', 'tc_add')[0], 'a')[0];
  var input = txt.value;

  if(!input.match(/^v[0-9]+/)) {
    alert(mt('_vnedit_rel_findformat'));
    return false;
  }

  txt.disabled = sel.disabled = off.disabled = true;
  txt.value = mt('_js_loading');
  setText(lnk, mt('_js_loading'));

  ajax('/xml/vn.xml?q='+encodeURIComponent(input), function(hr) {
    txt.disabled = sel.disabled = off.disabled = false;
    txt.value = '';
    setText(lnk, mt('_js_add'));

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert(mt('_vnedit_rel_novn'));

    var id = items[0].getAttribute('id');
    if(byId('relation_tr_'+id))
      return alert(mt('_vnedit_rel_double'));

    vnrAdd(sel.options[sel.selectedIndex].value, id, off.checked, items[0].firstChild.nodeValue);
    sel.selectedIndex = 0;
    vnrSerialize();
  });
  return false;
}

if(byId('vnrelations'))
  vnrLoad();




/*  R E L E A S E   M E D I A  (/r+/edit)  */

var medTypes = [ ];
function medLoad() {
  // load the medTypes and clear the div
  var sel = byName(byId('media_div'), 'select')[0].options;
  for(var i=0; i<sel.length; i++)
    medTypes[medTypes.length] = [ sel[i].value, getText(sel[i]), !hasClass(sel[i], 'noqty') ];
  setText(byId('media_div'), '');

  // load the selected media
  var med = byId('media').value.split(',');
  for(var i=0; i<med.length && med[i].length > 1; i++)
    medAdd(med[i].split(' ')[0], Math.floor(med[i].split(' ')[1]));

  medAdd('', 0);
}

function medAdd(med, qty) {
  var qsel = tag('select', {'class':'qty', onchange:medSerialize}, tag('option', {value:0}, mt('_redit_form_med_quantity')));
  for(var i=1; i<=20; i++)
    qsel.appendChild(tag('option', {value:i, selected: qty==i}, i));

  var msel = tag('select', {'class':'medium', onchange: med == '' ? medFormAdd : medSerialize});
  if(med == '')
    msel.appendChild(tag('option', {value:''}, mt('_redit_form_med_medium')));
  for(var i=0; i<medTypes.length; i++)
    msel.appendChild(tag('option', {value:medTypes[i][0], selected: med==medTypes[i][0]}, medTypes[i][1]));

  byId('media_div').appendChild(tag('span', qsel, msel,
    med != '' ? tag('input', {type: 'button', 'class':'submit', onclick:medDel, value:mt('_js_remove')}) : null
  ));
}

function medDel() {
  var span = this;
  while(span.nodeName.toLowerCase() != 'span')
    span = span.parentNode;
  byId('media_div').removeChild(span);
  medSerialize();
  return false;
}

function medFormAdd() {
  var span = this;
  while(span.nodeName.toLowerCase() != 'span')
    span = span.parentNode;
  var med = byClass(span, 'select', 'medium')[0];
  var qty = byClass(span, 'select', 'qty')[0];
  if(!med.selectedIndex)
    return;
  medAdd(med.options[med.selectedIndex].value, qty.options[qty.selectedIndex].value);
  byId('media_div').removeChild(span);
  medAdd('', 0);
  medSerialize();
}

function medSerialize() {
  var r = [];
  var meds = byName(byId('media_div'), 'span');
  for(var i=0; i<meds.length-1; i++) {
    var med = byClass(meds[i], 'select', 'medium')[0];
    var qty = byClass(meds[i], 'select', 'qty')[0];

    /* correct quantity if necessary */
    if(medTypes[med.selectedIndex][2] && !qty.selectedIndex)
      qty.selectedIndex = 1;
    if(!medTypes[med.selectedIndex][2] && qty.selectedIndex)
      qty.selectedIndex = 0;

    r[r.length] = medTypes[med.selectedIndex][0] + ' ' + qty.selectedIndex;
  }
  byId('media').value = r.join(',');
}

if(byId('jt_box_rel_format'))
  medLoad();




/*  V I S U A L   N O V E L   S C R E E N S H O T   U P L O A D E R  (/v+/edit)  */

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
  for(i=0; i<scr.length && scr[i].length>1; i++) {
    var r = scr[i].split(',');
    scrSet(scrAdd(r[0], r[1], r[2]), VNEDITSCR[r[0]][0], VNEDITSCR[r[0]][1]);
  }

  ivInit();
  scrLast();
  scrSetSubmit();
}

function scrSetSubmit() {
  var frm = byId('screenshots');
  while(frm.nodeName.toLowerCase() != 'form')
    frm = frm.parentNode;
  oldfunc = frm.onsubmit;
  frm.onsubmit = function() {
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
    } else if(oldfunc)
      return oldfunc();
  };
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
  for(var j=0; j<resolutions.length && odd; j++) {
    if(typeof resolutions[j][1] != 'object') {
      if(resolutions[j][0] == dim)
        odd = false;
    } else {
      for(var k=1; k<resolutions[j].length; k++)
        if(resolutions[j][k][1] == dim)
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




/*  V I S U A L   N O V E L   T A G   L I N K I N G  (/v+/tagmod)  */

var tglSpoilers = [];

function tglLoad() {
  for(var i=0; i<=3; i++)
    tglSpoilers[i] = mt('_spoil_'+(i-1)); // l10n /_spoil_-?\d+/

  // tag dropdown search
  dsInit(byId('tagmod_tag'), '/xml/tags.xml?q=', function(item, tr) {
    tr.appendChild(tag('td',
      shorten(item.firstChild.nodeValue, 40),
      item.getAttribute('meta') == 'yes' ? tag('b', {'class':'grayedout'}, ' '+mt('_js_ds_tag_meta')) :
      item.getAttribute('state') == 0    ? tag('b', {'class':'grayedout'}, ' '+mt('_js_ds_tag_mod')) : null
    ));
  }, function(item) {
    return item.firstChild.nodeValue;
  }, tglAdd);
  byId('tagmod_add').onclick = tglAdd;

  // JS'ify the voting bar and spoiler setting
  var trs = byName(byId('tagtable'), 'tr');
  for(var i=0; i<trs.length; i++) {
    if(hasClass(trs[i], 'tagmod_cat'))
      continue;
    var vote = byClass(trs[i], 'td', 'tc_myvote')[0];
    vote.tgl_vote = getText(vote)*1;
    tglVoteBar(vote);

    var spoil = byClass(trs[i], 'td', 'tc_myspoil')[0];
    spoil.tgl_spoil = getText(spoil)*1+1;
    setText(spoil, tglSpoilers[spoil.tgl_spoil]);
    ddInit(spoil, 'tagmod', tglSpoilDD);
    spoil.onclick = tglSpoilNext;
  }
  tglSerialize();
}

function tglSpoilNext() {
  if(++this.tgl_spoil >= tglSpoilers.length)
    this.tgl_spoil = 0;
  setText(this, tglSpoilers[this.tgl_spoil]);
  tglSerialize();
  ddRefresh();
}

function tglSpoilDD(lnk) {
  var lst = tag('ul', null);
  for(var i=0; i<tglSpoilers.length; i++)
    lst.appendChild(tag('li', i == lnk.tgl_spoil
      ? tag('i', tglSpoilers[i])
      : tag('a', {href: '#', onclick:tglSpoilSet, tgl_td:lnk, tgl_sp:i}, tglSpoilers[i])
    ));
  return lst;
}

function tglSpoilSet() {
  this.tgl_td.tgl_spoil = this.tgl_sp;
  setText(this.tgl_td, tglSpoilers[this.tgl_sp]);
  ddHide();
  tglSerialize();
  return false;
}

function tglVoteBar(td, vote) {
  setText(td, '');
  for(var i=-3; i<=3; i++)
    td.appendChild(tag('a', {
      'class':'taglvl taglvl'+i, tgl_num: i,
      onmouseover:tglVoteBarSel, onmouseout:tglVoteBarSel, onclick:tglVoteBarSel
    }, ' '));
  tglVoteBarSel(td, td.tgl_vote);
  return false;
}

function tglVoteBarSel(td, vote) {
  // nasty trick to make this function multifunctional
  if(this && this.tgl_num != null) {
    var e = td || window.event;
    td = this.parentNode;
    vote = this.tgl_num;
    if(e.type.toLowerCase() == 'click') {
      td.tgl_vote = vote;
      tglSerialize();
    }
    if(e.type.toLowerCase() == 'mouseout')
      vote = td.tgl_vote;
  }
  var l = byName(td, 'a');
  var num;
  for(var i=0; i<l.length; i++) {
    num = l[i].tgl_num;
    if(num == 0)
      setText(l[i], vote || '-');
    else
      setClass(l[i], 'taglvlsel', num<0&&vote<=num || num>0&&vote>=num);
  }
}

function tglAdd() {
  var tg = byId('tagmod_tag');
  var add = byId('tagmod_add');
  tg.disabled = add.disabled = true;
  add.value = mt('_js_loading');

  ajax('/xml/tags.xml?q=name:'+encodeURIComponent(tg.value), function(hr) {
    tg.disabled = add.disabled = false;
    tg.value = '';
    add.value = mt('_tagv_add');

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert(mt('_tagv_notfound'));
    if(items[0].getAttribute('meta') == 'yes')
      return alert(mt('_js_ds_tag_nometa'));

    var name = items[0].firstChild.nodeValue;
    var id = items[0].getAttribute('id');
    if(byId('tgl_'+id))
      return alert(mt('_tagv_double'));

    if(!byId('tagmod_newtags'))
      byId('tagtable').appendChild(tag('tr', {'class':'tagmod_cat', id:'tagmod_newtags'},
        tag('td', {colspan:7}, mt('_tagv_newlyadded'))));

    var vote = tag('td', {'class':'tc_myvote', tgl_vote: 2}, '');
    tglVoteBar(vote);
    var spoil = tag('td', {'class':'tc_myspoil', tgl_spoil: 0}, tglSpoilers[0]);
    ddInit(spoil, 'tagmod', tglSpoilDD);
    spoil.onclick = tglSpoilNext;

    var ismod = byClass(byId('tagtable').parentNode, 'td', 'tc_myover').length;

    byId('tagtable').appendChild(tag('tr', {id:'tgl_'+id},
      tag('td', {'class':'tc_tagname'}, tag('a', {href:'/g'+id}, name)),
      vote,
      ismod ? tag('td', {'class':'tc_myover'}, ' ') : null,
      spoil,
      tag('td', {'class':'tc_allvote'}, ' '),
      tag('td', {'class':'tc_allspoil'}, ' '),
      tag('td', {'class':'tc_allwho'}, '')
    ));
    tglSerialize();
  });
}

function tglSerialize() {
  var r = [];
  var l = byName(byId('tagtable'), 'tr');
  for(var i=0; i<l.length; i++) {
    if(hasClass(l[i], 'tagmod_cat'))
      continue;
    var vote = byClass(l[i], 'td', 'tc_myvote')[0].tgl_vote;
    if(vote != 0)
      r[r.length] = [
        l[i].id.substr(4),
        vote,
        byClass(l[i], 'td', 'tc_myspoil')[0].tgl_spoil-1
      ].join(',');
  }
  byId('taglinks').value = r.join(' ');
}

if(byId('taglinks'))
  tglLoad();




/*  R E L E A S E  ->  V I S U A L   N O V E L   L I N K I N G  (/r+/edit)  */

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
    tag('td', {'class':'tc_rm'},    tag('a', {href:'#', onclick:rvnDel}, mt('_js_remove')))
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
    tbl.appendChild(tag('tr', {id:'rvn_tr_none'}, tag('td', {colspan:2}, mt('_redit_form_vn_none'))));
  else if(byId('rvn_tr_none'))
    tbl.removeChild(byId('rvn_tr_none'));
}

function rvnFormAdd() {
  var txt = byId('vn_input');
  var lnk = byId('vn_add');
  var val = txt.value;

  if(!val.match(/^v[0-9]+/)) {
    alert(mt('_redit_form_vn_vnformat'));
    return false;
  }

  txt.disabled = true;
  txt.value = mt('_js_loading');
  setText(lnk, mt('_js_loading'));

  ajax('/xml/vn.xml?q='+encodeURIComponent(val), function(hr) {
    txt.disabled = false;
    txt.value = '';
    setText(lnk, mt('_js_add'));

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert(mt('_redit_form_vn_notfound'));

    var id = items[0].getAttribute('id');
    if(byId('rvn_'+id))
      return alert(mt('_redit_form_vn_double'));

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




/*  R E L E A S E  ->  P R O D U C E R   L I N K I N G  (/r+/edit)  */

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
    tag('td', {'class':'tc_rm'},   tag('a', {href:'#', onclick:rprDel}, mt('_js_remove')))
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
    tbl.appendChild(tag('tr', {id:'rpr_tr_none'}, tag('td', {colspan:2}, mt('_redit_form_prod_none'))));
  else if(byId('rpr_tr_none'))
    tbl.removeChild(byId('rpr_tr_none'));
}

function rprFormAdd() {
  var txt = byId('producer_input');
  var lnk = byId('producer_add');
  var val = txt.value;

  if(!val.match(/^p[0-9]+/)) {
    alert(mt('_redit_form_prod_pformat'));
    return false;
  }

  txt.disabled = true;
  txt.value = mt('_js_loading');
  setText(lnk, mt('_js_loading'));

  ajax('/xml/producers.xml?q='+encodeURIComponent(val), function(hr) {
    txt.disabled = false;
    txt.value = '';
    setText(lnk, mt('_js_add'));

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert(mt('_redit_form_prod_notfound'));

    var id = items[0].getAttribute('id');
    if(byId('rpr_'+id))
      return alert(mt('_redit_form_prod_double'));

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




/*  P R O D U C E R   R E L A T I O N S  (/p+/edit)  */

function prrLoad() {
  // read the current relations
  var rels = byId('prodrelations').value.split('|||');
  for(var i=0; i<rels.length && rels[0].length>1; i++) {
    var rel = rels[i].split(',', 3);
    prrAdd(rel[0], rel[1], rel[2]);
  }
  prrEmpty();

  // bind the add-link
  byName(byClass(byId('relation_new'), 'td', 'tc_add')[0], 'a')[0].onclick = prrFormAdd;

  // dropdown
  dsInit(byName(byClass(byId('relation_new'), 'td', 'tc_prod')[0], 'input')[0], '/xml/producers.xml?q=', function(item, tr) {
    tr.appendChild(tag('td', { style: 'text-align: right; padding-right: 5px'}, 'p'+item.getAttribute('id')));
    tr.appendChild(tag('td', shorten(item.firstChild.nodeValue, 40)));
  }, function(item) {
    return 'p'+item.getAttribute('id')+':'+item.firstChild.nodeValue;
  }, prrFormAdd);
}

function prrAdd(rel, pid, title) {
  var sel = tag('select', {onchange: prrSerialize});
  var ops = byName(byClass(byId('relation_new'), 'td', 'tc_rel')[0], 'select')[0].options;
  for(var i=0; i<ops.length; i++)
    sel.appendChild(tag('option', {value: ops[i].value, selected: ops[i].value==rel}, getText(ops[i])));

  byId('relation_tbl').appendChild(tag('tr', {id:'relation_tr_'+pid},
    tag('td', {'class':'tc_prod' }, 'p'+pid+':', tag('a', {href:'/p'+pid}, shorten(title, 40))),
    tag('td', {'class':'tc_rel'  }, sel),
    tag('td', {'class':'tc_add'  }, tag('a', {href:'#', onclick:prrDel}, mt('_js_remove')))
  ));

  prrEmpty();
}

function prrEmpty() {
  var tbl = byId('relation_tbl');
  if(byName(tbl, 'tr').length < 1)
    tbl.appendChild(tag('tr', {id:'relation_tr_none'}, tag('td', {colspan:4}, mt('_pedit_rel_none'))));
  else if(byId('relation_tr_none'))
    tbl.removeChild(byId('relation_tr_none'));
}

function prrSerialize() {
  var r = [];
  var trs = byName(byId('relation_tbl'), 'tr');
  for(var i=0; i<trs.length; i++) {
    if(trs[i].id == 'relation_tr_none')
      continue;
    var rel = byName(byClass(trs[i], 'td', 'tc_rel')[0], 'select')[0];
    r[r.length] = [
      rel.options[rel.selectedIndex].value,
      trs[i].id.substr(12),
      getText(byName(byClass(trs[i], 'td', 'tc_prod')[0], 'a')[0])
    ].join(',');
  }
  byId('prodrelations').value = r.join('|||');
}

function prrDel() {
  var tr = this;
  while(tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  byId('relation_tbl').removeChild(tr);
  prrSerialize();
  prrEmpty();
  return false;
}

function prrFormAdd() {
  var relnew = byId('relation_new');
  var txt = byName(byClass(relnew, 'td', 'tc_prod')[0], 'input')[0];
  var sel = byName(byClass(relnew, 'td', 'tc_rel')[0],  'select')[0];
  var lnk = byName(byClass(relnew, 'td', 'tc_add')[0],  'a')[0];
  var input = txt.value;

  if(!input.match(/^p[0-9]+/)) {
    alert(mt('_pedit_rel_findformat'));
    return false;
  }

  txt.disabled = sel.disabled = true;
  txt.value = mt('_js_loading');
  setText(lnk, mt('_js_loading'));

  ajax('/xml/producers.xml?q='+encodeURIComponent(input), function(hr) {
    txt.disabled = sel.disabled = false;
    txt.value = '';
    setText(lnk, mt('_js_add'));

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert(mt('_pedit_rel_notfound'));

    var id = items[0].getAttribute('id');
    if(byId('relation_tr_'+id))
      return alert(mt('_pedit_rel_double'));

    prrAdd(sel.options[sel.selectedIndex].value, id, items[0].firstChild.nodeValue);
    sel.selectedIndex = 0;
    prrSerialize();
  });
  return false;
}

if(byId('prodrelations'))
  prrLoad();




/*  C H A R A C T E R   T R A I T S  (/c+/edit) */

// l10n /_spoil_-?\d+/

function ctrLoad() {
  // load current traits
  var l = byId('traits').value.split(' ');
  var v = {}; // tag id -> spoiler lookup table
  var q = []; // list of id=X parameters
  for(var i=0; i<l.length; i++) {
    if(l[i]) {
      var m = l[i].split(/-/);
      v[m[0]] = m[1];
      q[i] = 'id='+m[0];
    }
  }
  if(q.length > 0)
    ajax('/xml/traits.xml?r=100;'+q.join(';'), function (ht) {
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
      tag('b', {'class':'grayedout'}, item.getAttribute('meta')=='yes' ? mt('_js_ds_tag_meta') : '')));
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
    t.appendChild(tag('tr', {id:'traits_empty',colspan:3}, tag('td', mt('_chare_traits_empty'))));
}

function ctrAdd(item, spoil) {
  var id = item.getAttribute('id');
  var name = item.firstChild.nodeValue;
  var group = item.getAttribute('groupname');
  var sp = tag('td', {'class':'tc_spoil', onclick:ctrSpoilNext, ctr_spoil:spoil}, mt('_spoil_'+spoil));
  ddInit(sp, 'left', ctrSpoilDD);
  byId('traits_tbl').appendChild(tag('tr', {ctr_id:id, ctr_spoiler:spoil},
    tag('td', {'class':'tc_name'},
      tag('b', {'class':'grayedout'}, group?group+' / ':''),
      tag('a', {'href':'/i'+id}, name)),
    sp,
    tag('td', {'class':'tc_del'}, tag('a', {href:'#', onclick:ctrDel}, mt('_js_remove')))
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
    alert(mt('_chare_traits_present'));
  else if(item.getAttribute('meta') == 'yes')
    alert(mt('_chare_traits_nometa'));
  else
    ctrAdd(item, 0);
  return '';
}

function ctrSpoilNext() {
  if(++this.ctr_spoil > 2)
    this.ctr_spoil = 0;
  setText(this, mt('_spoil_'+this.ctr_spoil));
  ddRefresh();
  ctrSerialize();
}

function ctrSpoilDD(lnk) {
  var lst = tag('ul', null);
  for(var i=0; i<=2; i++)
    lst.appendChild(tag('li', i == lnk.ctr_spoil
      ? tag('i', mt('_spoil_'+i))
      : tag('a', {href: '#', onclick:ctrSpoilSet, ctr_td:lnk, ctr_sp:i}, mt('_spoil_'+i))
    ));
  return lst;
}

function ctrSpoilSet() {
  this.ctr_td.ctr_spoil = this.ctr_sp;
  setText(this.ctr_td, mt('_spoil_'+this.ctr_sp));
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




/*  C H A R A C T E R   < - >   V N   L I N K I N G  (/c+/edit) */

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
    t.appendChild(tag('tr', {id:'vns_empty',colspan:3}, tag('td', mt('_chare_vns_empty'))));
}

function cvnVNAdd(vn, rel) {
  var vid = vn.getAttribute('id');
  var rels = byName(vn, 'release');
  byId('vns_tbl').appendChild(tag('tr', {id:'cvn_v'+vid, cvn_vid:vid, cvn_rels:rels},
    tag('td', {'class':'tc_vn',colspan:4}, 'v'+vid+':',
      tag('a', {href:'/v'+vid}, vn.getAttribute('title')),
      tag('i', '(', tag('a', {href:'#', onclick:cvnRelNew}, mt('_chare_vns_addrel')), ')')
    )
  ));
  if(rel)
    cvnRelAdd(vid, 0, 'primary', 0);
  cvnEmpty();
}

function cvnRelAdd(vid, rid, role, spoil) {
  var rels = byId('cvn_v'+vid).cvn_rels;
  var rsel = tag('select', {onchange:cvnRelChange}, tag('option', {value:0}, mt('_chare_vns_other')));
  for(var i=0; i<rels.length; i++) {
    var id = rels[i].getAttribute('id');
    rsel.appendChild(tag('option', {value: id, selected:id==rid},
      '['+rels[i].getAttribute('lang')+'] '+rels[i].firstChild.nodeValue+' (r'+id+')'));
  }

  var lsel = tag('select', {onchange:cvnSerialize});
  for(var i=0; i<char_roles.length; i++) // l10n /^_charrole_/
    lsel.appendChild(tag('option', {value: char_roles[i], selected:char_roles[i]==role}, mt('_charrole_'+char_roles[i])));

  // l10n /_spoil_\d+/
  var ssel = tag('select', {onchange:cvnSerialize});
  for(var i=0; i<3; i++)
    ssel.appendChild(tag('option', {value:i, selected:i==spoil}, mt('_spoil_'+i)));

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
    tag('td', {'class':'tc_del'}, tag('a', {href:'#', onclick:cvnRelDel}, mt('_js_remove')))
  ), last);
}

function cvnRelChange() {
  // look for duplicates and disallow the change
  var val = this.options[this.selectedIndex].value;
  var tr = this;
  while(tr.nodeName.toLowerCase() != 'tr')
    tr = tr.parentNode;
  if(byId('cvn_v'+tr.cvn_vid+'r'+val)) {
    alert(mt('_chare_vns_relexists'));
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
      alert(mt('_chare_vns_allrel'));
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
      return alert(mt('_chare_vns_exists'));
    cvnVNAdd(items[0], 1);
    cvnSerialize();
  }, 1);
  return mt('_js_loading');
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





/*  F I L T E R   S Y S T E M  */


/* Filter box definition:
 * [ <title>,
 *   [ <category_name>,
 *     [ <fieldcode>, <fieldname>, <fieldcontents>, <fieldreadfunc>, <fieldwritefunc> ], ..
 *   ], ..
 * ]
 * Where:
 *  <title>           human-readable title of the filter box
 *  <category_name>   human-readable name of the category. ignored if there's only one category
 *  <fieldcode>       code of this field, refers to the <field> in the filter format. Empty string for just a <tr>
 *  <fieldname>       human-readanle name of the field. Empty to not display a label. Space for always-enabled items (without checkbox)
 *  <fieldcontents>   tag() object, or an array of tag() objects
 *  <fieldreadfunc>   function reference. argument: <fieldcontents>; must return data to be used in the filter format
 *  <fieldwritefunc>  function reference, argument: <fieldcontents>, data from filter format; must update the contents with the passed data
 *
 * Filter string format:
 *  <field>-<value1>~<value2>.<field2>-<value>.<field3>-<value1>~<value2>
 * Where:
 *  <field> = [a-z0-9]+
 *  <value> = [a-zA-Z0-9_]+ and any UTF-8 characters not in the ASCII range
 * Escaping of the <value>:
 *  "_<two-number-code>"
 * Where <two-number-code> is the decimal index to the following array:
 *  _ <space> ! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ]  ^ ` { | } ~
 * For boolean fields, the <value> is either 0 or 1.
 */

var fil_cats; // [ <object with field->tr mapping>, <category-link1>, .. ]
var fil_escape = "_ !\"#$%&'()*+,-./:;<=>?@[\\]^`{|}~".split('');
function filLoad() {
  var l = byId('filselect').href.match(/#r$/) ? filReleases()
        : byId('filselect').href.match(/#c$/) ? filChars()
        : filVN();
  fil_cats = [ new Object ];

  var p = tag('p', {'class':'browseopts'});
  var c = tag('div', null);
  var idx = 0;
  for(var i=1; i<l.length; i++) {
    if(!l[i])
      continue;
    idx++;

    // category link
    var a = tag('a', { href: '#', onclick: filSelectCat, fil_num: idx, fil_onshow:[] }, l[i][0]);
    p.appendChild(a);
    p.appendChild(tag(' '));

    // category contents
    var t = tag('table', {'class':'formtable', fil_num: idx}, null);
    setClass(t, 'hidden', true);
    a.fil_t = t;
    for(var j=1; j<l[i].length; j++) {
      var fd = l[i][j];
      var lab = typeof fd[1] == 'object' ? fd[1][0] : fd[1];
      var f = tag('tr', {'class':'newfield', fil_code: fd[0], fil_contents: fd[2], fil_readfunc: fd[3], fil_writefunc: fd[4]},
        fd[0] ? tag('td', {'class':'check'}, tag('input', {type:'checkbox', id:'fil_check_'+fd[0], 'class':fd[1]==' '?'hidden':'', name:'fil_check_'+fd[0], onclick: filSelectField })) : tag('td', null),
        fd[1] ? tag('td', {'class':'label'},
          tag('label', {'for':'fil_check_'+fd[0]}, lab),
          typeof fd[1] == 'object' ? tag('b', fd[1][1]) : null
        ) : null,
        tag('td', {'class':'cont' }, fd[2]));
      if(fd[0])
        fil_cats[0][fd[0]] = f;
      if(fd[5])
        a.fil_onshow.push([ fd[5], f.fil_contents ]);
      t.appendChild(f);
    }
    c.appendChild(t);

    fil_cats[idx] = a;
  }

  addBody(tag('div', { id: 'fil_div', 'class':'hidden' },
    tag('a', {href:'#', onclick:filShow, 'class':'close'}, mt('_js_close')),
    tag('h3', l[0]),
    p,
    tag('b', {'class':'ruler'}, null),
    c,
    tag('b', {'class':'ruler'}, null),
    tag('input', {type:'button', 'class':'submit', value: mt('_js_fil_apply'), onclick:function () {
      var f = byId('fil');
      while(f.nodeName.toLowerCase() != 'form')
        f = f.parentNode;
      f.submit();
    }}),
    tag('input', {type:'button', 'class':'submit', value: mt('_js_fil_reset'), onclick:function () { byId('fil').value = ''; filDeSerialize()} }),
    byId('pref_code') ? tag('input', {type:'button', 'class':'submit', value: mt('_js_fil_save'), onclick:filSaveDefault }) : null,
    tag('p', {id:'fil_savenote', 'class':'hidden'}, '')
  ));
  filSelectCat(1);
  byId('filselect').onclick = filShow;
  filDeSerialize();
}

function filSaveDefault() {
  var but = this;
  var note = byId('fil_savenote');
  setText(note, mt('_js_loading'));
  but.enabled = false;
  setClass(byId('fil_savenote'), 'hidden', false);
  var type = byId('filselect').href.match(/#r$/) ? 'release' : 'vn';
  ajax('/xml/prefs.xml?formcode='+byId('pref_code').title+';key=filter_'+type+';value='+byId('fil').value, function (hr) {
    setText(note, mt('_js_fil_savenote'));
    but.enable = true;
  });
}

function filSelectCat(n) {
  setClass(byId('fil_savenote'), 'hidden', true);
  n = this.fil_num ? this.fil_num : n;
  for(var i=1; i<fil_cats.length; i++) {
    setClass(fil_cats[i], 'optselected', i == n);
    setClass(fil_cats[i].fil_t, 'hidden', i != n);
  }
  for(var i=0; i<fil_cats[n].fil_onshow.length; i++)
    fil_cats[n].fil_onshow[i][0](fil_cats[n].fil_onshow[i][1]);
  return false
}

function filSelectField(obj) {
  var t = obj && obj.parentNode ? obj : this;
  setClass(byId('fil_savenote'), 'hidden', true);
  // update checkbox and label
  var o = t;
  while(o.nodeName.toLowerCase() != 'tr')
    o = o.parentNode;
  var c = byId('fil_check_'+o.fil_code);
  if(c != t)
    c.checked = true;
  if(hasClass(c, 'hidden'))
    c.checked = true;
  setClass(byName(o, 'label')[0], 'active', c.checked);

  // update category link
  while(o.nodeName.toLowerCase() != 'table')
    o = o.parentNode;
  var l = byName(o, 'input');
  var n=0;
  for(var i=0; i<l.length; i++)
    if(l[i].type == 'checkbox' && l[i].id.substr(0, 10) == 'fil_check_' && !hasClass(l[i], 'hidden') && l[i].checked)
      n++;
  setClass(fil_cats[o.fil_num], 'active', n>0);

  // serialize
  filSerialize();
  return true;
}

function filSerialize() {
  var num = 0;
  var values = {};
  for(var f in fil_cats[0]) {
    if(!byId('fil_check_'+f).checked)
      continue;
    if(!hasClass(byId('fil_check_'+f), 'hidden'))
      num++;
    var v = fil_cats[0][f].fil_readfunc(fil_cats[0][f].fil_contents);
    var r = [];
    for(var h=0; h<v.length; h++) {
      var vs = (''+v[h]).split('');
      r[h] = '';
      // this isn't a very fast escaping method, blame JavaScript for inflexible search/replace support
      for(var i=0; i<vs.length; i++) {
        for(var j=0; j<fil_escape.length; j++)
          if(vs[i] == fil_escape[j])
            break;
        r[h] += j == fil_escape.length ? vs[i] : '_'+(j<10?'0'+j:j);
      }
    }
    if(r.length > 0 && r[0] != '')
      values[fil_cats[0][f].fil_code] = r.join('~');
  }
  if(!values['tag_inc'] && !values['trait_inc'])
    delete values['tagspoil'];
  var l = [];
  for(var f in values)
    l.push(f+'-'+values[f]);
  byId('fil').value = l.join('.');
  setText(byName(byId('filselect'), 'i')[1], num > 0 ? ' ('+num+')' : '');
}

function filDeSerialize() {
  var d = byId('fil').value;
  var fs = d.split('.');
  var f = new Object;
  for(var i=0; i<fs.length; i++) {
    var v = fs[i].split('-');
    if(fil_cats[0][v[0]])
      f[v[0]] = v[1];
  }
  for(var fn in fil_cats[0])
    if(!f[fn])
      f[fn] = '';
  for(var fn in f) {
    var c = byId('fil_check_'+fn);
    if(!c)
      continue;
    c.checked = f[fn] == '' ? false : true;
    var v = f[fn].split('~');
    for(var i=0; i<v.length; i++)
      v[i] = v[i].replace(/_([0-9]{2})/g, function (a, e) { return fil_escape[Math.floor(e)] });
    fil_cats[0][fn].fil_writefunc(fil_cats[0][fn].fil_contents, v);
    // not very efficient: filSelectField() does a lot of things that can be
    //  batched after all fields have been updated, and in some cases the
    //  writefunc() triggers the same filSelectField() as well
    filSelectField(c);
  }
}

function filShow() {
  var div = byId('fil_div');
  var hid = !hasClass(div, 'hidden');
  setClass(div, 'hidden', hid);
  setText(byName(byId('filselect'), 'i')[0], hid ? collapsed_icon : expanded_icon);
  setClass(byId('fil_savenote'), 'hidden', true);

  var o = this;
  ddx = ddy = 0;
  do {
    ddx += o.offsetLeft;
    ddy += o.offsetTop;
  } while(o = o.offsetParent);
  ddy += this.offsetHeight+2;
  ddx += (this.offsetWidth-div.offsetWidth)/2;
  div.style.left = ddx+'px';
  div.style.top = ddy+'px';

  return false;
}

var curSlider = null;
function filFSlider(c, n, min, max, def, unit) {
  var bw = 200; var pw = 1;  // slidebar width and pointer width
  var s = tag('p', {fil_val:def, 'class':'slider'});
  var b = tag('div', {style:'width:'+(bw-2)+'px;', s:s});
  var p = tag('div', {style:'width:'+pw+'px;', s:s});
  var v = tag('span', def+' '+unit);
  s.appendChild(b);
  b.appendChild(p);
  s.appendChild(v);

  var set = function (e, v) {
    var w = bw-pw-6;
    var s,x;

    if(v) {
      s = e;
      x = v[0] == '' ? def : parseInt(v[0]);
      x = (x-min)*w/(max-min);
    } else {
      s = curSlider;
      if(!e) e = window.event;
      x = (!e) ? (def-min)*w/(max-min)
        : (e.pageX || e.clientX + document.body.scrollLeft - document.body.clientLeft)-5;
      var o = s.childNodes[0];
      while(o.offsetParent) {
        x -= o.offsetLeft;
        o = o.offsetParent;
      }
    }

    if(x<0) x = 0; if(x>w) x = w;
    s.fil_val = min + Math.floor(x*(max-min)/w);
    s.childNodes[1].innerHTML = s.fil_val+' '+unit;
    s.childNodes[0].childNodes[0].style.left = x+'px';
    return false;
  }

  b.onmousedown = p.onmousedown = function (e) {
    curSlider = this.s;
    if(!curSlider.oldmousemove) curSlider.oldmousemove = document.onmousemove;
    if(!curSlider.oldmouseup) curSlider.oldmouseup = document.onmouseup;
    document.onmouseup = function () {
      document.onmousemove = curSlider.oldmousemove;
      curSlider.oldmousemove = null;
      document.onmouseup = curSlider.oldmouseup;
      curSlider.oldmouseup = null;
      filSelectField(curSlider);
      return false;
    }
    document.onmousemove = set;
    return set(e);
  }

  return [c, n, s, function (c) { return [ c.fil_val ]; }, set ];
}

function filFSelect(c, n, lines, opts) {
  var s = tag('select', {onfocus: filSelectField, onchange: filSerialize, multiple: lines > 1, size: lines});
  for(var i=0; i<opts.length; i++) {
    if(typeof opts[i][1] != 'object')
      s.appendChild(tag('option', {name: opts[i][0]}, opts[i][1]));
    else {
      var g = tag('optgroup', {label: opts[i][0]});
      for(var j=1; j<opts[i].length; j++)
        g.appendChild(tag('option', {name: opts[i][j][0]}, opts[i][j][1]));
      s.appendChild(g);
    }
  }
  return [ c, lines > 1 ? [ n, mt('_js_fil_boolor') ] : n, s,
    function (c) {
      var l = [];
      for(var i=0; i<c.options.length; i++)
        if(c.options[i].selected)
          l.push(c.options[i].name);
      return l;
    },
    function (c, f) {
      for(var i=0; i<c.options.length; i++) {
        for(var j=0; j<f.length; j++)
          if(c.options[i].name+'' == f[j]+'') // beware of JS logic: 0 == '', but '0' != ''
            break;
        c.options[i].selected = j != f.length;
      }
    }
  ];
}

function filFOptions(c, n, opts, setfunc) {
  var p = tag('p', {'class':'opts', fil_val:opts[0][0]});
  var sel = function (e) {
    var o = typeof e == 'string' ? e : this.fil_n;
    if(setfunc)
      o = setfunc(o);
    var l = byName(p, 'a');
    for(var i=0; i<l.length; i++)
      setClass(l[i], 'tsel', l[i].fil_n+'' == o+'');
    p.fil_val = o;
    if(typeof e != 'string')
      filSelectField(p);
    return false
  };
  for(var i=0; i<opts.length; i++) {
    p.appendChild(tag('a', {href:'#', fil_n: opts[i][0], onclick:sel}, opts[i][1]));
    if(i<opts.length-1)
      p.appendChild(tag('b', '|'));
  }
  return [ c, n, p,
    function (c) { return [ c.fil_val ] },
    function (c, v) { sel(v[0]) }
  ];
}

function filFTagInput(name, label, type) {
  var src = type=='tag' ? '/xml/tags.xml' : '/xml/traits.xml';

  var visible = false;
  var remove = function() {
    ;
  };
  var addtag = function(ul, id, name, group) {
    ul.appendChild(
      tag('li', { fil_id: id },
      type=='trait' && group ? tag('b', {'class':'grayedout'}, group+' / ') : null,
      type=='tag' ? tag('a', {href:'/g'+id}, name||'g'+id) : tag('a', {href:'/i'+id}, name||'i'+id),
      ' (', tag('a', {href:'#',
        onclick:function () {
          // a -> li -> ul -> div
          var ul = this.parentNode.parentNode;
          ul.removeChild(this.parentNode);
          filSelectField(ul.parentNode);
          return false
        }
      }, mt('_js_remove')), ')'
    ));
  }
  var fetch = function(c)   {
    var v = c.fil_val;
    var ul = byName(c, 'ul')[0];
    var txt = byName(c, 'input')[0];
    if(v == null)
      return;
    if(!v[0]) {
      setText(ul, '');
      txt.disabled = false;
      txt.value = '';
      return;
    }
    if(!visible)
      setText(ul, '');
    var q = [];
    for(var i=0; i<v.length; i++) {
      q.push('id='+v[i]);
      if(!visible)
        addtag(ul, v[i]);
    }
    txt.value = mt('_js_loading');
    txt.disabled = true;
    if(visible)
      ajax(src+'?'+q.join(';'), function (hr) {
        var l = [];
        var items = hr.responseXML.getElementsByTagName('item');
        setText(ul, '');
        for(var i=0; i<items.length; i++)
          addtag(ul, items[i].getAttribute('id'), items[i].firstChild.nodeValue, items[i].getAttribute('groupname'));
        txt.value = '';
        txt.disabled = false;
        c.fil_val = null;
      }, 1);
  };
  var input = tag('input', {type:'text', 'class':'text', style:'width:300px', onfocus:filSelectField});
  var list = tag('ul', null);
  dsInit(input, src+'?q=',
    function(item, tr) {
      var g = item.getAttribute('groupname');
      tr.appendChild(tag('td',
        type=='trait' && g ? tag('b', {'class':'grayedout'}, g+' / ') : null,
        shorten(item.firstChild.nodeValue, 40),                                // l10n /_js_ds_(tag|trait)_(meta|mod)/
        item.getAttribute('meta') == 'yes' ? tag('b', {'class': 'grayedout'}, ' '+mt('_js_ds_'+type+'_meta')) : null,
        item.getAttribute('state') == 0    ? tag('b', {'class': 'grayedout'}, ' '+mt('_js_ds_'+type+'_mod')) : null
      ));
    },
    function(item, obj) {
      if(item.getAttribute('meta') == 'yes')  // l10n /_js_ds_(tag|trait)_nometa/
        alert(mt('_js_ds_'+type+'_nometa'));
      else {
        addtag(byName(obj.parentNode, 'ul')[0], item.getAttribute('id'), item.firstChild.nodeValue, item.getAttribute('groupname'));
        filSelectField(obj);
      }
      return '';
    },
    function(o) { filSelectField(o); false }
  );

  return [
    name, label, tag('div', list, input),
    function(c) {
      var v = []; var l = byName(c, 'li');
      for(var i=0; i<l.length; i++)
        v.push(l[i].fil_id);
      return v;
    },
    function(c,v) { c.fil_val = v; fetch(c) },
    function(c) { visible = true; fetch(c); }
  ];
}

function filChars() {
  var gend = genders;
  for(var i=0; i<gend.length; i++) // l10n /_gender_.+/
    gend[i] = [ gend[i], mt('_gender_'+gend[i]) ];
  var bloodt = blood_types;
  for(var i=0; i<bloodt.length; i++) // l10n /_bloodt_.+/
    bloodt[i] = [ bloodt[i], bloodt[i] == 'unknown' ? mt('_unknown') : mt('_bloodt_'+bloodt[i]) ];
  var roles = char_roles;
  for(var i=0; i<roles.length; i++) // l10n /_charrole_.+/
    roles[i] = [ roles[i], mt('_charrole_'+roles[i]) ];

  var ontraitpage = location.pathname.indexOf('/c/') < 0;

  return [
    mt('_charb_fil_title'),
    [ mt('_charb_general'),
      filFSelect('gender', mt('_charb_gender'), 4, gend),
      filFSelect('bloodt', mt('_charb_bloodt'), 5, bloodt),
      '',
      filFSlider('bust_min', mt('_charb_bust_min'), 20, 120, 40, 'cm'),
      filFSlider('bust_max', mt('_charb_bust_max'), 20, 120, 100, 'cm'),
      filFSlider('waist_min', mt('_charb_waist_min'), 20, 120, 40, 'cm'),
      filFSlider('waist_max', mt('_charb_waist_max'), 20, 120, 100, 'cm'),
      filFSlider('hip_min', mt('_charb_hip_min'), 20, 120, 40, 'cm'),
      filFSlider('hip_max', mt('_charb_hip_max'), 20, 120, 100, 'cm'),
      '',
      filFSlider('height_min', mt('_charb_height_min'), 0, 300, 60, 'cm'),
      filFSlider('height_max', mt('_charb_height_max'), 0, 300, 240, 'cm'),
      filFSlider('weight_min', mt('_charb_weight_min'), 0, 400, 80, 'kg'),
      filFSlider('weight_max', mt('_charb_weight_max'), 0, 400, 320, 'kg'),
    ],
    ontraitpage ? [ mt('_charb_traits'),
      [ '', ' ', tag(mt('_charb_traitnothere')) ],
    ] : [ mt('_charb_traits'),
      [ '', ' ', tag(mt('_js_fil_booland')) ],
      filFTagInput('trait_inc', mt('_charb_traitinc'), 'trait'),
      filFTagInput('trait_exc', mt('_charb_traitexc'), 'trait'),
      filFOptions('tagspoil', ' ', [[0, mt('_charb_spoil0')],[1, mt('_charb_spoil1')],[2, mt('_charb_spoil2')]],
        function (o) { var s = getCookie('tagspoil'); if(o+'' == '') return s == null ? 0 : s; setCookie('tagspoil', o); return o})
    ],
    [ mt('_charb_roles'), filFSelect('role', mt('_charb_roles'), 4, roles) ]
  ];
}

function filReleases() {
  var types = release_types;
  for(var i=0; i<types.length; i++) // l10n /_rtype_.+/
    types[i] = [ types[i], mt('_rtype_'+types[i]) ];
  var ages = age_ratings;
  for(var i=0; i<ages.length; i++)
    ages[i] = [ ages[i], ages[i] == -1 ? mt('_unknown') : ages[i] == 0 ? mt('_minage_all') : mt('_minage_age', ages[i]) ];
  var lang = languages;
  for(var i=0; i<lang.length; i++) // l10n /_lang_.+/
    lang[i] = [ lang[i], mt('_lang_'+lang[i]) ];
  var plat = platforms;
  for(var i=0; i<plat.length; i++) // l10n /_plat_.+/
    plat[i] = [ plat[i], mt('_plat_'+plat[i]) ];
  plat.splice(0, 0, [ 'unk', mt('_unknown') ]);
  var med = media;
  for(var i=0; i<med.length; i++) // l10n /_med_.+/
    med[i] = [ med[i], mt('_med_'+med[i]) ];
  med.splice(0, 0, [ 'unk', mt('_unknown') ]);
  var voi = voiced;
  for(var i=0; i<voi.length; i++) // l10n /_voiced_.+/
    voi[i] = [ voi[i], voi[i] == 0 ? mt('_unknown') : mt('_voiced_'+voi[i]) ];
  var ani = animated;
  for(var i=0; i<ani.length; i++) // l10n /_animated_.+/
    ani[i] = [ ani[i], ani[i] == 0 ? mt('_unknown') : mt('_animated_'+ani[i]) ];
  return [
    mt('_rbrowse_fil_title'),
    [ mt('_rbrowse_general'),
      filFOptions('type',     mt('_rbrowse_type'),    types),
      filFOptions('patch',    mt('_rbrowse_patch'),   [ [1, mt('_rbrowse_patch_yes')],    [0, mt('_rbrowse_patch_no')] ]),
      filFOptions('freeware', mt('_rbrowse_freeware'),[ [1, mt('_rbrowse_freeware_yes')], [0, mt('_rbrowse_freeware_no')] ]),
      filFOptions('doujin',   mt('_rbrowse_doujin'),  [ [1, mt('_rbrowse_doujin_yes')],   [0, mt('_rbrowse_doujin_no')] ]),
      [ 'date_after',  mt('_rbrowse_dateafter'),  dateLoad(null, filSelectField), function (c) { return [c.date_val] }, dateSet ],
      [ 'date_before', mt('_rbrowse_datebefore'), dateLoad(null, filSelectField), function (c) { return [c.date_val] }, dateSet ],
      filFOptions('released', mt('_rbrowse_released'),[ [1, mt('_rbrowse_released_yes')], [0, mt('_rbrowse_released_no')] ])
    ],
    [ mt('_rbrowse_minage'),     filFSelect('minage',     mt('_rbrowse_minage'),     15, ages) ],
    [ mt('_rbrowse_language'),   filFSelect('lang',       mt('_rbrowse_language'),   20, lang) ],
    [ mt('_rbrowse_olang'),      filFSelect('olang',      mt('_rbrowse_olang'),      20, lang) ],
    [ mt('_rbrowse_resolution'), filFSelect('resolution', mt('_rbrowse_resolution'), 15, resolutions) ],
    [ mt('_rbrowse_platform'),   filFSelect('plat',       mt('_rbrowse_platform'),   20, plat) ],
    [ mt('_rbrowse_medium'),     filFSelect('med',        mt('_rbrowse_medium'),     10, med)  ],
    [ mt('_rbrowse_voiced'),     filFSelect('voiced',     mt('_rbrowse_voiced'),      5, voi)  ],
    [ mt('_rbrowse_animation'),
      filFSelect('ani_story', mt('_rbrowse_ani_story'), 5, ani),
      filFSelect('ani_ero',   mt('_rbrowse_ani_ero'),   5, ani)
    ]
  ];
}

function filVN() {
  var lang = languages;
  for(var i=0; i<lang.length; i++) // l10n /_lang_.+/
    lang[i] = [ lang[i], mt('_lang_'+lang[i]) ];
  var plat = platforms;
  for(var i=0; i<plat.length; i++) // l10n /_plat_.+/
    plat[i] = [ plat[i], mt('_plat_'+plat[i]) ];
  var len = vn_lengths;
  for(var i=0; i<len.length; i++) // l10n /_vnlength_.+/
    len[i] = [ len[i], len[i] == 0 ? mt('_unknown') : mt('_vnlength_'+len[i]) ];

  var ontagpage = location.pathname.indexOf('/v/') < 0;

  return [
    mt('_vnbrowse_fil_title'),
    [ mt('_vnbrowse_general'),
      filFSelect( 'length', mt('_vnbrowse_length'), 6, len),
      filFOptions('hasani', mt('_vnbrowse_anime'), [[1, mt('_vnbrowse_anime_yes')],[0, mt('_vnbrowse_anime_no')]])
    ],
    ontagpage ? [ mt('_vnbrowse_tags'),
      [ '', ' ', tag(mt('_vnbrowse_tagnothere')) ],
    ] : [ mt('_vnbrowse_tags'),
      [ '',       ' ',                     tag(mt('_js_fil_booland')) ],
      [ '',       ' ', byId('pref_code') ? tag(mt('_vnbrowse_tagactive')) : null ],
      filFTagInput('tag_inc', mt('_vnbrowse_taginc'), 'tag'),
      filFTagInput('tag_exc', mt('_vnbrowse_tagexc'), 'tag'),
      filFOptions('tagspoil', ' ', [[0, mt('_vnbrowse_spoil0')],[1, mt('_vnbrowse_spoil1')],[2, mt('_vnbrowse_spoil2')]],
        function (o) { var s = getCookie('tagspoil'); if(o+'' == '') return s == null ? 0 : s; setCookie('tagspoil', o); return o})
    ],
    [ mt('_vnbrowse_language'), filFSelect('lang', mt('_vnbrowse_language'), 20, lang) ],
    [ mt('_vnbrowse_olang'),    filFSelect('olang',mt('_vnbrowse_olang'),    20, lang) ],
    [ mt('_vnbrowse_platform'), filFSelect('plat', mt('_vnbrowse_platform'), 20, plat) ],
    !byId('pref_code') ? null : [
      mt('_vnbrowse_ul'),
      filFOptions('ul_notblack', mt('_vnbrowse_ul_notblack'), [[1, mt('_vnbrowse_ul_notblackmsg')]]),
      filFOptions('ul_onwish',   mt('_vnbrowse_ul_onwish'), [[0, mt('_vnbrowse_ul_onwishno')],[1, mt('_vnbrowse_ul_onwishyes')]]),
      filFOptions('ul_voted',    mt('_vnbrowse_ul_voted'),  [[0, mt('_vnbrowse_ul_votedno')], [1, mt('_vnbrowse_ul_votedyes') ]]),
      filFOptions('ul_onlist',   mt('_vnbrowse_ul_onlist'), [[0, mt('_vnbrowse_ul_onlistno')],[1, mt('_vnbrowse_ul_onlistyes')]])
    ],
  ];
}

if(byId('filselect'))
  filLoad();




/*  M I S C   S T U F F  */

// search box
{
  var i = byId('sq');
  i.onfocus = function () {
    if(this.value == mt('_menu_emptysearch')) {
      this.value = '';
      this.style.fontStyle = 'normal'
    }
  };
  i.onblur = function () {
    if(this.value.length < 1) {
      this.value = mt('_menu_emptysearch');
      this.style.fontStyle = 'italic'
    }
  };
}

// VN Voting (/v+)
if(byId('votesel')) {
  byId('votesel').onchange = function() {
    var s = this.options[this.selectedIndex].value;
    if(s == -2)
      s = prompt(mt('_vnpage_uopt_othervote'), '');
    if(!s || s == -3)
      return;
    if(s != -1 && (!s.match(/^([1-9]|10)([\.,][0-9])?$/) || s > 10 || s < 1)) {
      alert(mt('_vnpage_uopt_invvote'));
      this.selectedIndex = 0;
      return;
    }
    s = s.replace(',', '.');
    if(s == 1 && !confirm(mt('_vnpage_uopt_1vote')))
      return;
    if(s == 10 && !confirm(mt('_vnpage_uopt_10vote')))
      return;
    if(s > 0 || s == -1)
      location.href = location.href.replace(/#.*/, '').replace(/\/chars/, '').replace(/(v\d+)\.\d+/, '$1')+'/vote?formcode='+this.name+';v='+s;
  };
}

// Advanced search (/v/*)
if(byId('advselect')) {
  byId('advselect').onclick = function() {
    var box = byId('advoptions');
    var hidden = !hasClass(box, 'hidden');
    setClass(box, 'hidden', hidden);
    setText(byName(this, 'i')[0], hidden ? collapsed_icon : expanded_icon);
    return false;
  };
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
    var l = byClass(byId('screenshots'), 'a', 'scrlnk');
    for(var i=0; i<l.length; i++) {
      if(hasClass(l[i], 'nsfw')) {
        var hidden = !hasClass(l[i], 'hidden');
        setClass(l[i], 'hidden', hidden);
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
      location.href = location.href.replace(/#.*/, '').replace(/\/chars/, '').replace(/\.[0-9]+/, '')
        +'/wish?formcode='+this.name+';s='+this.options[this.selectedIndex].value;
  };
}

// Release & VN list dropdown box (/r+ and /v+)
if(byId('listsel')) {
  byId('listsel').onchange = function() {
    if(this.selectedIndex != 0)
      location.href = location.href.replace(/#.*/, '').replace(/\/chars/, '').replace(/\.[0-9]+/, '')
        +'/list?formcode='+this.name+';e='+this.options[this.selectedIndex].value;
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
// (let's just keep this untranslatable, nobody cares anyway ^^)
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

// Batch edit dropdown box (/u+/wish and /u+/votes)
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

// collapse/expand row groups (/u+/list)
if(byId('expandall')) {
  var table = byId('expandall');
  while(table.nodeName.toLowerCase() != 'table')
    table = table.parentNode;
  var heads = byClass(table, 'td', 'collapse_but');
  var allhid = false;

  var alltoggle = function() {
    allhid = !allhid;
    var l = byClass(table, 'tr', 'collapse');
    for(var i=0; i<l.length; i++) {
      setClass(l[i], 'hidden', allhid);
      var sel = byName(l[i], 'input')[0];
      if(sel) setClass(sel, 'hidden', allhid);
    }
    setText(byId('expandall'), allhid ? collapsed_icon : expanded_icon);
    for(var i=0; i<heads.length; i++)
      setText(heads[i], allhid ? collapsed_icon : expanded_icon);
    return false;
  }
  byId('expandall').onclick = alltoggle;
  alltoggle();

  var singletoggle = function() {
    var l = byClass(table, 'tr', 'collapse_'+this.id);
    if(l.length < 1)
      return;
    var hid = !hasClass(l[0], 'hidden');
    for(var i=0; i<l.length; i++) {
      setClass(l[i], 'hidden', hid);
      var sel = byName(l[i], 'input')[0];
      if(sel) setClass(sel, 'hidden', hid);
    }
    setText(this, hid ? collapsed_icon : expanded_icon);
  };
  for(var i=0; i<heads.length; i++)
    heads[i].onclick = singletoggle;
}


// charspoil handling
if(byId('charspoil_sel')) {
  var k = byClass('charspoil');
  var h = byName(byId('charspoil_sel'), 'a');
  var setall = function(spoil) {
    for(var i=0; i<k.length; i++)
      setClass(k[i], 'hidden',
        hasClass(k[i], 'charspoil_0') ? false :
        hasClass(k[i], 'charspoil_-1') ? spoil > 1 :
        hasClass(k[i], 'charspoil_1') ? spoil < 1 : spoil < 2);
    for(var i=0; i<h.length; i++)
      setClass(h[i], 'sel', spoil == i);
  };
  for(var i=0; i<h.length; i++) {
    h[i].num = i;
    h[i].onclick = function() {
      setall(this.num);
      setCookie('tagspoil', this.num);
      return false;
    };
  };
  setall(getCookie('tagspoil'));
}


// mouse-over price information / disclaimer
if(byId('buynow')) {
  var l = byClass(byId('buynow'), 'acronym', 'pricenote');
  for(var i=0; i<l.length; i++) {
    l[i].buynow_last = l[i].title;
    l[i].title = null;
    ddInit(l[i], 'bottom', function(acr) {
      return tag('p', {onmouseover:ddHide, style:'padding: 3px'},
        acr.buynow_last, tag('br', null),
        '* The displayed price only serves as an indication and',
        tag('br', null), 'usually excludes shipping. Actual price may differ.'
      );
    });
  }
}


// set note input box (/u+/list)
if(byId('not') && byId('vns'))
  byId('vns').onchange = function () {
    if(this.options[this.selectedIndex].value == 999)
      byId('not').value = prompt(mt('_rlist_setnote_prompt'), '');
    return true;
  };


// expand/collapse release listing (/p+)
if(byId('expandprodrel')) {
  var lnk = byId('expandprodrel');
  setexpand = function() {
    var exp = !(getCookie('prodrelexpand') == 1);
    setText(lnk, exp ? mt('_js_collapse') : mt('_js_expand'));
    setClass(byId('prodrel'), 'collapse', !exp);
  };
  setexpand();
  lnk.onclick = function () {
    setCookie('prodrelexpand', getCookie('prodrelexpand') == 1 ? 0 : 1);
    setexpand();
    return false;
  };
}

// Language selector
if(byId('lang_select')) {
  var d = byId('lang_select');
  var curlang = byName(d, 'acronym')[0].className.substr(11, 2);
  ddInit(d, 'bottom', function(lnk) {
    var lst = tag('ul', null);
    for(var i=0; i<L10N_LANG.length; i++) {
      var ln = L10N_LANG[i];
      var icon = tag('acronym', {'class':'icons lang '+ln[0]}, ' ');
      lst.appendChild(tag('li', {'class':'lang_selector'}, curlang == ln[0]
        ? tag('i', icon, mt('_lang_'+ln[0]))
        : tag('a', {href:'/setlang?lang='+ln[0]}, icon, ln[1])
      ));
    }
    return lst;
  });
  d.onclick = function() {return false};
}

// "check all" checkbox
{
  var f = function() {
    var l = byName('input');
    for(var i=0; i<l.length; i++)
      if(l[i].type == this.type && l[i].name == this.name && !hasClass(l[i], 'hidden'))
        l[i].checked = this.checked;
  };
  var l = byClass('input', 'checkall');
  for(var i=0; i<l.length; i++)
    if(l[i].type == 'checkbox')
      l[i].onclick = f;
}

// search tabs
if(byId('searchtabs')) {
  var f = function() {
    var str = byId('q').value;
    if(str.length > 1) {
      this.href = this.href.split('?')[0];
      if(this.href.indexOf('/g') >= 0 || this.href.indexOf('/i') >= 0)
        this.href += '/list';
      this.href += '?q=' + encodeURIComponent(str);
    }
    return true;
  };
  var l = byName(byId('searchtabs'), 'a');
  for(var i=0; i<l.length; i++)
    l[i].onclick = f;
}

// spam protection on all forms
setTimeout(function() {
  for(i=1; i<document.forms.length; i++)
    document.forms[i].action = document.forms[i].action.replace(/\/nospam\?/,'');
}, 500);



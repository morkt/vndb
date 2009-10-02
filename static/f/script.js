
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
      ret[ret.length-1] = l[i];
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
function addClass(obj, c) {
  if(!hasClass(obj, c))
    obj.className = (obj.className ? obj.className+' ' : '') + c;
}
function removeClass(obj, c) {
  var l = listClass(obj);
  var n = [];
  for(var i=0; i<l.length; i++)
    if(l[i] != c)
      n[n.length] = l[i];
  obj.className = n.join(' ');
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
      if(ol[i].rel.substr(0,3) == 'iv:' && ol[i].rel.indexOf(':'+opt[2]) > 4 && ol[i].className.indexOf('hidden') < 0 && ol[i].id != 'ivprev' && ol[i].id != 'ivnext')
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
  setContent(x('ivimg'), tag('img', {src:u, onclick:ivClose,
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






/*  V N L I S T   D R O P D O W N  */

var rstat = [ 'Unknown', 'Pending', 'Obtained', 'On loan', 'Deleted' ];
var vstat = [ 'Unknown', 'Playing', 'Finished', 'Stalled', 'Dropped' ];
function vlDropDown(e) {
  e = e || window.event;
  var tg = e.target || e.srcElement;
  while(tg && (tg.nodeType == 3 || tg.nodeName.toLowerCase() != 'a'))
    tg = tg.parentNode;

  var o = x('vldd');
  if(!o && (!tg || tg.id.substr(0,6) != 'rlsel_'))
    return;

  if(o) {
    var mouseX = e.pageX || (e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft);
    var mouseY = e.pageY || (e.clientY + document.body.scrollTop  + document.documentElement.scrollTop);
    if((mouseX < ddx-5 || mouseX > ddx+o.offsetWidth+100 || mouseY < ddy-5 || mouseY > ddy+o.offsetHeight+5)
        || (tg && tg.id.substr(0,6) == 'rlsel_' && tg.id != 'rlsel_'+o.relId)) {
      document.body.removeChild(o);
      o = null;
    }
  }
  if(!o && tg) {
    o = tg;
    ddx = ddy = 0;
    do {
      ddx += o.offsetLeft;
      ddy += o.offsetTop;
    } while(o = o.offsetParent);
    ddx -= 185;

    var cu = tg.id.substr(6);
    var st = tg.innerHTML.split(' / ');
    if(st[0].indexOf('loading') >= 0)
      return;
    var r = '<ul><li><b>Release status</b></li>';
    for(var i=0;i<rstat.length;i++)
      r += st[0] && st[0].indexOf(rstat[i]) >= 0 ? '<li><i>'+rstat[i]+'</i></li>' : '<li><a href="#" onclick="return vlMod('+cu+',\'r'+i+'\')">'+rstat[i]+'</a></li>';
    r += '</ul><ul><li><b>Play status</b></li>';
    for(var i=0;i<vstat.length;i++)
      r += st[1] && st[1].indexOf(vstat[i]) >= 0 ? '<li><i>'+vstat[i]+'</i></li>' : '<li><a href="#" onclick="return vlMod('+cu+',\'v'+i+'\')">'+vstat[i]+'</a></li>';
    r += '</ul>';
    if(tg.innerHTML != '--')
      r += '<ul class="full"><li><a href="#" onclick="return vlMod('+cu+',\'del\')">Remove from VN list</a></li></ul>';

    o = document.createElement('div');
    o.id = 'vldd';
    o.relId = tg.id.substr(6);
    o.style.left = ddx+'px';
    o.style.top = ddy+'px';
    o.innerHTML = r;
    document.body.appendChild(o);
  }
}

function vlMod(rid, act) {
  document.body.removeChild(x('vldd'));
  x('rlsel_'+rid).innerHTML = '<b class="patch">loading...</b>';
  ajax('/xml/rlist.xml?id='+rid+';e='+act, function(hr) {
    x('rlsel_'+rid).innerHTML = hr.responseXML.getElementsByTagName('rlist')[0].firstChild.nodeValue;
  });
  return false;
}






/*  J A V A S C R I P T   T A B S  */

function jtInit() {
  var sel = '';
  var first = '';
  var l = x('jt_select').getElementsByTagName('a');
  for(var i=0;i<l.length;i++)
    if(l[i].id.substr(0,7) == 'jt_sel_') {
      l[i].onclick = jtSel;
      if(!first)
        first = l[i].id;
      if(location.hash && l[i].id == 'jt_sel_'+location.hash.substr(1))
        sel = l[i].id;
    }
  if(!first)
    return;
  if(!sel)
    sel = first;
  jtSel(sel, 1);
}

function jtSel(which, nolink) {
  which = typeof(which) == 'string' ? which : which && which.id ? which.id : this.id;
  which = which.substr(7);

  var l = x('jt_select').getElementsByTagName('a');
  for(var i=0;i<l.length;i++)
    if(l[i].id.substr(0,7) == 'jt_sel_') {
      var name = l[i].id.substr(7);
      if(name != 'all')
        x('jt_box_'+name).style.display = name == which || which == 'all' ? 'block' : 'none';
      var o = x('jt_sel_'+name).parentNode;
      if(o.className.indexOf('tabselected') >= 0) {
        if(name != which)
          o.className = o.className.replace(/tabselected/, '');
      } else
        if(name == which)
          o.className += ' tabselected';
    }

  if(!nolink)
    location.href = '#'+which;
  return false;
}




/* Tag VN spoilers */
/* lvl = null to not change lvl, lim = null to not change limit */
function tvsSet(lvl, lim) {
  var l = x('tagops').getElementsByTagName('a');
  for(var i=0;i<l.length;i++) {
    if(i < 3) {
      if(lvl == null) { /* determine level */
        if(l[i].className.indexOf('tsel') >= 0)
         lvl = i;
      } else { /* set level */
        if(i == lvl && l[i].className.indexOf('tsel') < 0)
          l[i].className += ' tsel';
        else if(i != lvl && l[i].className.indexOf('tsel') >= 0)
          l[i].className = l[i].className.replace(/tsel/, '');
      }
    } else {
      if(lim == null) { /* determine limit */
        if(l[i].className.indexOf('tsel') >= 0)
          lim = i == 3;
      } else { /* set limit */
        if((i == 3) == lim && l[i].className.indexOf('tsel') < 0)
          l[i].className += ' tsel';
        else if((i == 3) != lim && l[i].className.indexOf('tsel') >= 0)
          l[i].className = l[i].className.replace(/tsel/, '');
      }
    }
  }

  l = x('vntags').getElementsByTagName('span');
  lim = lim ? 15 : 999;
  var s=0;
  for(i=0;i<l.length;i++) {
    if((lvl < l[i].className.substr(6, 1) || s>=lim) && l[i].className.indexOf('hidden') < 0)
      l[i].className += ' hidden';
    if(lvl >= l[i].className.substr(6, 1) && ++s<=lim && l[i].className.indexOf('hidden') >= 0)
      l[i].className = l[i].className.replace(/hidden/, '');
  }
  return false;
}




/* date input */
var months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
function dtLoad(obj) {
  var r = Math.floor(obj.value) || 0;
  var v = [ Math.floor(r/10000), Math.floor(r/100)%100, r%100 ];
  var i;
  r = '<select onchange="dtSerialize(this)" style="width: 70px"><option value="0">-year-</option>';
  for(i=1980; i<=(new Date()).getFullYear()+5; i++)
    r += '<option value="'+i+'"'+(i == v[0] ? ' selected="selected"':'')+'>'+i+'</option>';
  r += '<option value="9999"'+(v[0] == 9999 ? ' selected="selected"':'')+'>TBA</option>';
  r += '</select><select onchange="dtSerialize(this)" style="width: 100px"><option value="99">-month-</option>';
  for(i=1; i<=12; i++)
    r += '<option value="'+i+'"'+(i == v[1] ? ' selected="selected"':'')+'>'+months[i-1]+'</option>';
  r += '</select><select onchange="dtSerialize(this)" style="width: 70px"><option value="99">-day-</option>';
  for(i=1; i<=31; i++)
    r += '<option value="'+i+'"'+(i == v[2] ? ' selected="selected"':'')+'>'+i+'</option>';
  r += '</select>';
  v = document.createElement('div');
  v.obj = obj;
  v.innerHTML = r;
  obj.parentNode.insertBefore(v, obj);
}
function dtSerialize(obj) {
  obj = obj.parentNode;
  var l = obj.getElementsByTagName('select');
  var v = [ l[0].options[l[0].selectedIndex].value*1, l[1].options[l[1].selectedIndex].value*1, l[2].options[l[2].selectedIndex].value*1 ];
  obj = obj.obj;
  if(v[0] == 0) obj.value = 0;
  else if(v[0] == 9999) obj.value = 99999999;
  else obj.value = v[0]*10000 + v[1]*100 + (v[1]==99?99:v[2]);
}



  // search box
  var i = x('sq');
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


  // VN Voting
  i = x('votesel');
  if(i)
    i.onchange = function() {
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

  // VN Wishlist editing
  i = x('wishsel');
  if(i)
    i.onchange = function() {
      if(this.selectedIndex != 0)
        location.href = location.href.replace(/\.[0-9]+/, '')+'/wish?s='+this.options[this.selectedIndex].value;
    };
  // Batch Wishlist editing
  i = x('batchedit');
  if(i)
    i.onchange = function() {
      var frm = this;
      while(frm.nodeName.toLowerCase() != 'form')
        frm = frm.parentNode;
      if(this.selectedIndex != 0)
        frm.submit();
    };


  // Release list editing
  i = x('listsel');
  if(i)
    i.onchange = function() {
      if(this.selectedIndex != 0)
        location.href = location.href.replace(/\.[0-9]+/, '')+'/list?e='+this.options[this.selectedIndex].value;
    };

  // User VN list
  // (might want to make this a bit more generic, as it's now also used for the user tag list)
  i = x('relhidall');
  if(i) {
    var l = document.getElementsByTagName('tr');
    for(var i=0;i<l.length;i++)
      if(l[i].className.indexOf('relhid') >= 0)
        l[i].style.display = 'none';
    var l = document.getElementsByTagName('td');
    for(var i=0;i<l.length;i++)
      if(l[i].className.indexOf('relhid_but') >= 0)
        l[i].onclick = function() {
          var l = document.getElementsByTagName('tr');
          for(var i=0;i<l.length;i++)
            if(l[i].className.substr(7) == this.id) {
              l[i].style.display = l[i].style.display == 'none' ? '' : 'none';
              this.getElementsByTagName('i')[0].innerHTML = l[i].style.display == 'none' ? '&#9656;' : '&#9662;';
            }
        };
    var allhid = 1;
    x('relhidall').onclick = function() {
      allhid = !allhid;
      var l = document.getElementsByTagName('tr');
      for(var i=0;i<l.length;i++)
        if(l[i].className.indexOf('relhid') >= 0) {
          l[i].style.display = allhid ? 'none' : '';
          x(l[i].className.substr(7)).getElementsByTagName('i')[0].innerHTML = allhid ? '&#9656;' : '&#9662;';
        }
      this.getElementsByTagName('i')[0].innerHTML = allhid ? '&#9656;' : '&#9662;';
    };
  }

  // Advanced search
  if(x('advselect'))
    x('advselect').onload = function() {
      var e = x('advoptions');
      e.className = e.className.indexOf('hidden')>=0 ? '' : 'hidden';
      this.getElementsByTagName('i')[0].innerHTML = e.className.indexOf('hidden')>=0 ? '&#9656;' : '&#9662;';
      return false;
    };

  // auto-complete tag search
  if(x('advselect') && x('ti')) {
    var fields=['ti','te'];
    for(var field=0;field<fields.length;field++)
      dsInit(x(fields[field]), '/xml/tags.xml?q=',
        function(item, tr) {
          var td = document.createElement('td');
          td.innerHTML = shorten(item.firstChild.nodeValue, 40);
          if(item.getAttribute('meta') == 'yes')
            td.innerHTML += ' <b class="grayedout">meta</b>';
          else if(item.getAttribute('state') == 0)
            td.innerHTML += ' <b class="grayedout">awaiting moderation</b>';
          tr.appendChild(td);
        },
        function(item, obj) {
          var tags = obj.value.split(/ *, */);
          tags[tags.length-1] = item.firstChild.nodeValue;
          return tags.join(', ');
        },
        function() { false; },
        function(val) { return (val.split(/, */))[val.split(/, */).length-1]; }
      );
  }

  // update spoiler cookie on VN search radio button
  if(x('sp_0')) {
    x('sp_0').onload = function(){setCookie('tagspoil',0)};
    x('sp_1').onload = function(){setCookie('tagspoil',1)};
    x('sp_2').onload = function(){setCookie('tagspoil',2)};
    if((i = getCookie('tagspoil')) == null)
      i = 1;
    x('sp_'+i).checked = true;
  }

  // show/hide NSFW VN image
  if(x('nsfw_show'))
    x('nsfw_show').getElementsByTagName('a')[0].onclick = function() {
      x('nsfw_show').style.display = 'none';
      x('nsfw_hid').style.display = 'block';
      x('nsfw_hid').onclick = function() {
        x('nsfw_show').style.display = 'block';
        x('nsfw_hid').style.display = 'none';
      };
      return false
    };

  // NSFW toggle for screenshots
  if(x('nsfwhide'))
    x('nsfwhide').onload = function() {
      var s=0;
      var l = x('screenshots').getElementsByTagName('div');
      for(var i=0;i<l.length;i++) {
        if(l[i].className.indexOf('nsfw') >= 0) {
          if(l[i].className.indexOf('hidden') >= 0) {
            s++;
            l[i].className = 'nsfw';
            l[i].getElementsByTagName('a')[0].className = '';
          } else {
            l[i].className += ' hidden';
            l[i].getElementsByTagName('a')[0].className = 'hidden';
          }
        } else
          s++;
      }
      x('nsfwshown').innerHTML = s;
      return false;
    };

  // vnlist dropdown
  var l = document.getElementsByTagName('a');
  for(var i=0;i<l.length;i++)
    if(l[i].id.substr(0,6) == 'rlsel_') {
      document.onmousemove = vlDropDown;
      break;
    }

  // VN tag spoiler options
  if(x('tagops')) {
    l = x('tagops').getElementsByTagName('a');
    for(i=0;i<l.length;i++)
      l[i].onclick = function() {
        var l = x('tagops').getElementsByTagName('a');
        var sel = 0;
        for(var i=0;i<l.length;i++)
          if(l[i] == this) {
            if(i < 3) {
              tvsSet(i, null);
              setCookie('tagspoil', i);
            } else
              tvsSet(null, i==3?true:false);
          }
        return false;
      };
    tvsSet(getCookie('tagspoil'), true);
  }

  // Javascript tabs
  if(x('jt_select'))
    jtInit();

  // spoiler tags
  l = document.getElementsByTagName('b');
  for(i=0;i<l.length;i++)
    if(l[i].className == 'spoiler') {
      l[i].onmouseover = function() { this.className = 'spoiler_shown' };
      l[i].onmouseout = function() { this.className = 'spoiler' };
    }

  // expand/collapse edit summaries on */hist
  if(x('history_comments')) {
    setcomment = function() {
      var e = getCookie('histexpand') == 1;
      var l = x('history_comments');
      l.innerHTML = e ? 'collapse' : 'expand';
      while(l.nodeName.toLowerCase() != 'table')
        l = l.parentNode;
      l = l.getElementsByTagName('tr');
      for(var i=0;i<l.length;i++)
        //alert(l[i].className);
        if(l[i].className.indexOf('editsum') >= 0) {
          if(!e && l[i].className.indexOf('hidden') < 0)
            l[i].className += ' hidden';
          if(e && l[i].className.indexOf('hidden') >= 0)
            l[i].className = l[i].className.replace(/hidden/, '');
        }
    };
    setcomment();
    x('history_comments').onclick = function () {
      setCookie('histexpand', getCookie('histexpand') == 1 ? 0 : 1);
      setcomment();
      return false;
    };
  }

  // Are we really vndb?
  if(location.hostname != 'vndb.org') {
    var d = document.createElement('div');
    d.setAttribute('id', 'debug');
    d.innerHTML = '<h2>This is not VNDB!</h2>The real VNDB is <a href="http://vndb.org/">here</a>.';
    document.body.appendChild(d);
  }

  // date selector
  l = document.getElementsByTagName('input');
  for(i=0;i<l.length;i++)
    if(l[i].className == 'dateinput')
      dtLoad(l[i]);

  // make some fields readonly when patch flag is set
  if(x('jt_box_rel_geninfo')) {
    var func = function() {
      x('doujin').disabled = x('resolution').disabled = x('voiced').disabled = x('ani_story').disabled = x('ani_ero').disabled = x('patch').checked;
    };
    func();
    x('patch').onclick = func;
  }

  // spam protection on all forms
  if(document.forms.length >= 1)
    for(i=0; i<document.forms.length; i++)
      document.forms[i].action = document.forms[i].action.replace(/\/nospam\?/,'');


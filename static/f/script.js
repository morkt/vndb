
/*  G L O B A L   S T U F F  */

function x(y){return document.getElementById(y)}
function cl(o,f){if(x(o))x(o).onclick=f}
function DOMLoad(y){var d=0;var f=function(){if(d++)return;y()};
if(document.addEventListener)document.addEventListener("DOMCont"
+"entLoaded",f,false);document.write("<script id=_ie defer src="
+"javascript:void(0)><\/script>");document.getElementById('_ie')
.onreadystatechange=function(){if(this.readyState=="complete")f()
};if(/WebKit/i.test(navigator.userAgent))var t=setInterval(
function(){if(/loaded|complete/.test(document.readyState)){
clearInterval(t);f()}},10);window.onload=f;}

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
  url += (url.indexOf('?')>=0 ? ';' : '?')+(Math.floor(Math.random()*999)+1);
  http_request.open('GET', url, true);
  http_request.send(null);
}






/*  A D V A N C E D  S E A R C H  */

function searchInit() {
  cl('advselect', function() {
    var e = x('advoptions');
    e.className = e.className.indexOf('hidden')>=0 ? '' : 'hidden';
    this.getElementsByTagName('i')[0].innerHTML = e.className.indexOf('hidden')>=0 ? '&#9656;' : '&#9662;';
    return false;
  });

  var l = x('catselect').getElementsByTagName('li');
  for(i=0;i<l.length;i++)
    if(l[i].id.substr(0,4) == 'cat_')
      l[i].onclick = function() {
        searchParse(1, this.innerHTML);
      };

  l = x('advoptions').getElementsByTagName('input');
  for(i=0;i<l.length;i++)
    if(l[i].id.substr(0,5) == 'lang_' || l[i].id.substr(0,5) == 'plat_')
      l[i].onclick = function() { 
        searchParse(0, this.parentNode.getElementsByTagName('acronym')[0].title);
      };

  x('q').onkeyup = searchParse;
  searchParse();
}

function searchParse(add, term) {
  var q = x('q').value;
  var i;

  if(add == 0 || add === 1) {
    var qn = q;
    if(!add)
      eval('qn = qn.replace(/'+term+'/gi, "")');
    else {
      eval('qn = qn.replace(/(^|[^-])'+term+'/gi, "$1-'+term+'")');
      if(qn == q)
        eval('qn = qn.replace(/-'+term+'/gi, "")');
    }
    if(qn == q)
      q += ' '+term;
    else
      q = qn;

    q = q.replace(/^ +/, "");
    q = q.replace(/ +$/, "");
    q = q.replace(/  +/g, " ");

    x('q').value = q;
  }

  q = q.toLowerCase();
  var l = x('catselect').getElementsByTagName('li');
  for(i=0;i<l.length;i++)
    if(l[i].id.substr(0,4) == 'cat_') {
      var cat = l[i].innerHTML.toLowerCase();
      l[i].className = q.indexOf('-'+cat) >= 0 ? 'exc' : q.indexOf(cat) >= 0 ? 'inc' : '';
    }

  l = x('advoptions').getElementsByTagName('input');
  for(i=0;i<l.length;i++)
    if(l[i].id.substr(0,5) == 'lang_' || l[i].id.substr(0,5) == 'plat_')
      l[i].checked = q.indexOf(l[i].parentNode.getElementsByTagName('acronym')[0].title.toLowerCase()) >= 0 ? true : false;

  return false;
}





/*  I M A G E   V I E W E R  */

function ivInit() {
  var init = 0;
  var l = document.getElementsByTagName('a');
  for(var i=0;i<l.length;i++)
    if(l[i].rel.substr(0,3) == 'iv:') {
      init++;
      l[i].onclick = ivView;
    }
  if(init && !x('iv_view')) {
    var d = document.createElement('div');
    d.id = 'iv_view';
    d.innerHTML = '<b id="ivimg"></b><br />'
      +'<a href="#" id="ivfull">&nbsp;</a>'
      +'<a href="#" onclick="return ivClose()" id="ivclose">close</a>'
      +'<a href="#" onclick="return ivView(this)" id="ivprev">&laquo; previous</a>'
      +'<a href="#" onclick="return ivView(this)" id="ivnext">next &raquo;</a>';
    document.body.appendChild(d);
    d = document.createElement('b');
    d.id = 'ivimgload';
    d.innerHTML = 'Loading...';
    document.body.appendChild(d);
  }
}

function ivView(what) {
  what = what && what.rel ? what : this;
  var u = what.href;
  var opt = what.rel.split(':');
  d = x('iv_view');

 // fix prev/next links (if any)
  if(opt[2]) {
    var ol = document.getElementsByTagName('a');
    var l=[];
    for(i=0;i<ol.length;i++)
      if(ol[i].rel.substr(0,3) == 'iv:' && ol[i].rel.indexOf(':'+opt[2]) > 4 && ol[i].className.indexOf('hidden') < 0 && ol[i].id != 'ivprev' && ol[i].id != 'ivnext')
        l[l.length] = ol[i];
    for(i=0;i<l.length;i++)
      if(l[i].href == u) {
        x('ivnext').style.visibility = l[i+1] ? 'visible' : 'hidden';
        x('ivnext').href = l[i+1] ? l[i+1].href : '#';
        x('ivnext').rel = l[i+1] ? l[i+1].rel : '';
        x('ivprev').style.visibility = l[i-1] ? 'visible' : 'hidden';
        x('ivprev').href = l[i-1] ? l[i-1].href : '#';
        x('ivprev').rel = l[i-1] ? l[i-1].rel : '';
      }
  } else
    x('ivnext').style.visibility = x('ivprev').style.visibility = 'hidden';

 // calculate dimensions
  var w = Math.floor(opt[1].split('x')[0]);
  var h = Math.floor(opt[1].split('x')[1]);
  var ww = typeof(window.innerWidth) == 'number' ? window.innerWidth : document.documentElement.clientWidth;
  var wh = typeof(window.innerHeight) == 'number' ? window.innerHeight : document.documentElement.clientHeight;
  var st = typeof(window.pageYOffset) == 'number' ? window.pageYOffset : document.body && document.body.scrollTop ? document.body.scrollTop : document.documentElement.scrollTop;
  if(w+100 > ww || h+70 > wh) {
    x('ivfull').href = u;
    x('ivfull').innerHTML = w+'x'+h;
    x('ivfull').style.visibility = 'visible';
    if(w/h > ww/wh) { // width++
      h *= (ww-100)/w;
      w = ww-100;
    } else { // height++
      w *= (wh-70)/h;
      h = wh-70;
    }
  } else
    x('ivfull').style.visibility = 'hidden';
  var dw = w;
  var dh = h+20;
  dw = dw < 200 ? 200 : dw;

 // update document
  d.style.display = 'block';
  x('ivimg').innerHTML = '<img src="'+u+'" onclick="ivClose()" onload="document.getElementById(\'ivimgload\').style.top=\'-400px\'" style="width: '+w+'px; height: '+h+'px" />';
  d.style.width = dw+'px';
  d.style.height = dh+'px';
  d.style.left = ((ww - dw) / 2 - 10)+'px';
  d.style.top = ((wh - dh) / 2 + st - 20)+'px';
  x('ivimgload').style.left = ((ww - 100) / 2 - 10)+'px';
  x('ivimgload').style.top = ((wh - 20) / 2 + st)+'px';
  return false;
}

function ivClose() {
  x('iv_view').style.display = 'none';
  x('iv_view').style.top = '-5000px';
  x('ivimgload').style.top = '-400px';
  x('ivimg').innerHTML = '';
  return false;
}






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




/*  O N L O A D   E V E N T  */

DOMLoad(function() {

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


  // Advanced VN search
  if(x('advselect'))
    searchInit();


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
  cl('nsfwhide', function() {
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
  });

  // initialize image viewer
  ivInit();

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
        l = x('tagops').getElementsByTagName('a');
        var lvl;
        for(var i=0;i<l.length;i++) {
          if(l[i] == this)
            lvl = i;
          if(l[i] == this && l[i].className.indexOf('tsel') < 0)
            l[i].className += ' tsel';
          else if(l[i] != this && l[i].className.indexOf('tsel') >= 0)
            l[i].className = l[i].className.replace(/tsel/, '');
        }
        l = x('vntags').getElementsByTagName('span');
        for(i=0;i<l.length;i++) {
          if(lvl < l[i].className.substr(6, 1) && l[i].className.indexOf('hidden') < 0)
            l[i].className += ' hidden';
          else if(lvl >= l[i].className.substr(6, 1) && l[i].className.indexOf('hidden') >= 0)
            l[i].className = l[i].className.replace(/hidden/, '');
        }
        return false;
      };
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

  // forms.js
  if(x('relations'))
    relLoad();
  if(x('jt_box_screenshots'))
    scrLoad();
  if(x('media'))
    medLoad();
  if(x('jt_box_visual_novels'))
    vnpLoad('vn');
  if(x('jt_box_producers'))
    vnpLoad('producers');
  if(x('taglinks'))
    tglLoad();

  // spam protection on all forms
  if(document.forms.length >= 1)
    for(i=0; i<document.forms.length; i++)
      document.forms[i].action = document.forms[i].action.replace(/\/nospam\?/,'');

});

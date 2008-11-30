
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
      +'<a href="#" onclick="return ivView(this)" id="ivprev">&lt;- previous</a>'
      +'<a href="#" onclick="return ivView(this)" id="ivnext">next -&gt;</a>';
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
      x('jt_box_'+name).style.display = name == which ? 'block' : 'none';
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


  // show/hide NSFW VN image
  cl('nsfw_show', function() {
    x('nsfw_show').style.display = 'none';
    x('nsfw_hid').style.display = 'block';
    x('nsfw_hid').onclick = function() {
      x('nsfw_show').style.display = 'block';
      x('nsfw_hid').style.display = 'none';
    };
    return false
  });

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

  // Javascript tabs
  if(x('jt_select')) 
    jtInit();

  // forms.js
  if(x('categories'))
    catLoad();
  if(x('relations'))
    relLoad();
  if(x('jt_box_screenshots'))
    scrLoad();

  // spam protection on all forms
  if(document.forms.length >= 1)
    for(i=0; i<document.forms.length; i++)
      document.forms[i].action = document.forms[i].action.replace(/\/nospam\?/,'');

});

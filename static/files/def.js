

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




/*   F O R M   S U B S  */

var formsubs = [];
function formhid() {
  var i;
  var j;
  var l = document.forms[1].getElementsByTagName('a');
  for(i=0; i<l.length; i++)
    if(l[i].className.indexOf('s_') != -1) {
      formsubs[ l[i].className.substr(l[i].className.indexOf('s_')+2) ] = 0;
      l[i].onclick = function() {
        formtoggle(this.className.substr(this.className.indexOf('s_')+2));
        return false;
      };
    }

  if(x('_hid') && x('_hid').value.length > 1) {
    l = x('_hid').value.split(/,/);
    for(i in formsubs) {
      var inz=0;
      for(j=0; j<l.length; j++)
        if(l[j] == i)
          inz = 1;
      if(!inz)
        formsubs[i] = !formsubs[i];
    }
  }
}
function formtoggle(n) {
  formsubs[n] = !formsubs[n];
  var i;
  var l = document.forms[1].getElementsByTagName('a');
  for(i=0; i<l.length; i++)
    if(l[i].className.indexOf('s_'+n) != -1)
      l[i].innerHTML = (formsubs[n] ? '&#9656;' : '&#9662;') + l[i].innerHTML.substr(1);

  l = document.forms[1].getElementsByTagName('li');
  for(i=0; i<l.length; i++)
    if(l[i].className.indexOf('sf_'+n) != -1) {
      if(formsubs[n])
        l[i].className += ' formhid';
      else
        l[i].className = l[i].className.replace(/formhid/g, '');
    }

  if(x('_hid')) {
    l = [];
    for(i in formsubs)
      if(!formsubs[i])
        l[l.length] = i;
    x('_hid').value = l.toString();
  }
}




/*  D R O P D O W N   M E N U S  */

var ddx;var ddy;var dds=null;
function dropDown(e) {
  e = e || window.event;
  var tg = e.target || e.srcElement;
  if(tg.nodeType == 3)
    tg = tg.parentNode;

  if(!dds && (tg.nodeName.toLowerCase() != 'a' || !tg.rel || tg.className.indexOf('dropdown') < 0))
    return;
  if(tg.rel)
    tg.rel = tg.rel.replace(/ *nofollow */,"");
  if(!dds && !tg.rel)
    return;
  
  if(!dds) {
    var obj=tg;
    ddx = ddy = 0;
    do {
      ddx += obj.offsetLeft;
      ddy += obj.offsetTop;
    } while(obj = obj.offsetParent);
    ddy += 16;
    obj = x(tg.rel);
    obj.style.left = ddx+'px';
    obj.style.top = ddy+'px';
    dds = tg;
  }

  if(dds) {
    var mouseX = e.pageX || (e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft);
    var mouseY = e.pageY || (e.clientY + document.body.scrollTop  + document.documentElement.scrollTop);
    var obj = x(dds.rel);
    if((mouseX < ddx-5 || mouseX > ddx+obj.offsetWidth+5 || mouseY < ddy-20 || mouseY > ddy + obj.offsetHeight)
        || (mouseY < ddy && tg.nodeName.toLowerCase() == 'a' && tg != dds)) {
      obj.style.left = '-500px';
      dds = null;
    }
  }
}




/*  A D V A N C E D   S E A R C H  */

var ad_cats = {};
var ad_lang = {};
var ad_plat = {};

function adsearch() {
  x('vsearch').onsubmit = ad_dosearch;
  x('vsearch_sub').onclick = ad_dosearch;
  x('q').onkeyup = ad_update;

  x('adsearchclick').onclick = function() {
    if(x('adsearch').style.display == 'none') {
      x('adsearch').style.display = 'block';
      x('adsearchclick').innerHTML = '&#9662; advanced options';
    } else {
      x('adsearch').style.display = 'none';
      x('adsearchclick').innerHTML = '&#9656; advanced options';
    }
  };

  var l = x('cat').getElementsByTagName('li');
  for(i=0;i<l.length;i++)
    if(l[i].id.indexOf('cat_') != -1) {
      ad_cats[ l[i].id.substr(l[i].id.indexOf('cat_')+4, 3) ] = l[i].innerHTML.substring(0, l[i].innerHTML.indexOf('(')-1).toLowerCase();
      l[i].onclick = function () {
        try { document.selection.empty() } catch(e) { try { window.getSelection().collapse(this, 0) } catch(e) {} };
        ad_update(1, this.innerHTML.substring(0, this.innerHTML.indexOf('(')-1));
      };
    }
 
  l = x('lfilter').getElementsByTagName('input');
  for(i=0;i<l.length;i++) {
    ad_lang[ l[i].name.substring(5) ] = l[i].value.toLowerCase();
    l[i].onclick = function() { ad_update(0, this.value) };
  }

  l = x('pfilter').getElementsByTagName('input');
  for(i=0;i<l.length;i++) {
    ad_plat[ l[i].name.substring(5) ] = l[i].value.toLowerCase();
    l[i].onclick = function() { ad_update(0, this.value) };
  }

  ad_update();
}

function ad_update(add, term) {
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
  for (i in ad_lang)
    x('lang_'+i).checked = q.indexOf(ad_lang[i]) >= 0 || q.indexOf('l:'+i) >= 0 ? true : false;
  for (i in ad_plat)
    x('plat_'+i).checked = q.indexOf(ad_plat[i]) >= 0 || q.indexOf('p:'+i) >= 0 ? true : false;
  for (i in ad_cats)
    x('cat_'+i).className = q.indexOf('-'+ad_cats[i]) >= 0 || q.indexOf('-c:'+i) >= 0 ? 'exc' : q.indexOf(ad_cats[i]) >= 0 || q.indexOf('c:'+i) >= 0 ? 'inc' : '';
}

function ad_dosearch() {
  location.href = '?q='+x('q').value;
  return false;
}




/*  O N L O A D  */

DOMLoad(function() {
  var i;

 // search box
  i = x('searchfield');
  i.onfocus = function () {
    if(this.value == 'search') {
      this.value = '';
      this.style.color = '#000'; } };
  i.onblur = function () {
    if(this.value.length < 1) {
      this.value = 'search';
      this.style.color = '#999';} };
 
 // advanced search
  if(x('adsearch'))
    adsearch();

 // vnlist
  cl('askcomment', function() {
    this.href = this.href + ';c=' + encodeURIComponent(prompt("Enter personal note (optional)", '')||'');
    return true;
  });

 // mass-change vnlist status
  if(x('vnlistchange')) {
    x('vnlistchange').onchange = function() {
      var val = this.options[this.selectedIndex].value;
      if(val == '-3') 
        return;
      var l = document.getElementsByTagName('input');
      var y; var ch=0;
      for(y=0;y<l.length;y++)
        if(l[y].type == 'checkbox' && l[y].checked)
          ch++;
      if(!ch)
        return alert('Nothing selected...');
      if(val == '-1' && !confirm('Are you sure you want to remove the selected items from your visual novel list?'))
        return;
      if(val == '-2')
        x('comments').value = prompt('Enter personal note (leave blank to delete note)','')||'';
      document.forms[1].submit();
    }
  }

 // userdel
  cl('userdel', function() { return confirm("Completely remove this account from the site?") });

 // vote warnings
  cl('dovote_10', function() { return confirm(
     "You are about to give this visual novel a 10 out of 10. This is a rather extreme rating, "
    +"meaning this is one of the best visual novels you've ever played and it's unlikely "
    +"that any other game could ever be better than this one.\n"
    +"It is generally a bad idea to have more than three games in your vote list with this rating, choose carefully!") });
  cl('dovote_1',  function() { return confirm(
     "You are about to give this visual novel a 1 out of 10. This is a rather extreme rating, "
    +"meaning this game has absolutely nothing to offer, and that it's the worst game you have ever played.\n"
    +"Are you really sure this visual novel matches that description?") });

 // NSFW
  cl('nsfw', function () {
    this.src = this.className;
    this.id = '';
  });

 // spam protection on all forms
  if(document.forms.length > 1)
    for(i=1; i<document.forms.length; i++)
      document.forms[i].action = document.forms[i].action.replace(/\/nospam\?/,'');

 // dropdown menus
  var z = document.getElementsByTagName('a');
  for(i=0;i<z.length;i++)
    if(z[i].rel && z[i].className.indexOf('dropdown') >= 0) {
      document.onmousemove = dropDown;
      break;
    }

 // form-stuff
  if(document.forms.length > 1) {
    formhid();
   // edit summary warning
    if(x('comm'))
      document.forms[1].onsubmit = function () {
        var z = x('comm');
        if(z.value.length > 5) return true;
        var y = prompt("Edit summary field is empty,\nPlease explain your edits and cite all sources!", z.value);
        if(y == null) return false;
        z.value = y;
        return true;
      };
  }

 // init dyna
  if(window.dInit)
    dInit();

 // zebra-striped tables (client side!? yes... client side :3)
  var sub = document.getElementsByTagName('tr');
  for(i=1; i<sub.length; i+=2)
    sub[i].style.backgroundColor = '#f5f5f5';
});




// small hack because the mozilla -moz-inline-stack display hack sucks
//  (so we're counter-hacking a CSS hack using JS... right)
if(navigator.userAgent.indexOf('Gecko') >= 0 && navigator.userAgent.indexOf('like Gecko') < 0 && navigator.userAgent.indexOf('fox/3') < 0)
  document.write('<style type="text/css">.icons.lang { width: 15px; height: 13px; }</style>');



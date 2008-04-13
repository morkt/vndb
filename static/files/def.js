

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
  var tg = e.target || e.srcElement; // get target element
  if(tg.nodeType == 3)
    tg = tg.parentNode;
  if(!dds && (tg.nodeName.toLowerCase() != 'a' || !tg.rel || tg.className.indexOf('dropdown') < 0))
    return;
  var mouseX = e.pageX || (e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft);
  var mouseY = e.pageY || (e.clientY + document.body.scrollTop  + document.documentElement.scrollTop);
  if(!dds) {
    var obj = x(tg.rel);
    ddx = mouseX-20;
    ddy = mouseY+10;
    obj.style.left = ddx+'px';
    obj.style.top = ddy+'px';
    dds = tg;
  }
  if(dds) {
    var obj = x(dds.rel);
    if((mouseX < ddx || mouseX > ddx+obj.offsetWidth || mouseY < ddy-20 || mouseY > ddy + obj.offsetHeight)
        || (mouseY < ddy && tg.nodeName.toLowerCase() == 'a' && tg != dds)) {
      obj.style.left = '-500px';
      dds = null;
    }
    return;
  }
  return true;
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

 // browse categories
  if(x('catsearch')) {
    x('catsearch').onclick = function () {
      var u = { i:'',e:'',l:'' };
      var l = x('cat').getElementsByTagName('li');
      var y;var j;
      for(y=0;y<l.length;y++)
        if((j = l[y].className.indexOf('cat_')) != -1) {
          var k = l[y].className.substr(j+4, 3);
          if(l[y].className.indexOf(' inc') != -1)
            u.i += (u.i?',':'')+k;
          if(l[y].className.indexOf(' exc') != -1)
            u.e += (u.e?',':'')+k;
        }
      l = x('lfilter').getElementsByTagName('input');
      for(y=0;y<l.length;y++)
        if(l[y].checked)
          u.l+=(u.l!=''?',':'')+l[y].name.substr(5);
      var url = '/v/cat';
      for (y in u)
        if(u[y])
          url+=(url.indexOf('?')<0?'?':';')+y+'='+u[y];
      location.href=url;
      return false;
    };
    var l = x('cat').getElementsByTagName('li');
    for(i=0;i<l.length;i++)
      if(l[i].className.indexOf('cat_') != -1)
        l[i].onclick = function () {
          try { document.selection.empty() } catch(e) { try { window.getSelection().collapse(this, 0) } catch(e) {} };
          var sel = this.className.substr(this.className.indexOf('cat_'), 7);
          this.className = this.className.indexOf(' inc') != -1 ? (sel+' exc') : this.className.indexOf(' exc') != -1 ? sel : (sel + ' inc');
        };
  }

 // vnlist
  cl('askcomment', function() {
    this.href = this.href + '&amp;c=' + encodeURIComponent(prompt("Enter personal note (optional)", '')||'');
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

 // autocheck
  cl('checkall', function () {
    var l = document.getElementsByTagName('input');
    var y;
    for(y=0;y<l.length;y++)
      if(l[y].type == 'checkbox' && l[y].name == this.name)
        l[y].checked = this.checked;
  });

 // a few confirm popups
  cl('idel', function () {
    return confirm('Are you sure you want to delete this item?\n\nAll previous edits will be deleted, this action can not be reverted!') });
//  cl('vhide', function () {
//    return confirm('!WARNING!\nHiding a visual novel also DELETES the following information:\n - VN Relations of ALL revisions\n - VN lists\n - Votes\nThis is NOT recoverable!');  });
  cl('massdel', function () {
    return confirm('Are you sure you want to mass-delete all the selected changes?\n\nThis action can not be reverted!') });

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
  if(document.forms.length > 1)
    formhid();

 // init dyna
//  if(x('vn_select') || x('md_select') || x('pd_select') || x('rl_select'))
  if(window.dInit)
    dInit();

 // zebra-striped tables (client side!? yes... client side :3)
  var sub = document.getElementsByTagName('tr');
  for(i=1; i<sub.length; i+=2)
    sub[i].style.backgroundColor = '#f5f5f5';
});

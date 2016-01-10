function ulist_redirect(type, path, formcode, args) {
  var r = new RegExp('/('+type+'[0-9]+).*$');
  location.href = location.href.replace(r, '/$1')+path
    +'?formcode='+formcode
    +';ref='+encodeURIComponent(location.pathname+location.search)
    +';'+args;
}


// VN Voting (/v+)
if(byId('votesel'))
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
      ulist_redirect('v', '/vote', this.name, 'v='+s);
  };


// VN Wishlist dropdown box (/v+)
if(byId('wishsel'))
  byId('wishsel').onchange = function() {
    if(this.selectedIndex != 0)
      ulist_redirect('v', '/wish', this.name, ';s='+this.options[this.selectedIndex].value);
  };


// Release & VN list dropdown box (/r+ and /v+)
if(byId('listsel'))
  byId('listsel').onchange = function() {
    if(this.selectedIndex != 0)
      ulist_redirect('[rv]', '/list', this.name, 'e='+this.options[this.selectedIndex].value);
  };


// NSFW VN image toggle (/v+)
(function() {
  var msg = byId('nsfw_show');
  if(msg) {
    var img = byId('nsfw_hid');
    byName(msg, 'a')[0].onclick = function() {
      setClass(msg, 'hidden', true);
      setClass(img, 'hidden', false);
      return false;
    };
    img.onclick = function() {
      setClass(msg, 'hidden', false);
      setClass(img, 'hidden', true);
    };
  }
})();


// NSFW toggle for screenshots (/v+)
if(byId('nsfwhide'))
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


// Notification list onclick
(function(){
  var d = byId('notifies');
  if(!d)
    return;
  var l = byClass(d, 'td', 'clickable');
  for(var i=0; i<l.length; i++)
    l[i].onclick = function() {
      var baseurl = location.href.replace(/\/u([0-9]+)\/notifies.*$/, '/u$1/notify/');
      location.href = baseurl + this.id.replace(/notify_/, '');
    };
})();


// BBCode spoiler tags
(function(){
  var l = byClass('b', 'spoiler');
  for(var i=0; i<l.length; i++) {
    l[i].onmouseover = function() { setClass(this, 'spoiler', false); setClass(this, 'spoiler_shown', true)  };
    l[i].onmouseout = function()  { setClass(this, 'spoiler', true);  setClass(this, 'spoiler_shown', false) };
  }
})();


// vndb.org domain check
if(location.hostname != 'vndb.org') {
  addBody(tag('div', {id:'debug'},
    tag('h2', 'This is not VNDB!'),
    'The real VNDB is ',
    tag('a', {href:'http://vndb.org/'}, 'here'),
    '.'
  ));
}


// 'more' / 'less' summarization of some boxes on VN pages
(function(){
  function set(o, h) {
    var a = tag('a', {href:'#', summarizeOn:false}, '');
    var toggle = function() {
      a.summarizeOn = !a.summarizeOn;
      o.style.maxHeight = a.summarizeOn ? h+'px' : null;
      o.style.overflowY = a.summarizeOn ? 'hidden' : null;
      setText(a, a.summarizeOn ? '⇓ more ⇓' : '⇑ less ⇑');
      return false;
    };
    a.onclick = toggle;
    var t = tag('div', {'class':'summarize_more'}, a);
    l[i].parentNode.insertBefore(t, l[i].nextSibling);
    toggle();
  }

  var l = byClass(document, 'summarize');

  for(var i=0; i<l.length; i++) {
    var h = Math.floor(l[i].getAttribute('data-summarize-height') || 150);
    if(l[i].offsetHeight > h+30)
      set(l[i], h);
  }
})();


// make some fields readonly when patch flag is set (/r+/edit)
(function(){
  function sync() {
    byId('doujin').disabled =
      byId('resolution').disabled =
      byId('voiced').disabled =
      byId('ani_story').disabled =
      byId('ani_ero').disabled =
      byId('patch').checked;
  };
  if(byId('jt_box_rel_geninfo')) {
    sync();
    byId('patch').onclick = sync;
  }
})();


// Batch edit dropdown box (/u+/wish and /u+/votes)
if(byId('batchedit'))
  byId('batchedit').onchange = function() {
    if(this.selectedIndex == 0)
      return true;
    var frm = this;
    while(frm.nodeName.toLowerCase() != 'form')
      frm = frm.parentNode;
    frm.submit();
  };


// collapse/expand row groups (/u+/list)
(function(){
  var table = byId('expandall');
  if(!table)
    return;
  while(table.nodeName.toLowerCase() != 'table')
    table = table.parentNode;
  var heads = byClass(table, 'td', 'collapse_but');
  var allhid = false;

  function sethid(l, h, hid) {
    var i;
    for(i=0; i<l.length; i++) {
      setClass(l[i], 'hidden', hid);
      // Set the hidden class on the input checkbox, if it exists. This
      // prevents the "select all" functionality from selecting it if the row
      // is not visible.
      var sel = byName(l[i], 'input')[0];
      if(sel)
        setClass(sel, 'hidden', hid);
    }
    for(i=0; i<h.length; i++)
      setText(h[i], allhid ? collapsed_icon : expanded_icon);
  }

  function alltoggle() {
    allhid = !allhid;
    setText(byId('expandall'), allhid ? collapsed_icon : expanded_icon);
    sethid(byClass(table, 'tr', 'collapse'), heads, allhid);
    return false;
  }

  function singletoggle() {
    var l = byClass(table, 'tr', 'collapse_'+this.id);
    sethid(l, [this], !hasClass(l[0], 'hidden'));
  }

  byId('expandall').onclick = alltoggle;
  for(var i=0; i<heads.length; i++)
    heads[i].onclick = singletoggle;
  alltoggle();
})();


// mouse-over price information / disclaimer
(function(){
  if(byId('buynow')) {
    var l = byClass(byId('buynow'), 'abbr', 'pricenote');
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
})();


// set note input box (/u+/list)
if(byId('not') && byId('vns'))
  byId('vns').onchange = function () {
    if(this.options[this.selectedIndex].value == 999)
      byId('not').value = prompt(mt('_rlist_setnote_prompt'), '');
    return true;
  };


// expand/collapse release listing (/p+)
(function(){
  var lnk = byId('expandprodrel');
  if(!lnk)
    return;
  function setexpand() {
    var exp = !(getCookie('prodrelexpand') == 1);
    setText(lnk, exp ? mt('_js_collapse') : mt('_js_expand'));
    setClass(byId('prodrel'), 'collapse', !exp);
  };
  lnk.onclick = function () {
    setCookie('prodrelexpand', getCookie('prodrelexpand') == 1 ? 0 : 1);
    setexpand();
    return false;
  };
  setexpand();
})();


// Language selector
(function(){
  var d = byId('lang_select');
  var flag = byName(d, 'abbr')[0];
  ddInit(d, 'bottom', function(lnk) {
    var lst = tag('ul', null);
    for(var i=0; i<VARS.l10n_lang.length; i++) {
      var ln = VARS.l10n_lang[i];
      var icon = tag('abbr', {'class':'icons lang '+ln[0]}, ' ');
      lst.appendChild(tag('li', {'class':'lang_selector'}, hasClass(flag, ln[0])
        ? tag('i', icon, ln[1])
        : tag('a', {href:'/setlang?lang='+ln[0]+';ref='+encodeURIComponent(location.pathname+location.search)}, icon, ln[1])
      ));
    }
    return lst;
  });
  d.onclick = function() {return false};
})();


// "check all" checkbox
(function(){
  function set() {
    var l = byName('input');
    for(var i=0; i<l.length; i++)
      if(l[i].type == this.type && l[i].name == this.name && !hasClass(l[i], 'hidden'))
        l[i].checked = this.checked;
  }
  var l = byClass('input', 'checkall');
  for(var i=0; i<l.length; i++)
    if(l[i].type == 'checkbox')
      l[i].onclick = set;
})();


// search tabs
(function(){
  function click() {
    var str = byId('q').value;
    if(str.length > 1) {
      this.href = this.href.split('?')[0];
      if(this.href.indexOf('/g') >= 0 || this.href.indexOf('/i') >= 0)
        this.href += '/list';
      this.href += '?q=' + encodeURIComponent(str);
    }
    return true;
  };
  if(byId('searchtabs')) {
    var l = byName(byId('searchtabs'), 'a');
    for(var i=0; i<l.length; i++)
      l[i].onclick = click;
  }
})();


// spam protection on all forms
setTimeout(function() {
  for(var i=1; i<document.forms.length; i++)
    document.forms[i].action = document.forms[i].action.replace(/\/nospam\?/,'');
}, 500);

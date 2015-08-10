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
      location.href = location.href.replace(/#.*/, '').replace(/\/(chars|staff)/, '').replace(/(v\d+)\.\d+/, '$1')+'/vote?formcode='+this.name+';v='+s;
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
      location.href = location.href.replace(/#.*/, '').replace(/\/(chars|staff)/, '').replace(/\.[0-9]+/, '')
        +'/wish?formcode='+this.name+';s='+this.options[this.selectedIndex].value;
  };
}

// Release & VN list dropdown box (/r+ and /v+)
if(byId('listsel')) {
  byId('listsel').onchange = function() {
    if(this.selectedIndex != 0)
      location.href = location.href.replace(/#.*/, '').replace(/\/(chars|staff)/, '').replace(/\.[0-9]+/, '')
        +'/list?formcode='+this.name+';e='+this.options[this.selectedIndex].value+';ref='+encodeURIComponent(location.pathname+location.search);
  };
}

// Notification list onclick
if(byId('notifies')) {
  var l = byClass(byId('notifies'), 'td', 'clickable');
  for(var i=0; i<l.length; i++)
    l[i].onclick = function() {
      var baseurl = location.href.replace(/\/u([0-9]+)\/notifies.*$/, '/u$1/notify/');
      location.href = baseurl + this.id.replace(/notify_/, '');
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
    for(var i=0; i<VARS.l10n_lang.length; i++) {
      var ln = VARS.l10n_lang[i];
      var icon = tag('acronym', {'class':'icons lang '+ln[0]}, ' ');
      lst.appendChild(tag('li', {'class':'lang_selector'}, curlang == ln[0]
        ? tag('i', icon, mt('_lang_'+ln[0]))
        : tag('a', {href:'/setlang?lang='+ln[0]+';ref='+encodeURIComponent(location.pathname+location.search)}, icon, ln[1])
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

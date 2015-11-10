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
        : byId('filselect').href.match(/#s$/) ? filStaff()
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

function filFOptions(c, n, opts) {
  var p = tag('p', {'class':'opts', fil_val:opts[0][0]});
  var sel = function (e) {
    var o = typeof e == 'string' ? e : this.fil_n;
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
    function(o) { filSelectField(o) }
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
  var ontraitpage = location.pathname.indexOf('/c/') < 0;

  return [
    mt('_charb_fil_title'),
    [ mt('_charb_general'),
      filFSelect('gender', mt('_charb_gender'), 4, VARS.genders),
      filFSelect('bloodt', mt('_charb_bloodt'), 5, VARS.blood_types),
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
      filFOptions('tagspoil', ' ', [[0, mt('_spoilset_0')],[1, mt('_spoilset_1')],[2, mt('_spoilset_2')]]),
    ],
    [ mt('_charb_roles'), filFSelect('role', mt('_charb_roles'), 4, VARS.char_roles) ]
  ];
}

function filReleases() {
  var plat = VARS.platforms;
  plat.splice(0, 0, [ 'unk', mt('_unknown') ]);
  var med = VARS.media;
  med.splice(0, 0, [ 'unk', mt('_unknown') ]);
  return [
    mt('_rbrowse_fil_title'),
    [ mt('_rbrowse_general'),
      filFOptions('type',     mt('_rbrowse_type'),    VARS.release_types),
      filFOptions('patch',    mt('_rbrowse_patch'),   [ [1, mt('_rbrowse_patch_yes')],    [0, mt('_rbrowse_patch_no')] ]),
      filFOptions('freeware', mt('_rbrowse_freeware'),[ [1, mt('_rbrowse_freeware_yes')], [0, mt('_rbrowse_freeware_no')] ]),
      filFOptions('doujin',   mt('_rbrowse_doujin'),  [ [1, mt('_rbrowse_doujin_yes')],   [0, mt('_rbrowse_doujin_no')] ]),
      [ 'date_after',  mt('_rbrowse_dateafter'),  dateLoad(null, filSelectField), function (c) { return [c.date_val] }, function(o,v) { o.dateSet(v) } ],
      [ 'date_before', mt('_rbrowse_datebefore'), dateLoad(null, filSelectField), function (c) { return [c.date_val] }, function(o,v) { o.dateSet(v) } ],
      filFOptions('released', mt('_rbrowse_released'),[ [1, mt('_rbrowse_released_yes')], [0, mt('_rbrowse_released_no')] ])
    ],
    [ mt('_rbrowse_minage'),     filFSelect('minage',     mt('_rbrowse_minage'),     15, VARS.age_ratings) ],
    [ mt('_rbrowse_language'),   filFSelect('lang',       mt('_rbrowse_language'),   20, VARS.languages) ],
    [ mt('_rbrowse_olang'),      filFSelect('olang',      mt('_rbrowse_olang'),      20, VARS.languages) ],
    [ mt('_rbrowse_resolution'), filFSelect('resolution', mt('_rbrowse_resolution'), 15, VARS.resolutions) ],
    [ mt('_rbrowse_platform'),   filFSelect('plat',       mt('_rbrowse_platform'),   20, plat) ],
    [ mt('_rbrowse_medium'),     filFSelect('med',        mt('_rbrowse_medium'),     10, med)  ],
    [ mt('_rbrowse_voiced'),     filFSelect('voiced',     mt('_rbrowse_voiced'),      5, VARS.voiced)  ],
    [ mt('_rbrowse_animation'),
      filFSelect('ani_story', mt('_rbrowse_ani_story'), 5, VARS.animated),
      filFSelect('ani_ero',   mt('_rbrowse_ani_ero'),   5, VARS.animated)
    ]
  ];
}

function filVN() {
  var ontagpage = location.pathname.indexOf('/v/') < 0;

  return [
    mt('_vnbrowse_fil_title'),
    [ mt('_vnbrowse_general'),
      filFSelect( 'length', mt('_vnbrowse_length'), 6, VARS.vn_lengths),
      filFOptions('hasani', mt('_vnbrowse_anime'), [[1, mt('_vnbrowse_anime_yes')],[0, mt('_vnbrowse_anime_no')]])
    ],
    ontagpage ? [ mt('_vnbrowse_tags'),
      [ '', ' ', tag(mt('_vnbrowse_tagnothere')) ],
    ] : [ mt('_vnbrowse_tags'),
      [ '',       ' ',                     tag(mt('_js_fil_booland')) ],
      [ '',       ' ', byId('pref_code') ? tag(mt('_vnbrowse_tagactive')) : null ],
      filFTagInput('tag_inc', mt('_vnbrowse_taginc'), 'tag'),
      filFTagInput('tag_exc', mt('_vnbrowse_tagexc'), 'tag'),
      filFOptions('tagspoil', ' ', [[0, mt('_spoilset_0')],[1, mt('_spoilset_1')],[2, mt('_spoilset_2')]])
    ],
    [ mt('_vnbrowse_language'), filFSelect('lang', mt('_vnbrowse_language'), 20, VARS.languages) ],
    [ mt('_vnbrowse_olang'),    filFSelect('olang',mt('_vnbrowse_olang'),    20, VARS.languages) ],
    [ mt('_vnbrowse_platform'), filFSelect('plat', mt('_vnbrowse_platform'), 20, VARS.platforms) ],
    !byId('pref_code') ? null : [
      mt('_vnbrowse_ul'),
      filFOptions('ul_notblack', mt('_vnbrowse_ul_notblack'), [[1, mt('_vnbrowse_ul_notblackmsg')]]),
      filFOptions('ul_onwish',   mt('_vnbrowse_ul_onwish'), [[0, mt('_vnbrowse_ul_onwishno')],[1, mt('_vnbrowse_ul_onwishyes')]]),
      filFOptions('ul_voted',    mt('_vnbrowse_ul_voted'),  [[0, mt('_vnbrowse_ul_votedno')], [1, mt('_vnbrowse_ul_votedyes') ]]),
      filFOptions('ul_onlist',   mt('_vnbrowse_ul_onlist'), [[0, mt('_vnbrowse_ul_onlistno')],[1, mt('_vnbrowse_ul_onlistyes')]])
    ],
  ];
}

function filStaff() {
  var gend = [
    ['unknown', mt('_gender_unknown')],
    ['m', mt('_gender_m')],
    ['f', mt('_gender_f')],
  ];

  // Insert seiyuu into the list of roles, before the "staff" role.
  var roles = VARS.staff_roles;
  for(var i=0; i<roles.length; i++)
    if(roles[i][0] == 'staff') {
      roles.splice(i, 0, ['seiyuu', mt('_credit_seiyuu')]);
      break;
    }

  return [
    mt('_sbrowse_fil_title'),
    [ mt('_sbrowse_general'),
      filFOptions('truename', mt('_sbrowse_names'), [[1, mt('_sbrowse_names_primary')],[0, mt('_sbrowse_names_all')]]),
      filFSelect('role', mt('_sbrowse_roles'), roles.length, roles),
      '',
      filFSelect('gender', mt('_sbrowse_gender'), gend.length, gend),
    ],
    [ mt('_sbrowse_language'),   filFSelect('lang',       mt('_sbrowse_language'),   20, VARS.languages) ],
  ];
}

if(byId('filselect'))
  filLoad();

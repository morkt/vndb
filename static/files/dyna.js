var med = {
  cd:  'CD',
  dvd: 'DVD',
  gdr: 'GD-ROM',
  blr: 'Blu-Ray disk',
  'in':'Internet download',
  pa:  'Patch',
  otc: 'Other (console)'
};
var vrel = [
  'Sequel',
  'Prequel',
  'Same setting',
  'Alternative setting',
  'Alternative version',
  'Same characters',
  'Side story',
  'Parent story',
  'Summary',
  'Full story',
  'Other'
];

var md;var pd;var rl;var vn;var ct;

function dInit() {
  md = x('md_select');
  if(md) {
    md.onclick = mdChangeSel;
    mdLoad();
    md.selectedIndex = 0;
    mdChangeSel();
  }
  
  pd = x('pd_select');
  if(pd) {
    pd.onclick = pdChangeSel;
    pdLoad();
    pd.selectedIndex = 0;
    pdChangeSel();
  }

  rl = x('rl_select');
  if(rl) {
    rl.onclick = rlChangeSel;
    rlLoad();
    rl.selectedIndex = 0;
    rlChangeSel();
  }

  vn = x('vn_select');
  if(vn) {
    vn.onclick = vnChangeSel;
    vnLoad();
    vn.selectedIndex = 0;
    vnChangeSel();
  }

  ct = x('categories');
  if(ct)
    catLoad();
}

function qq(v) {
  return v.replace(/&/g,"&amp;").replace(/</,"&lt;").replace(/>/,"&gt;").replace(/'/g,/*'*/ "\\'").replace(/"/g,/*"*/'&quot;');
} 

// small AJAX wapper
var hr = false;
function ajax(url, func) {
  if(hr)
    hr.abort();
  hr = (window.ActiveXObject) ? new ActiveXObject('Microsoft.XMLHTTP') : new XMLHttpRequest();
  if(hr == null) {
    alert("Your browse does not support the functionality this website requires.");
    return;
  }
  hr.onreadystatechange = func;
  hr.open('GET', url, true);
  hr.send(null);
}




   /************************\
   *        M E D I A       *
   \************************/


function mdChangeSel() {
  var sel = md.options[md.selectedIndex || 0];
  var o = x('md_conts');
  var i;
  if(sel.value == '0_new') {
    var l = ''; var q = '<option value="0">Qty</option>';
    for(i in med)
      l += '<option value="'+i+'">'+med[i]+'</option>';
    for(i=1;i<10;i++)
      q += '<option value="'+i+'">'+i+'</option>';
    o.innerHTML = '<select id="md_Q" name="md_Q" style="width: 50px;">'+q+'</select>'
      + '<select id="md_S" name="md_S" style="width: 150px;">'+l+'</select>'
      + '<br style="clear: both" />'
      + '<button type="button" onclick="mdAddRem()">add/remove</button>'
      + '<br />Qty is only required for CD & DVD';
  } else {
    o.innerHTML = 'Selected "' + sel.text + '"<br />'
      + '<button type="button" onclick="mdAddRem(\'' + sel.value + '\')">remove</button>';
  }
}

function mdAddRem(id) {
  var i;
  var d = 0;
  var o = id ? null : x('md_S').options[x('md_S').selectedIndex];
  var qty = id ? null : x('md_Q').options[x('md_Q').selectedIndex].value;
  var v = id ? id : (o.value != 'cd' && o.value != 'dvd' && o.value != 'gdr' && o.value != 'blr' ? o.value : (o.value + '_' + qty));
  for(i=0;i<md.options.length;i++)
    if(md.options[i].value == v) {
      md.options[i] = null;
      d = 1;
    }
  if(!d && !id) {
    if(v.indexOf('_') >= 0 && qty == 0) {
      alert('Please specify the quantity');
      return;
    }
    md.options[md.options.length] = new Option(mdString(qty, o.value), v);
  }
  else if(id) {
    md.options[0].selected = true;
    mdChangeSel();
  }
  mdSerialize();
}

function mdSerialize() {
  var dest = x('media');
  var str = '';
  var i;
  for(i=0;i<md.options.length;i++)
    md.options[i].value != '0_new' && (str += (str.length>0 ? ',' : '') + md.options[i].value);
  dest.value = str;
}

function mdLoad() {
  var me = x('media').value.split(',');
  var i, j;
  for(i=0;i<me.length;i++) {
    var m = me[i].split('_');
    if(med[m[0]])
      md.options[md.options.length] = new Option(mdString(m[1], m[0]), me[i]);
  }
}

function mdString(qty, medium) {
  if(medium != 'cd' && medium != 'dvd' && medium != 'gdr' && medium != 'blr')
    return med[medium];
  else
    return qty + ' ' + med[medium] + (qty > 1 ? 's' : '');
}






   /************************\
   *    P R O D U C E R S   *
   \************************/


function pdChangeSel() {
  var sel = pd.options[pd.selectedIndex || 0];
  var o = x('pd_conts');
  var i;
  if(sel.value == '0_new') {
    o.innerHTML = '<input type="text" name="pd_S" id="pd_S" onkeyup="pdDoSearch(0)" onkeydown="return pdEnter(event)" style="width: 150px;" />'
      + '<button type="button" onclick="pdDoSearch(1)" style="width: 55px;">Search!</button><br style="clear: both" />'
      + '<span id="pd_R" style="display: block; width: 220px; height: 70px; overflow: auto"></span>'
      + '<a href="/p/add" target="_blank">Add new producer</a>';
    pdDoSearch('');
  } else {
    o.innerHTML = 'Selected "' + sel.text + '"<br />'
      + '<button type="button" onclick="pdAddRem(\'' + sel.value + '\')">remove</button>';
  }
}

function pdEnter(ev) {
  var c = document.layers ? ev.which : document.all ? event.keyCode : ev.keyCode;
  if(c == 13) {
    pdDoSearch(0);
    return false;
  }
  return true;
}

function pdDoSearch(f) {
  var v = x('pd_S').value;
  var d = x('pd_R');
  if(v.length < 1)
    d.innerHTML = 'Hint: type pX if you know the producer id.';
  else {
    if(f)
      d.innerHTML = '...searching...';
    ajax('/xml/producers.xml?q='+escape(v)+'&r='+(Math.floor(Math.random()*999)+1), function () {
      if(!hr || hr.readyState != 4 || !hr.responseText)
        return;
      if(hr.status != 200)
        return alert('Whoops, error! :(');
      var items = hr.responseXML.getElementsByTagName('item');
      if(!items || items.length < 1) {
        d.innerHTML = 'No results';
        return false;
      }
      var res = '';
      var i,j;
      for(i=0; i<items.length; i++) {
        var id = items[i].getElementsByTagName('id')[0].firstChild.nodeValue;
        var name = items[i].getElementsByTagName('name')[0].firstChild.nodeValue;
        var cid = id + ',' + name;
        var s = '';
        for(j=0; j<pd.options.length; j++)
          if(pd.options[j].value == cid)
            s = ' checked="checked"';
        res += '<input type="checkbox" id="pd_I'+id+'"'+s+' onclick="pdAddRem(\''+qq(cid)+'\', \''+qq(name)+'\')" />'
          + '<label style="width: auto" for="pd_I'+id+'">'+name+'</label><br style="clear: left" />';
      }
      d.innerHTML = res;
    });
  } 
}

function pdAddRem(id, name) {
  var i;
  var d = 0;
  for(i=0;i<pd.options.length;i++)
    if(pd.options[i].value == id) {
      pd.options[i] = null;
      d = 1;
    }
  if(!d && name)
    pd.options[pd.options.length] = new Option(name, id);
  else if(!name) {
    pd.options[0].selected = true;
    pdChangeSel();
  }
  pdSerialize();
}

//  id,name|||id,name
function pdSerialize() {
  var dest = x('producers');
  var str = '';
  var i;
  for(i=0;i<pd.options.length;i++)
    pd.options[i].value != '0_new' && (str += (str.length>0 ? '|||' : '') + pd.options[i].value);
  dest.value = str;
}

function pdLoad() {
  var pds = x('producers').value.split('|||');
  if(!pds[0])
    return;
  var i;
  for(i=0;i<pds.length;i++)
    pd.options[pd.options.length] = new Option(pds[i].split(',',2)[1], pds[i]);
}








   /************************\
   *    R E L A T I O N S   *
   \************************/


var rlsel = ''; var rlname = '';
function rlChangeSel() {
  var sel = rl.options[rl.selectedIndex || 0];
  var o = x('rl_conts');
  var i;
  rlsel = '';
  var ops='';
  for(i=0;i<vrel.length;i++)
    ops += '<option value="'+i+'">'+vrel[i]+'</option>';
  if(sel.value == '0_new') {
    o.innerHTML = '<input type="text" name="rl_S" id="rl_S" onkeyup="rlDoSearch(0)" onkeydown="return rlEnter(event)" style="width: 150px;" />'
      + '<button type="button" onclick="rlDoSearch(1)" style="width: 60px;">Search!</button><br style="clear: both" />'
      + '<span id="rl_R" style="display: block; width: 250px; height: 70px; overflow: auto"></span>'
      + '<select id="rl_L" name="rl_L" onchange="rlAddRem(0)"><option value="-1">...is a [..] of this visual novel</option>'+ops+'</select>';
    rlDoSearch('');
  } else {
    o.innerHTML = sel.value.split(',', 3)[2] + '<br />'
      + '<select id="rl_L" name="rl_L" onchange="rlAddRem(\''+qq(sel.value)+'\')">'
      + '<option value="-1"> - change - </option>'+ops+'<option value="-2"> - remove relation - </option></select>';
  }
}

function rlEnter(ev) {
  var c = document.layers ? ev.which : document.all ? event.keyCode : ev.keyCode;
  if(c == 13) {
    rlDoSearch(0);
    return false;
  }
  return true;
}

function rlDoSearch(f) {
  var v = x('rl_S').value;
  var d = x('rl_R');
  if(v.length < 1)
    d.innerHTML = 'Search for a visual novel to add a relation.<br /><br />'
      + 'Hint: type vX if you know the VN id.';
  else {
    if(f)
      d.innerHTML = '...searching...';
    ajax('/xml/vn.xml?q='+escape(v)+'&r='+(Math.floor(Math.random()*999)+1), function () {
      if(!hr || hr.readyState != 4 || !hr.responseText)
        return;
      if(hr.status != 200)
        return alert('Whoops, error! :(');
      rlsel = '';
      var items = hr.responseXML.getElementsByTagName('item');
      if(!items || items.length < 1) {
        d.innerHTML = 'No results';
        return false;
      }
      var res = '';
      var i,j;
      for(i=0; i<items.length; i++) {
        var id = items[i].getElementsByTagName('id')[0].firstChild.nodeValue;
        var title = items[i].getElementsByTagName('title')[0].firstChild.nodeValue;
        var cid = id + ',' + title;
        res += '<input type="radio" name="rl_rad" id="pd_I'+id+'" value="rl_I'+id+'" onclick="rlAddRem(\''+qq(cid)+'\', \''+qq(title)+'\')" />'
             + '<label style="width: auto" for="rl_I'+id+'">'+title+'</label><br style="clear: left" />';
      }
      d.innerHTML = res;
    });
  } 
}

function rlAddRem(id, name) {
  var i;
  var rs = x('rl_L').selectedIndex;
  if(id && name) {
    rlsel = id;
    rlname = name;
  } else if(id) {
    if(!rs)
      return;
    if(rs == x('rl_L').options.length-1) { // remove
      for(i=0;i<rl.options.length;i++)
        if(rl.options[i].value == id)
          rl.options[i] = null;
      rl.options[0].selected = true;
    } else {
      var cur = id.split(',', 3);
      i = rl.selectedIndex;
      rs--;
      rl.options[i] = new Option(vrel[rs]+': '+cur[2], (rs)+','+cur[1]+','+cur[2]);
      rl.options[i].selected = true;
    }
    rlChangeSel();
    rlSerialize();
    return;
  } else if(!rlsel) {
    alert('No visual novel selected');
    return;
  }

  if(!id && rlsel && !rs) { // remove
    for(i=0;i<rl.options.length;i++)
      if(rl.options[i].value.indexOf(rlsel) != -1)
        rl.options[i] = null;
    rlSerialize();
    return;
  }
  if(!rs)
    return;

  // add/edit
  var mod = rl.options.length;
  rs--;
  for(i=0;i<rl.options.length;i++)
    if(rl.options[i].value.indexOf(rlsel) != -1)
      mod = i;
  rl.options[mod] = new Option(vrel[rs]+': '+rlname, rs+','+rlsel);

  rlSerialize();
}

//  rel,id,name|||rel,id,name
function rlSerialize() {
  var dest = x('relations');
  var str = '';
  var i;
  for(i=0;i<rl.options.length;i++)
    rl.options[i].value != '0_new' && (str += (str.length>0 ? '|||' : '') + rl.options[i].value);
  dest.value = str;
}

function rlLoad() {
  var rls = x('relations').value.split('|||');
  if(!rls[0])
    return;
  var i;
  for(i=0;i<rls.length;i++)
    rl.options[rl.options.length] = new Option(vrel[rls[i].split(',',3)[0]]+': '+rls[i].split(',',3)[2], rls[i]);
}








   /************************\
   *      VISUAL NOVELS     *
   \************************/


function vnChangeSel() {
  var sel = vn.options[vn.selectedIndex || 0];
  var o = x('vn_conts');
  var i;
  var ops='';
  for(i=0;i<vrel.length;i++)
    ops += '<option value="'+i+'">'+vrel[i]+'</option>';
  if(sel.value == '0_new') {
    o.innerHTML = '<input type="text" name="vn_S" id="vn_S" onkeyup="vnDoSearch(0)" onkeydown="return vnEnter(event)" style="width: 150px;" />'
      + '<button type="button" onclick="vnDoSearch(1)" style="width: 60px;">Search!</button><br style="clear: both" />'
      + '<span id="vn_R" style="display: block; width: 250px; height: 90px; overflow: auto"></span>';
    vnDoSearch('');
  } else {
    o.innerHTML = 'Selected "' + sel.text + '"<br />'
      + '<button type="button" onclick="vnAddRem(\'' + sel.value + '\')">remove</button>';
  }
}

function vnEnter(ev) {
  var c = document.layers ? ev.which : document.all ? event.keyCode : ev.keyCode;
  if(c == 13) {
    vnDoSearch(0);
    return false;
  }
  return true;
}

function vnDoSearch(f) {
  var v = x('vn_S').value;
  var d = x('vn_R');
  if(v.length < 1)
    d.innerHTML = 'Hint: type vX if you know the visual novel id.';
  else {
    if(f)
      d.innerHTML = '...searching...';
    ajax('/xml/vn.xml?q='+escape(v)+'&r='+(Math.floor(Math.random()*999)+1), function () {
      if(!hr || hr.readyState != 4 || !hr.responseText)
        return;
      if(hr.status != 200)
        return alert('Whoops, error! :(');
      var items = hr.responseXML.getElementsByTagName('item');
      if(!items || items.length < 1) {
        d.innerHTML = 'No results';
        return false;
      }
      var res = '';
      var i,j;
      for(i=0; i<items.length; i++) {
        var id = items[i].getElementsByTagName('id')[0].firstChild.nodeValue;
        var title = items[i].getElementsByTagName('title')[0].firstChild.nodeValue;
        var s = '';
        for(j=0; j<vn.options.length; j++)
          if(vn.options[j].value == id)
            s = ' checked="checked"';
        res += '<input type="checkbox" id="vn_I'+id+'"'+s+' onclick="vnAddRem(\''+qq(id)+'\', \''+qq(title)+'\')" />'
          + '<label style="width: auto" for="vn_I'+id+'">'+title+'</label><br style="clear: left" />';
      }
      d.innerHTML = res;
    });
  } 
}

function vnAddRem(id, title) {
  var i;
  var d = 0;
  for(i=0;i<vn.options.length;i++)
    if(vn.options[i].value == id) {
      vn.options[i] = null;
      d = 1;
    }
  if(!d && title)
    vn.options[vn.options.length] = new Option(title, id);
  else if(!title) {
    vn.options[0].selected = true;
    vnChangeSel();
  }
  vnSerialize();
}

//  id,title|||id,title
function vnSerialize() {
  var dest = x('vn');
  var str = '';
  var i;
  for(i=0;i<vn.options.length;i++)
    vn.options[i].value != '0_new' && (str += (str.length>0 ? '|||' : '') + vn.options[i].value + ',' + vn.options[i].text);
  dest.value = str;
}

function vnLoad() {
  var vns = x('vn').value.split('|||');
  if(!vns[0])
    return;
  var i;
  for(i=0;i<vns.length;i++)
    vn.options[vn.options.length] = new Option(vns[i].split(',',2)[1], vns[i].split(',',2)[0]);
}






   /************************\
   *   C A T E G O R I E S  *
   \************************/


function catLoad() {
  var i;var cats=[];
  var l = ct.value.split(',');
  for(i=0;i<l.length;i++)
    cats[l[i].substr(0,3)] = Math.floor(l[i].substr(3,1));

  var l=x('cat').getElementsByTagName('a');
  for(i=0;i<l.length;i++) {
    catSet(l[i].id.substr(4), cats[l[i].id.substr(4)]||0);
    l[i].onclick = function() {
      var c = this.id.substr(4);
      if(!cats[c])       cats[c] = 0;
      if(c.substr(0,1) == 'p' || c == 'gaa' || c == 'gab') {
        if(cats[c]++)
          cats[c] = 0;
      } else if(++cats[c] == 4)
        cats[c] = 0;
      catSet(c, cats[c]);

     // has to be ordered before serializing!
      var r;l=[];i=0;
      for(r in cats)
        l[i++] = r;
      l = l.sort();
      r='';
      for(i=0;i<l.length;i++)
        if(cats[l[i]] > 0)
          r+=(r?',':'')+l[i]+cats[l[i]];
      ct.value = r;
      return false;
    };
  }
}

function catSet(id, rnk) {
  var c = rnk == 0 ? '#000' :
          rnk == 1 ? '#090' :
          rnk == 2 ? '#990' : '#900';
  x('b_'+id).style.color = c;
  x('cat_'+id).style.color = c;
  x('b_'+id).innerHTML = rnk;
}



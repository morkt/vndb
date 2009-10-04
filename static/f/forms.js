function qq(v) {
  return v.replace(/&/g,"&amp;").replace(/</,"&lt;").replace(/>/,"&gt;").replace(/"/g,'&quot;');
} 




   /****************************************************\
   *   V I S U A L   N O V E L S  /  P R O D U C E R S  *
   \****************************************************/


function vnpLoad(type) {
  // load currently selected VNs
  var l = x(type).value.split('|||');
  for(var i=0;i<l.length;i++)
    if(l[i].length > 2)
      vnpAdd(type, l[i].split(',',2)[0], l[i].split(',',2)[1]);
  vnpCheckEmpty(type);

  // dropdown
  var n = x('jt_box_'+(type == 'vn' ? 'rel_vn' : 'rel_prod')).getElementsByTagName('div')[1];
  dsInit(n.getElementsByTagName('input')[0], '/xml/'+type+'.xml?q=', function(item, tr) {
    var td = document.createElement('td');
    td.innerHTML = type.substr(0,1)+item.getAttribute('id');
    td.style.textAlign = 'right';
    td.style.paddingRight = '5px';
    tr.appendChild(td);
    td = document.createElement('td');
    td.innerHTML = shorten(item.firstChild.nodeValue, 40);
    tr.appendChild(td);
  }, function(item) {
    return type.substr(0,1)+item.getAttribute('id')+':'+item.firstChild.nodeValue;
  }, function() { vnpFormAdd(type) });
  n.getElementsByTagName('a')[0].onclick = function() { vnpFormAdd(type); return false };
}

function vnpAdd(type, id, title) {
  var o = document.createElement('span');
  o.innerHTML = '<i>'+type.substr(0,1)+id+':<a href="/'+type.substr(0,1)+id+'">'+shorten(title, 40)+'</a></i>'
    +'<a href="#" onclick="return vnpDel(this, \''+type+'\')">remove</a>';
  x(type+'sel').appendChild(o);
  vnpStripe(type);
  vnpCheckEmpty(type);
}

function vnpDel(what, type) {
  what = what.nodeName ? what : this;
  while(what.nodeName.toLowerCase() != 'span')
    what = what.parentNode;
  x(type+'sel').removeChild(what);
  vnpCheckEmpty(type);
  vnpSerialize(type);
  return false;
}

function vnpCheckEmpty(type) {
  var o = x(type+'sel');
  if(o.getElementsByTagName('span').length < 1) {
    if(o.getElementsByTagName('b').length < 1)
      o.innerHTML = '<b>Nothing selected...</b>';
  } else if(o.getElementsByTagName('b').length == 1)
    o.removeChild(o.getElementsByTagName('b')[0]);
}

function vnpStripe(type) {
  var l = x(type+'sel').getElementsByTagName('span');
  for(var i=0;i<l.length;i++)
    l[i].className = i%2 ? 'odd' : '';
}

function vnpFormAdd(type) {
  var n = x('jt_box_'+(type == 'vn' ? 'rel_vn' : 'rel_prod')).getElementsByTagName('div')[1];
  var txt = n.getElementsByTagName('input')[0];
  var lnk = n.getElementsByTagName('a')[0];
  var input = txt.value;

  if(type == 'vn' && !input.match(/^v[0-9]+/)) {
    alert('Visual novel textbox must start with an ID (e.g. v17)');
    return false;
  }
  if(type == 'producers' && !input.match(/^p[0-9]+/)) {
    alert('Producer textbox must start with an ID (e.g. p5)');
    return false;
  }

  txt.disabled = true;
  txt.value = 'loading...';
  lnk.innerHTML = 'loading...';

  ajax('/xml/'+type+'.xml?q='+encodeURIComponent(input), function(hr) {
    txt.disabled = false;
    txt.value = '';
    lnk.innerHTML = 'add';

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert('Item not found!');

    vnpAdd(type, items[0].getAttribute('id'), items[0].firstChild.nodeValue);
    vnpSerialize(type);
  });
  return false;
}

function vnpSerialize(type) {
  var r = '';
  var l = x(type+'sel').getElementsByTagName('span');
  for(var i=0;i<l.length;i++)
    r += (r ? '|||' : '') + l[i].getElementsByTagName('i')[0].innerHTML.substr(1, l[i].getElementsByTagName('i')[0].innerHTML.indexOf(':')-1)
      + ',' + l[i].getElementsByTagName('a')[0].innerHTML;
  x(type).value = r;
}






   /****************************************************\
   *   V I S U A L   N O V E L   T A G   L I N K I N G  *
   \****************************************************/


function tglLoad() {
  var n = x('tagtable').getElementsByTagName('tfoot')[0].getElementsByTagName('input');
  dsInit(n[1], '/xml/tags.xml?q=', function(item, tr) {
    var td = document.createElement('td');
    td.innerHTML = shorten(item.firstChild.nodeValue, 40);
    if(item.getAttribute('meta') == 'yes')
      td.innerHTML += ' <b class="grayedout">meta</b>';
    else if(item.getAttribute('state') == 0)
      td.innerHTML += ' <b class="grayedout">awaiting moderation</b>';
    tr.appendChild(td);
  }, function(item) {
    return item.firstChild.nodeValue;
  }, tglAdd);
  n[2].onclick = tglAdd;

  tglStripe();
  var l = x('tagtable').getElementsByTagName('tbody')[0].getElementsByTagName('tr');
  for(var i=0; i<l.length;i++) {
    var o = l[i].getElementsByTagName('td');
    tglSpoiler(o[2], parseInt(o[2].innerHTML));
    tglVoteBar(o[1], parseInt(o[1].innerHTML));
  }
}

function tglSpoiler(obj, spoil) {
  var r = '<select onchange="tglSerialize()">';
  for(var i=-1; i<=2; i++)
    r += '<option value="'+i+'"'+(spoil==i?' selected="selected"':'')+'>'
      +(i == -1 ? 'neutral' : i == 0 ? 'no spoiler' : i == 1 ? 'minor spoiler' : 'major spoiler')
      +'&nbsp;</option>';
  obj.innerHTML = r+'</select>';
}

function tglVoteBar(obj, vote) {
  var r = '';
  for(var i=-3;i<=3;i++)
    r += '<a href="#" class="taglvl taglvl'+i+'" onmouseover="tglVoteBarSel(this, '+i+')"'
       + ' onmouseout="tglVoteBarSel(this, '+vote+')" onclick="return tglVoteBar(this.parentNode, '+i+')">&nbsp;</a>';
  obj.innerHTML = r;
  tglVoteBarSel(obj, vote);
  tglSerialize();
  return false;
}

function tglVoteBarSel(obj, vote) {
  if(obj.className.indexOf('taglvl') >= 0)
    obj = obj.parentNode;
  var l = obj.getElementsByTagName('a');
  var num;
  for(var i=0; i<l.length; i++) {
    if((num = l[i].className.replace(/^.*taglvl(-?[0-3]).*$/, "$1")) == l[i].className)
      continue;
    if(num == 0)
      l[i].innerHTML = vote == 0 ? '-' : vote;
    else if(num<0&&vote<=num || num>0&&vote>=num) {
      if(l[i].className.indexOf('taglvlsel') < 0)
        l[i].className += ' taglvlsel';
    } else
      if(l[i].className.indexOf('taglvlsel') >= 0)
        l[i].className = l[i].className.replace(/taglvlsel/, '');
  }
}

function tglAdd() {
  var n = x('tagtable').getElementsByTagName('tfoot')[0].getElementsByTagName('input');
  n[1].disabled = n[2].disabled = true;
  n[2].value = 'loading...';
  ajax('/xml/tags.xml?q=name:'+encodeURIComponent(n[1].value), function(hr) {
    n[1].disabled = n[1].disabled = false;
    n[2].value = 'Add tag';
    n[1].value = '';

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert('Item not found!');
    if(items[0].getAttribute('meta') == 'yes')
      return alert('Can\'t use meta tags here!');
    var name = items[0].firstChild.nodeValue;
    var l = x('tagtable').getElementsByTagName('a');
    for(var i=0; i<l.length; i++)
      if(l[i].innerHTML == qq(name))
        return alert('Tag is already present!');

    var tr = document.createElement('tr');
    var td = document.createElement('td');
    td.innerHTML = '<a href="/g'+items[0].getAttribute('id')+'">'+qq(name)+'</a>';
    td.className = 'tc1';
    tr.appendChild(td);
    td = document.createElement('td');
    tglVoteBar(td, 2);
    td.className = 'tc2';
    tr.appendChild(td);
    td = document.createElement('td');
    tglSpoiler(td, -1);
    td.className = 'tc3';
    tr.appendChild(td);
    td = document.createElement('td');
    td.className = 'tc4';
    td.innerHTML = '-';
    tr.appendChild(td);
    td = document.createElement('td');
    td.innerHTML = '-';
    td.className = 'tc5';
    tr.appendChild(td);
    x('tagtable').getElementsByTagName('tbody')[0].appendChild(tr);
    tglStripe();
    tglSerialize();
  });
}

function tglStripe() {
  var l = x('tagtable').getElementsByTagName('tbody')[0].getElementsByTagName('tr');
  for(var i=0;i<l.length;i++)
    l[i].className = i%2 ? 'odd' : '';
}

function tglSerialize() {
  var r = '';
  var l = x('tagtable').getElementsByTagName('tbody')[0].getElementsByTagName('tr');
  for(var i=0; i<l.length;i++) {
    var lnk = l[i].getElementsByTagName('a')[0].href;
    var vt = l[i].getElementsByTagName('td')[1].getElementsByTagName('a');
    var id;
    if((id = lnk.replace(/^.*g([1-9][0-9]*)$/, "$1")) != lnk && vt.length > 3 && vt[3].innerHTML != '-')
      r += (r?' ':'')+id+','+vt[3].innerHTML+','+(l[i].getElementsByTagName('select')[0].selectedIndex-1);
  }
  x('taglinks').value = r;
}




// load

if(x('jt_box_rel_vn'))
  vnpLoad('vn');
if(x('jt_box_rel_prod'))
  vnpLoad('producers');
if(x('taglinks'))
  tglLoad();



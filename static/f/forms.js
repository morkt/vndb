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



// load

if(x('jt_box_rel_vn'))
  vnpLoad('vn');
if(x('jt_box_rel_prod'))
  vnpLoad('producers');


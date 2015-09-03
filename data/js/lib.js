window.expanded_icon = '▾',
window.collapsed_icon = '▸';


var ajax_req;
window.ajax = function(url, func, async) {
  if(!async && ajax_req)
    ajax_req.abort();
  var req = window.ActiveXObject ? new ActiveXObject('Microsoft.XMLHTTP') : new XMLHttpRequest();
  if(!async)
    ajax_req = req;
  req.onreadystatechange = function() {
    if(!req || req.readyState != 4 || !req.responseText)
      return;
    if(req.status != 200)
      return alert('Whoops, error! :(');
    func(req);
  };
  url += (url.indexOf('?')>=0 ? ';' : '?')+(Math.floor(Math.random()*999)+1);
  req.open('GET', url, true);
  req.send(null);
};


window.setCookie = function(n,v) {
  var date = new Date();
  date.setTime(date.getTime()+(365*24*60*60*1000));
  document.cookie = VARS.cookie_prefix+n+'='+v+'; expires='+date.toGMTString()+'; path=/';
};

window.getCookie = function(n) {
  var l = document.cookie.split(';');
  n = VARS.cookie_prefix+n;
  for(var i=0; i<l.length; i++) {
    var c = l[i];
    while(c.charAt(0) == ' ')
      c = c.substring(1,c.length);
    if(c.indexOf(n+'=') == 0)
      return c.substring(n.length+1,c.length);
  }
  return null;
};


window.byId = function(n) {
  return document.getElementById(n)
};

window.byName = function(){
  var d = arguments.length > 1 ? arguments[0] : document;
  var n = arguments.length > 1 ? arguments[1] : arguments[0];
  return d.getElementsByTagName(n);
};

window.byClass = function() { // [class], [parent, class], [tagname, class], [parent, tagname, class]
  var par = typeof arguments[0] == 'object' ? arguments[0] : document;
  var t = arguments.length == 2 && typeof arguments[0] == 'string' ? arguments[0] : arguments.length == 3 ? arguments[1] : '*';
  var c = arguments[arguments.length-1];
  var l = byName(par, t);
  var ret = [];
  for(var i=0; i<l.length; i++)
    if(hasClass(l[i], c))
      ret[ret.length] = l[i];
  return ret;
};


/* wrapper around DOM element creation
 * tag('string') -> createTextNode
 * tag('tagname', tag(), 'string', ..) -> createElement(), appendChild(), ..
 * tag('tagname', { class: 'meh', title: 'Title' }) -> createElement(), setAttribute()..
 * tag('tagname', { <attributes> }, <elements>) -> create, setattr, append */
window.tag = function() {
  if(arguments.length == 1)
    return typeof arguments[0] != 'object' ? document.createTextNode(arguments[0]) : arguments[0];
  var el = typeof document.createElementNS != 'undefined'
    ? document.createElementNS('http://www.w3.org/1999/xhtml', arguments[0])
    : document.createElement(arguments[0]);
  for(var i=1; i<arguments.length; i++) {
    if(arguments[i] == null)
      continue;
    if(typeof arguments[i] == 'object' && !arguments[i].appendChild) {
      for(attr in arguments[i]) {
        if(attr == 'style')
          el.setAttribute(attr, arguments[i][attr]);
        else
          el[ attr == 'class' ? 'className' : attr == 'for' ? 'htmlFor' : attr ] = arguments[i][attr];
      }
    } else
      el.appendChild(tag(arguments[i]));
  }
  return el;
};


window.addBody = function(el) {
  if(document.body.appendChild)
    document.body.appendChild(el);
  else if(document.documentElement.appendChild)
    document.documentElement.appendChild(el);
  else if(document.appendChild)
    document.appendChild(el);
};

window.setContent = function() {
  setText(arguments[0], '');
  for(var i=1; i<arguments.length; i++)
    if(arguments[i] != null)
      arguments[0].appendChild(tag(arguments[i]));
};

window.getText = function(obj) {
  return obj.textContent || obj.innerText || '';
};

window.setText = function(obj, txt) {
  if(obj.textContent != null)
    obj.textContent = txt;
  else
    obj.innerText = txt;
};


window.listClass = function(obj) {
  var n = obj.className;
  if(!n)
    return [];
  return n.split(/ /);
};

window.hasClass = function(obj, c) {
  var l = listClass(obj);
  for(var i=0; i<l.length; i++)
    if(l[i] == c)
      return true;
  return false;
};

window.setClass = function(obj, c, set) {
  var l = listClass(obj);
  var n = [];
  if(set) {
    n = l;
    if(!hasClass(obj, c))
      n[n.length] = c;
  } else {
    for(var i=0; i<l.length; i++)
      if(l[i] != c)
        n[n.length] = l[i];
  }
  obj.className = n.join(' ');
};

window.onSubmit = function(form, handler) {
  var prev_handler = form.onsubmit;
  form.onsubmit = function(e) {
    if(prev_handler)
      if(!prev_handler(e))
        return false;
    return handler(e);
  }
};


window.shorten = function(v, l) {
  return v.length > l ? v.substr(0, l-3)+'...' : v;
};


/* maketext function. Less powerful than the Perl equivalent, as it only
 * supports [_n], ~[ and ~]. jsgen.pl is responsible for weeding out the other
 * codes. */
window.mt = function() {
  var key = arguments[0];
  var val = VARS.l10n_str[key] || key;
  // BUG: ~[_1] will get replaced. We don't have a string like that, so whatever.
  for(var i=1; i<arguments.length; i++)
    val = val.replace(new RegExp('\\[_'+i+'\\]', 'g'), arguments[i]);
  return val.replace(/~\[/g, '[').replace(/~\]/g, ']');
};


window.jsonParse = function(s) {
  return s ? JSON.parse(s) : '';
};

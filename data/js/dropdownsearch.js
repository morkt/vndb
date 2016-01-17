/* Interactive drop-down search widget. Usage:
 *
 *   dsInit(obj, url, trfunc, serfunc, retfunc);
 *
 * obj: An <input type="text"> object.
 *
 * url: The base URL of the XML API, e.g. "/xml/tags.xml?q=", the search query is appended to this URL.
 *   The resource at the URL should return an XML document with a
 *     <item id="something" ..>..</item>
 *   element for each result.
 *
 * trfunc(item, tr): Function that is given an <item> object given by the XML
 *   document and an empty <tr> object. The function should format the data of
 *   the item to be shown in the tr.
 *
 * serfunc(item, obj): Called whenever a user selects an item from the search
 *   results. Should return a string, which will be used as the new value of the
 *   input object.
 *
 * retfunc(obj): Called whenever the user selects an item from the search
 *   results (after setfunc()) or when enter is pressed (even if nothing is
 *   selected).
 *
 * setfunc and retfunc can be null.
 *
 * TODO: Some users of this widget consider serfunc() as their final "apply
 *   this selection" function, whereas others use retfunc() for this. Might be
 *   worth investigating whether the additional flexibility offered by
 *   retfunc() is actually necessary, and remove the callback if not.
 */
var boxobj;

function box() {
  if(!boxobj) {
    boxobj = tag('div', {id: 'ds_box', 'class':'hidden'}, tag('b', 'Loading...'));
    addBody(boxobj);
  }
  return boxobj;
}

function init(obj, url, trfunc, serfunc, retfunc) {
  obj.setAttribute('autocomplete', 'off');
  obj.onkeydown = keydown;
  obj.onclick = obj.onchange = obj.oninput = function() { return textchanged(obj); };
  obj.onblur = blur;
  obj.ds_returnFunc = retfunc;
  obj.ds_trFunc = trfunc;
  obj.ds_serFunc = serfunc;
  obj.ds_searchURL = url;
  obj.ds_selectedId = 0;
  obj.ds_dosearch = null;
  obj.ds_lastVal = obj.value;
}

function blur() {
  setTimeout(function () {
    setClass(box(), 'hidden', true)
  }, 500)
}

function setselected(obj, id) {
  obj.ds_selectedId = id;
  var l = byName(box(), 'tr');
  for(var i=0; i<l.length; i++)
    setClass(l[i], 'selected', id && l[i].id == 'ds_box_'+id);
}

function setvalue(obj) {
  if(obj.ds_selectedId != 0)
    obj.value = obj.ds_lastVal = obj.ds_serFunc(byId('ds_box_'+obj.ds_selectedId).ds_itemData, obj);
  if(obj.ds_returnFunc)
    obj.ds_returnFunc(obj);

  setClass(box(), 'hidden', true);
  setContent(box(), tag('b', 'Loading...'));
  setselected(obj, 0);
  if(obj.ds_dosearch) {
    clearTimeout(obj.ds_dosearch);
    obj.ds_dosearch = null;
  }
}

function enter(obj) {
  // Make sure the form doesn't submit when enter is pressed.
  // This solution is a hack, but it's simple and reliable.
  var frm = obj;
  while(frm && frm.nodeName.toLowerCase() != 'form')
    frm = frm.parentNode;
  if(frm) {
    var oldsubmit = frm.onsubmit;
    frm.onsubmit = function() { return false };
    setTimeout(function() { frm.onsubmit = oldsubmit }, 100);
  }

  setvalue(obj);
  return false;
}

function updown(obj, up) {
  var i, sel, l = byName(box(), 'tr');
  if(l.length < 1)
    return true;

  if(obj.ds_selectedId == 0)
    sel = up ? l.length-1 : 0;
  else
    for(i=0; i<l.length; i++)
      if(l[i].id == 'ds_box_'+obj.ds_selectedId)
        sel = up ? (i>0 ? i-1 : l.length-1) : (l[i+1] ? i+1 : 0);

  setselected(obj, l[sel].id.substr(7));
  return false;
}

function textchanged(obj) {
  // Ignore this event if the text hasn't actually changed.
  if(obj.ds_lastVal == obj.value)
    return true;
  obj.ds_lastVal = obj.value;

  // perform search after a timeout
  if(obj.ds_dosearch)
    clearTimeout(obj.ds_dosearch);
  obj.ds_dosearch = setTimeout(function() {
    search(obj);
  }, 500);
  return true;
}

function keydown(ev) {
  var c = document.layers ? ev.which : document.all ? event.keyCode : ev.keyCode;
  var obj = this;

  if(c == 9) // tab
    return true;

  if(c == 13) // enter
    return enter(obj);

  if(c == 38 || c == 40) // up / down
    return updown(obj, c == 38);

  return textchanged(obj);
}

function search(obj) {
  var b = box();
  var val = obj.value;

  clearTimeout(obj.ds_dosearch);
  obj.ds_dosearch = null;

  // hide the ds_box div if the search string is too short
  if(val.length < 2) {
    setClass(b, 'hidden', true);
    setContent(b, tag('b', 'Loading...'));
    setselected(obj, 0);
    return;
  }

  // position the div
  var ddx=0;
  var ddy=obj.offsetHeight;
  var o = obj;
  do {
    ddx += o.offsetLeft;
    ddy += o.offsetTop;
  } while(o = o.offsetParent);

  b.style.position = 'absolute';
  b.style.left = ddx+'px';
  b.style.top = ddy+'px';
  b.style.width = obj.offsetWidth+'px';
  setClass(b, 'hidden', false);

  // perform search
  ajax(obj.ds_searchURL + encodeURIComponent(val), function(hr) { results(hr, obj) });
}

function results(hr, obj) {
  var lst = hr.responseXML.getElementsByTagName('item');
  var b = box();
  if(lst.length < 1) {
    setContent(b, tag('b', 'No results...'));
    setselected(obj, 0);
    return;
  }

  var tb = tag('tbody', null);
  for(var i=0; i<lst.length; i++) {
    var id = lst[i].getAttribute('id');
    var tr = tag('tr', {id: 'ds_box_'+id, ds_itemData: lst[i]} );

    tr.onmouseover = function() { setselected(obj, this.id.substr(7)) };
    tr.onmousedown = function() { setselected(obj, this.id.substr(7)); setvalue(obj) };

    obj.ds_trFunc(lst[i], tr);
    tb.appendChild(tr);
  }
  setContent(b, tag('table', tb));
  setselected(obj, obj.ds_selectedId != 0 && !byId('ds_box_'+obj.ds_selectedId) ? 0 : obj.ds_selectedId);
}

window.dsInit = init;

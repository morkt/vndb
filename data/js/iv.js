/* Simple image viewer widget. Usage:
 *
 *   <a href="full_image.jpg" rel="iv:{width}x{height}:{category}">..</a>
 *
 * Clicking on the above link will cause the image viewer to open
 * full_image.jpg. The {category} part can be empty or absent. If it is not
 * empty, next/previous links will show up to point to the other images within
 * the same category.
 *
 * ivInit() should be called when links with "iv:" tags are dynamically added
 * or removed from the DOM.
 */

// Cache of image categories and the list of associated link objects. Used to
// quickly generate the next/prev links.
var cats;

function init() {
  cats = {};
  var n = 0;
  var l = byName('a');
  for(var i=0;i<l.length;i++) {
    var o = l[i];
    if(o.rel.substr(0,3) == 'iv:' && o.id != 'ivprev' && o.id != 'ivnext') {
      n++;
      o.onclick = show;
      var cat = o.rel.split(':')[2];
      if(cat) {
        if(!cats[cat])
          cats[cat] = [];
        o.iv_i = cats[cat].length;
        cats[cat].push(o);
      }
    }
  }

  if(n && !byId('iv_view')) {
    addBody(tag('div', {id: 'iv_view','class':'hidden'},
      tag('b', {id:'ivimg'}, ''),
      tag('br', null),
      tag('a', {href:'#', id:'ivfull'}, ''),
      tag('a', {href:'#', onclick: close, id:'ivclose'}, mt('_js_close')),
      tag('a', {href:'#', onclick: show, id:'ivprev'}, '« '+mt('_js_iv_prev')),
      tag('a', {href:'#', onclick: show, id:'ivnext'}, mt('_js_iv_next')+' »')
    ));
    addBody(tag('b', {id:'ivimgload','class':'hidden'}, mt('_js_loading')));
  }
}

// Find the next (dir=1) or previous (dir=-1) non-hidden link object for the category.
function findnav(cat, i, dir) {
  for(var j=i+dir; j>=0 && j<cats[cat].length; j+=dir)
    if(!hasClass(cats[cat][j], 'hidden'))
      return cats[cat][j];
  return 0
}

// fix properties of the prev/next links
function fixnav(lnk, cat, i, dir) {
  var a = cat ? findnav(cat, i, dir) : 0;
  lnk.style.visibility = a ? 'visible' : 'hidden';
  lnk.href             = a ? a.href    : '#';
  lnk.rel              = a ? a.rel     : '';
  lnk.iv_i             = a ? a.iv_i    : 0;
}

function show() {
  var u = this.href;
  var opt = this.rel.split(':');
  var idx = this.iv_i;
  var view = byId('iv_view');
  var full = byId('ivfull');

  fixnav(byId('ivprev'), opt[2], idx, -1);
  fixnav(byId('ivnext'), opt[2], idx, 1);

  // calculate dimensions
  var w = Math.floor(opt[1].split('x')[0]);
  var h = Math.floor(opt[1].split('x')[1]);
  var ww = typeof(window.innerWidth) == 'number' ? window.innerWidth : document.documentElement.clientWidth;
  var wh = typeof(window.innerHeight) == 'number' ? window.innerHeight : document.documentElement.clientHeight;
  var st = typeof(window.pageYOffset) == 'number' ? window.pageYOffset : document.body && document.body.scrollTop ? document.body.scrollTop : document.documentElement.scrollTop;
  if(w+100 > ww || h+70 > wh) {
    full.href = u;
    setText(full, w+'x'+h);
    full.style.visibility = 'visible';
    if(w/h > ww/wh) { // width++
      h *= (ww-100)/w;
      w = ww-100;
    } else { // height++
      w *= (wh-70)/h;
      h = wh-70;
    }
  } else
    full.style.visibility = 'hidden';
  var dw = w;
  var dh = h+20;
  dw = dw < 200 ? 200 : dw;

  // update document
  setClass(view, 'hidden', false);
  setContent(byId('ivimg'), tag('img', {src:u, onclick:close,
    onload: function() { setClass(byId('ivimgload'), 'hidden', true); },
    style: 'width: '+w+'px; height: '+h+'px'
  }));
  view.style.width = dw+'px';
  view.style.height = dh+'px';
  view.style.left = ((ww - dw) / 2 - 10)+'px';
  view.style.top = ((wh - dh) / 2 + st - 20)+'px';
  byId('ivimgload').style.left = ((ww - 100) / 2 - 10)+'px';
  byId('ivimgload').style.top = ((wh - 20) / 2 + st)+'px';
  setClass(byId('ivimgload'), 'hidden', false);
  return false;
}

function close() {
  setClass(byId('iv_view'), 'hidden', true);
  setClass(byId('ivimgload'), 'hidden', true);
  setText(byId('ivimg'), '');
  return false;
}

window.ivInit = init;
init();

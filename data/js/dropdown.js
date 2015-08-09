function ddInit(obj, align, contents) {
  obj.dd_align = align; // see ddRefresh for details
  obj.dd_contents = contents;
  document.onmousemove = ddMouseMove;
  document.onscroll = ddHide;
  if(!byId('dd_box'))
    addBody(tag('div', {id:'dd_box', 'class':'hidden', dd_used: false}));
}

function ddHide() {
  var box = byId('dd_box');
  setText(box, '');
  setClass(box, 'hidden', true);
  box.dd_used = false;
  box.dd_lnk = null;
}

function ddMouseMove(e) {
  e = e || window.event;
  var lnk = e.target || e.srcElement;
  while(lnk && (lnk.nodeType == 3 || !lnk.dd_align))
    lnk = lnk.parentNode;
  var box = byId('dd_box');
  if(!box.dd_used && !lnk)
    return;

  if(box.dd_used) {
    var mouseX = e.pageX || (e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft);
    var mouseY = e.pageY || (e.clientY + document.body.scrollTop  + document.documentElement.scrollTop);
    if((mouseX < box.dd_x-10 || mouseX > box.dd_x+box.offsetWidth+10 || mouseY < box.dd_y-10 || mouseY > box.dd_y+box.offsetHeight+10)
        || (lnk && lnk == box.dd_lnk))
      ddHide();
  }

  if(!box.dd_used && lnk || box.dd_used && lnk && box.dd_lnk != lnk) {
    box.dd_lnk = lnk;
    box.dd_used = true;
    if(!ddRefresh())
      ddHide();
  }
}

function ddRefresh() {
  var box = byId('dd_box');
  if(!box.dd_used)
    return false;
  var lnk = box.dd_lnk;
  var content = lnk.dd_contents(lnk, box);
  if(content == null)
    return false;
  setContent(box, content);
  setClass(box, 'hidden', false);

  var o = lnk;
  ddx = ddy = 0;
  do {
    ddx += o.offsetLeft;
    ddy += o.offsetTop;
  } while(o = o.offsetParent);

  if(lnk.dd_align == 'left')
    ddx -= box.offsetWidth;
  if(lnk.dd_align == 'tagmod')
    ddx += lnk.offsetWidth-35;
  if(lnk.dd_align == 'bottom')
    ddy += lnk.offsetHeight;
  box.dd_x = ddx;
  box.dd_y = ddy;
  box.style.left = ddx+'px';
  box.style.top = ddy+'px';
  return true;
}


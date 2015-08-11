/* Dropdown widget, used as follows:
 *
 *   ddInit(obj, align, func);
 *
 * Show a dropdown box on mouse-over on 'obj'. 'func' should generate and
 * return the contents of the box as a DOM node, or null to not show a dropdown
 * box at all. The 'align' argument indicates where the box should be shown,
 * relative to the obj:
 *
 *   left:   To the left of obj
 *   bottom: To the bottom of obj
 *   tagmod: Special alignment for tagmod page
 *
 * Other functions:
 *
 *   ddHide();      Hides the box
 *   ddRefresh();   Refreshes the box contents
 */
(function(){
  var box;

  function init(obj, align, contents) {
    obj.dd_align = align;
    obj.dd_contents = contents;
    obj.onmouseover = show;
  }

  function show() {
    if(!box) {
      box = tag('div', {id:'dd_box', 'class':'hidden'});
      addBody(box);
    }
    box.dd_lnk = this;
    document.onmousemove = mouse;
    document.onscroll = hide;
    refresh();
  }

  function hide() {
    if(box) {
      setText(box, '');
      setClass(box, 'hidden', true);
      box.dd_lnk = document.onmousemove = document.onscroll = null;
    }
  }

  function mouse(e) {
    e = e || window.event;
    // Don't hide if the cursor is on the link
    for(var lnk = e.target || e.srcElement; lnk; lnk=lnk.parentNode)
      if(lnk == box.dd_lnk)
        return;

    // Hide if it's 10px outside of the box
    var mouseX = e.pageX || (e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft);
    var mouseY = e.pageY || (e.clientY + document.body.scrollTop  + document.documentElement.scrollTop);
    if(mouseX < box.dd_x-10 || mouseX > box.dd_x+box.offsetWidth+10 || mouseY < box.dd_y-10 || mouseY > box.dd_y+box.offsetHeight+10)
      hide();
  }

  function refresh() {
    if(!box || !box.dd_lnk)
      return hide();
    var lnk = box.dd_lnk;
    var content = lnk.dd_contents(lnk, box);
    if(content == null)
      return hide();
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
  }

  window.ddInit = init;
  window.ddHide = hide;
  window.ddRefresh = refresh;
})();

var l, lim, spoil = 0, cats = {};


function init() {
  var i;
  l = byName(byId('tagops'), 'a');

  // Categories
  for(i=0; i<3; i++) {
    l[i].tagops_cat = l[i].href.substr(l[i].href.indexOf('#')+1);
    l[i].onclick = function() { cats[this.tagops_cat] = !cats[this.tagops_cat]; return set(); };
    cats[l[i].tagops_cat] = hasClass(l[i], 'tsel');
  }

  // Spoiler level
  for(i=3; i<6; i++) {
    l[i].tagops_spoil = i-3;
    l[i].onclick = function() { spoil = this.tagops_spoil; return set(); };
    if(hasClass(l[i], 'tsel'))
      spoil = i-3;
  }

  // Summary / all
  for(i=6; i<8; i++) {
    l[i].tagops_lim = i == 6;
    l[i].onclick = function() { lim = this.tagops_lim; return set(); };
    if(hasClass(l[i], 'tsel'))
      lim = i == 6;
  }

  set();
}


function set() {
  var i;

  // Set link selection class
  for(i=0; i<8; i++)
    setClass(l[i], 'tsel',
       i < 3 ? cats[l[i].tagops_cat] :
       i < 6 ? l[i].tagops_spoil == spoil
             : l[i].tagops_lim == lim);

  // update tag visibility
  var t = byName(byId('vntags'), 'span');
  var n = 0;
  for(i=0; i<t.length; i++) {
    var v = n < (lim ? 15 : 999);
    for(var j=0; j<3; j++)
      if(hasClass(t[i], 'tagspl'+j))
        v = v && j <= spoil;
    for(var c in cats)
      if(hasClass(t[i], 'cat_'+c))
        v = v && cats[c];
    setClass(t[i], 'hidden', !v);
    n += v?1:0;
  }

  return false;
}


if(byId('tagops'))
  init();

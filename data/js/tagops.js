function tvsInit() {
  if(!byId('tagops'))
    return;
  var l = byName(byId('tagops'), 'a');
  for(var i=0;i<l.length; i++)
    l[i].onclick = tvsClick;
  tvsSet();
}

function tvsClick() {
  var sel;
  var l = byName(byId('tagops'), 'a');
  for(var i=0; i<l.length; i++)
    if(l[i] == this) {
      if(i < 3) { /* categories */
        setClass(l[i], 'tsel', !hasClass(l[i], 'tsel'));
        tvsSet();
      } else if(i < 6) { /* spoiler level */
        tvsSet(i-3);
      } else /* limit */
        tvsSet(null, i == 6);
    }
  return false;
}

function tvsSet(lvl, lim, cats) {
  /* set/get level and limit to/from the links */
  var l = byName(byId('tagops'), 'a');
  var cat = cats || [];
  for(var i=0; i<l.length; i++) {
    if(i < 3) { /* categories */
      var c = l[i].href.substr(l[i].href.indexOf('#')+1);
      if(cats) {
        for(var j=0; j<cats.length && c != cats[j]; j++) ;
        setClass(l[i], 'tsel', j != cats.length);
      } else {
        if(hasClass(l[i], 'tsel'))
          cat.push(c);
      }
    } else if(i < 6) { /* spoiler level */
      if(lvl != null)
        setClass(l[i], 'tsel', i-3 == lvl);
      if(lvl == null && hasClass(l[i], 'tsel'))
        lvl = i-3;
    } else { /* display limit (6 = summary) */
      if(lim != null)
        setClass(l[i], 'tsel', lim == (i == 6));
      if(lim == null && hasClass(l[i], 'tsel'))
        lim = i == 6;
    }
  }

  /* update tag visibility */
  l = byName(byId('vntags'), 'span');
  lim = lim ? 15 : 999;
  var s=0;
  for(i=0;i<l.length;i++) {
    var thislvl = l[i].className.substr(6, 1);
    for(var j=0; j<cat.length && !hasClass(l[i], 'cat_'+cat[j]); j++) ;
    if(thislvl <= lvl && s < lim && j != cat.length) {
      setClass(l[i], 'hidden', false);
      s++;
    } else
      setClass(l[i], 'hidden', true);
  }
}

tvsInit();

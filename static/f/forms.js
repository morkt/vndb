// various form functions
// called by script.js


   /************************\
   *   C A T E G O R I E S  *
   \************************/


function catLoad() {
  var i;
  var cats=[];
  var ct = x('categories');
  var l = ct.value.split(',');
  for(i=0;i<l.length;i++)
    cats[l[i].substr(0,3)] = Math.floor(l[i].substr(3,1));

  l = x('jt_box_categories').getElementsByTagName('a');
  for(i=0;i<l.length;i++) {
    if(l[i].id.substr(0, 4) != 'cat_')
      continue;
    catSet(l[i].id.substr(4), cats[l[i].id.substr(4)]||0);
    l[i].onclick = function() {
      var c = this.id.substr(4);
      if(!cats[c]) cats[c] = 0;
      if(c.substr(0,1) == 'p' || c == 'gaa' || c == 'gab' || c.substr(0,1) == 'h' || c.substr(0,1) == 'l' || c.substr(0,1) == 't') {
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
  // doesn't work very nice with skins...
  var c = rnk == 0 ? '' :
          rnk == 1 ? '#0c0' :
          rnk == 2 ? '#cc0' : '#c00';
  x('b_'+id).style.color = c;
  x('cat_'+id).style.color = c;
  x('b_'+id).innerHTML = rnk;
}



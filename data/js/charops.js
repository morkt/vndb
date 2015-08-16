var spoil, sexual, t;


// Fixes the commas between trait names and the hidden status of the entire row
function fixrow(c) {
  var l = byName(byName(c, 'td')[1], 'span');
  var first = 1;
  for(var i=0; i<l.length; i+=2)
    if(!hasClass(l[i], 'hidden')) {
      setClass(l[i+1], 'hidden', first);
      first = 0;
    }
  setClass(c, 'hidden', first);
}


function restripe() {
  for(var i=0; i<t.length; i++) {
    var b = byName(t[i], 'tbody');
    if(!b.length)
      continue;
    setClass(t[i], 'stripe', false);
    var r = 1;
    var rows = byName(b[0], 'tr');
    for(var j=0; j<rows.length; j++) {
      if(hasClass(rows[j], 'traitrow'))
        fixrow(rows[j]);
      if(!hasClass(rows[j], 'nostripe') && !hasClass(rows[j], 'hidden'))
        setClass(rows[j], 'odd', r++&1);
    }
  }
}


function setall(h) {
  var k = byClass('charspoil');
  for(var i=0; i<k.length; i++)
    setClass(k[i], 'hidden',
      !sexual && hasClass(k[i], 'sexual') ? true :
      hasClass(k[i], 'charspoil_0') ? false :
      hasClass(k[i], 'charspoil_-1') ? spoil > 1 :
      hasClass(k[i], 'charspoil_1') ? spoil < 1 : spoil < 2);
  for(var i=0; i<3; i++)
    setClass(h[i], 'sel', spoil == i);
  if(h[3])
    setClass(h[3], 'sel', sexual);
  if(k.length)
    restripe();
  return false;
}


function init() {
  var h = byName(byId('charops'), 'a');
  t = byClass('table', 'stripe');

  // Spoiler level
  for(var i=0; i<3; i++) {
    h[i].num = i;
    h[i].onclick = function() {
      spoil = this.num;
      return setall(h);
    };
    if(hasClass(h[i], 'sel'))
      spoil = i;
  };

  // Sexual toggle
  if(h[3]) {
    h[3].onclick = function() {
      sexual = !sexual;
      return setall(h);
    };
    sexual = hasClass(h[3], 'sel');
  }
  setall(h);
}


if(byId('charops'))
  init();

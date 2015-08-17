function medLoad() {
  // load the selected media
  var med = byId('media').value.split(',');
  for(var i=0; i<med.length && med[i].length > 1; i++)
    medAdd(med[i].split(' ')[0], Math.floor(med[i].split(' ')[1]));

  medAdd('', 0);
}

function medAdd(med, qty) {
  var qsel = tag('select', {'class':'qty', onchange:medSerialize}, tag('option', {value:0}, mt('_redit_form_med_quantity')));
  for(var i=1; i<=20; i++)
    qsel.appendChild(tag('option', {value:i, selected: qty==i}, i));

  var msel = tag('select', {'class':'medium', onchange: med == '' ? medFormAdd : medSerialize});
  if(med == '')
    msel.appendChild(tag('option', {value:''}, mt('_redit_form_med_medium')));
  for(var i=0; i<VARS.media.length; i++)
    msel.appendChild(tag('option', {value:VARS.media[i][0], selected: med==VARS.media[i][0]}, VARS.media[i][1]));

  byId('media_div').appendChild(tag('span', qsel, msel,
    med != '' ? tag('input', {type: 'button', 'class':'submit', onclick:medDel, value:mt('_js_remove')}) : null
  ));
}

function medDel() {
  var span = this;
  while(span.nodeName.toLowerCase() != 'span')
    span = span.parentNode;
  byId('media_div').removeChild(span);
  medSerialize();
  return false;
}

function medFormAdd() {
  var span = this;
  while(span.nodeName.toLowerCase() != 'span')
    span = span.parentNode;
  var med = byClass(span, 'select', 'medium')[0];
  var qty = byClass(span, 'select', 'qty')[0];
  if(!med.selectedIndex)
    return;
  medAdd(med.options[med.selectedIndex].value, qty.options[qty.selectedIndex].value);
  byId('media_div').removeChild(span);
  medAdd('', 0);
  medSerialize();
}

function medSerialize() {
  var r = [];
  var meds = byName(byId('media_div'), 'span');
  for(var i=0; i<meds.length-1; i++) {
    var med = byClass(meds[i], 'select', 'medium')[0];
    var qty = byClass(meds[i], 'select', 'qty')[0];

    /* correct quantity if necessary */
    if(VARS.media[med.selectedIndex][2] && !qty.selectedIndex)
      qty.selectedIndex = 1;
    if(!VARS.media[med.selectedIndex][2] && qty.selectedIndex)
      qty.selectedIndex = 0;

    r[r.length] = VARS.media[med.selectedIndex][0] + ' ' + qty.selectedIndex;
  }
  byId('media').value = r.join(',');
}

if(byId('jt_box_rel_format'))
  medLoad();

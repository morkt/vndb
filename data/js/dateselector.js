function dateLoad(obj, serfunc) {
  var year = tag('select', {style: 'width: 70px', onfocus:serfunc, onchange: dateSerialize, tabIndex: 10},
    tag('option', {value:0}, mt('_js_date_year')),
    tag('option', {value: 9999}, 'TBA')
  );
  for(var i=(new Date()).getFullYear()+5; i>=1980; i--)
    year.appendChild(tag('option', {value: i}, i));

  var month = tag('select', {style: 'width: 70px', onfocus:serfunc, onchange: dateSerialize, tabIndex: 10},
    tag('option', {value:99}, mt('_js_date_month'))
  );
  for(var i=1; i<=12; i++)
    month.appendChild(tag('option', {value: i}, i));

  var day = tag('select', {style: 'width: 70px', onfocus:serfunc, onchange: dateSerialize, tabIndex: 10},
    tag('option', {value:99}, mt('_js_date_day'))
  );
  for(var i=1; i<=31; i++)
    day.appendChild(tag('option', {value: i}, i));

  var div = tag('div', {date_obj: obj, date_serfunc: serfunc, date_val: obj ? obj.value : 0}, year, month, day);
  dateSet(div, obj ? obj.value : 0);
  return obj ? obj.parentNode.insertBefore(div, obj) : div;
}

function dateSet(div, val) {
  val = typeof val == 'object' ? val[0] : val;
  val = Math.floor(val) || 0;
  val = [ Math.floor(val/10000), Math.floor(val/100)%100, val%100 ];
  if(val[1] == 0) val[1] = 99;
  if(val[2] == 0) val[2] = 99;
  var l = byName(div, 'select');
  for(var i=0; i<l.length; i++)
    for(var j=0; j<l[i].options.length; j++)
      l[i].options[j].selected = l[i].options[j].value == val[i];
  dateSerialize(div.childNodes[0], true);
}

function dateSerialize(div, nonotify) {
  var div = div && div.parentNode ? div.parentNode : this.parentNode;
  var sel = byName(div, 'select');
  var val = [
    sel[0].options[sel[0].selectedIndex].value*1,
    sel[1].options[sel[1].selectedIndex].value*1,
    sel[2].options[sel[2].selectedIndex].value*1
  ];
  div.date_val = val[0] == 0 ? 0 : val[0] == 9999 ? 99999999 : val[0]*10000+val[1]*100+(val[1]==99?99:val[2]);
  if(div.date_obj)
    div.date_obj.value = div.date_val;
  if(!nonotify && div.date_serfunc)
    div.date_serfunc(div);
}

{
  var l = byClass('input', 'dateinput');
  for(i=0; i<l.length; i++)
    dateLoad(l[i]);
}

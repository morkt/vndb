/* Date selector widget for the 'release date'-style dates, with support for
 * TBA and unknown month or day. Usage:
 *
 *   <input type="hidden" class="dateinput" .. />
 *
 * Will add a date selector to the HTML at that place, and automatically
 * read/write the value of the hidden field. Alternative usage:
 *
 *   var obj = dateLoad(ref, serfunc);
 *
 * If 'ref' is set, it will behave as above with 'ref' being the input object.
 * Otherwise it will return the widget object. The setfunc, if set, will be
 * called whenever the date widget is focussed or its value is changed.
 *
 * The object returned by dateLoad() can be used as follows:
 *   obj.date_val:      Always contains the currently selected date.
 *   obj.dateSet(val):  Change the selected date
 */
function load(obj, serfunc) {
  var i;
  var selops = {style: 'width: 70px', onfocus:serfunc, onchange: serialize, tabIndex: 10};

  var year = tag('select', selops,
    tag('option', {value:0}, mt('_js_date_year')),
    tag('option', {value:9999}, 'TBA')
  );
  for(i=(new Date()).getFullYear()+5; i>=1980; i--)
    year.appendChild(tag('option', {value: i}, i));

  var month = tag('select', selops,
    tag('option', {value:99}, mt('_js_date_month'))
  );
  for(i=1; i<=12; i++)
    month.appendChild(tag('option', {value: i}, i));

  var day = tag('select', selops,
    tag('option', {value:99}, mt('_js_date_day'))
  );
  for(i=1; i<=31; i++)
    day.appendChild(tag('option', {value: i}, i));

  var div = tag('div', {
      date_obj: obj,
      date_serfunc: serfunc,
      date_val: obj ? obj.value : 0
    }, year, month, day);
  div.dateSet = function(v){ set(div, v) };

  set(div, div.date_val);
  return obj ? obj.parentNode.insertBefore(div, obj) : div;
}

function set(div, val) {
  val = +val || 0;
  val = [ Math.floor(val/10000), Math.floor(val/100)%100, val%100 ];
  if(val[1] == 0) val[1] = 99;
  if(val[2] == 0) val[2] = 99;
  var l = byName(div, 'select');
  for(var i=0; i<l.length; i++)
    for(var j=0; j<l[i].options.length; j++)
      l[i].options[j].selected = l[i].options[j].value == val[i];
  serialize(div, true);
}

function serialize(div, nonotify) {
  div = div.dateSet ? div : this.parentNode;
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

var l = byClass('input', 'dateinput');
for(var i=0; i<l.length; i++)
  load(l[i]);

window.dateLoad = load;

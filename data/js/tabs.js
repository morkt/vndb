/* Javascript tabs. General usage:
 *
 *   <ul id="jt_select">
 *    <li><a href="#<name>" id="jt_sel_<name>">..</a></li>
 *    ..
 *   </ul>
 *
 * Can then be used to show/hide the following box:
 *
 *   <div id="jt_box_<name>"> .. </div>
 *
 * The name of the active box will be set to and (at page load) read from
 * location.hash. The parent node of the active link will get the 'tabselected'
 * class. A link with the special name "all" will display all boxes associated
 * with jt_select links.
 *
 * Only one jt_select list-of-tabs can be used on a single page.
 */
var links = byId('jt_select') ? byName(byId('jt_select'), 'a') : [];

function init() {
  var sel;
  var first;
  for(var i=0; i<links.length; i++) {
    links[i].onclick = function() { set(this.id); return false };
    if(!first)
      first = links[i].id;
    if(location.hash && links[i].id == 'jt_sel_'+location.hash.substr(1))
      sel = links[i].id;
  }
  if(first)
    set(sel||first, 1);
}

function set(which, nolink) {
  which = which.substr(7);

  for(var i=0; i<links.length; i++) {
    var name = links[i].id.substr(7);
    if(name != 'all')
      setClass(byId('jt_box_'+name), 'hidden', which != 'all' && which != name);
    setClass(links[i].parentNode, 'tabselected', name == which);
  }

  if(!nolink)
    location.href = '#'+which;
}

init();

var tglSpoilers = [];

function tglLoad() {
  for(var i=0; i<=3; i++)
    tglSpoilers[i] = fmtspoil(i-1);

  // tag dropdown search
  dsInit(byId('tagmod_tag'), '/xml/tags.xml?q=', function(item, tr) {
    tr.appendChild(tag('td',
      shorten(item.firstChild.nodeValue, 40),
      item.getAttribute('meta') == 'yes' ? tag('b', {'class':'grayedout'}, ' meta') :
      item.getAttribute('state') == 0    ? tag('b', {'class':'grayedout'}, ' awaiting moderation') : null
    ));
  }, function(item) {
    return item.firstChild.nodeValue;
  }, tglAdd);
  byId('tagmod_add').onclick = tglAdd;

  // JS'ify the voting bar and spoiler setting
  var trs = byName(byId('tagtable'), 'tr');
  for(var i=0; i<trs.length; i++) {
    if(hasClass(trs[i], 'tagmod_cat'))
      continue;
    var vote = byClass(trs[i], 'td', 'tc_myvote')[0];
    vote.tgl_vote = getText(vote)*1;
    tglVoteBar(vote);

    var spoil = byClass(trs[i], 'td', 'tc_myspoil')[0];
    spoil.tgl_spoil = getText(spoil)*1+1;
    setText(spoil, tglSpoilers[spoil.tgl_spoil]);
    ddInit(spoil, 'tagmod', tglSpoilDD);
    spoil.onclick = tglSpoilNext;
  }
  tglSerialize();
}

function tglSpoilNext() {
  if(++this.tgl_spoil >= tglSpoilers.length)
    this.tgl_spoil = 0;
  setText(this, tglSpoilers[this.tgl_spoil]);
  tglSerialize();
  ddRefresh();
}

function tglSpoilDD(lnk) {
  var lst = tag('ul', null);
  for(var i=0; i<tglSpoilers.length; i++)
    lst.appendChild(tag('li', i == lnk.tgl_spoil
      ? tag('i', tglSpoilers[i])
      : tag('a', {href: '#', onclick:tglSpoilSet, tgl_td:lnk, tgl_sp:i}, tglSpoilers[i])
    ));
  return lst;
}

function tglSpoilSet() {
  this.tgl_td.tgl_spoil = this.tgl_sp;
  setText(this.tgl_td, tglSpoilers[this.tgl_sp]);
  ddHide();
  tglSerialize();
  return false;
}

function tglVoteBar(td, vote) {
  setText(td, '');
  for(var i=-3; i<=3; i++)
    td.appendChild(tag('a', {
      'class':'taglvl taglvl'+i, tgl_num: i,
      onmouseover:tglVoteBarSel, onmouseout:tglVoteBarSel, onclick:tglVoteBarSel
    }, ' '));
  tglVoteBarSel(td, td.tgl_vote);
  return false;
}

function tglVoteBarSel(td, vote) {
  // nasty trick to make this function multifunctional
  if(this && this.tgl_num != null) {
    var e = td || window.event;
    td = this.parentNode;
    vote = this.tgl_num;
    if(e.type.toLowerCase() == 'click') {
      td.tgl_vote = vote;
      tglSerialize();
    }
    if(e.type.toLowerCase() == 'mouseout')
      vote = td.tgl_vote;
  }
  var l = byName(td, 'a');
  var num;
  for(var i=0; i<l.length; i++) {
    num = l[i].tgl_num;
    if(num == 0)
      setText(l[i], vote || '-');
    else
      setClass(l[i], 'taglvlsel', num<0&&vote<=num || num>0&&vote>=num);
  }
}

function tglAdd() {
  var tg = byId('tagmod_tag');
  var add = byId('tagmod_add');
  tg.disabled = add.disabled = true;
  add.value = 'Loading...';

  ajax('/xml/tags.xml?q=name:'+encodeURIComponent(tg.value), function(hr) {
    tg.disabled = add.disabled = false;
    tg.value = '';
    add.value = 'Add tag';

    var items = hr.responseXML.getElementsByTagName('item');
    if(items.length < 1)
      return alert('Item not found!');
    if(items[0].getAttribute('meta') == 'yes')
      return alert('Can\'t use meta tags here!');

    var name = items[0].firstChild.nodeValue;
    var id = items[0].getAttribute('id');
    if(byId('tgl_'+id))
      return alert('Tag is already present!');

    if(!byId('tagmod_newtags'))
      byId('tagtable').appendChild(tag('tr', {'class':'tagmod_cat', id:'tagmod_newtags'},
        tag('td', {colspan:7}, 'Newly added')));

    var vote = tag('td', {'class':'tc_myvote', tgl_vote: 2}, '');
    tglVoteBar(vote);
    var spoil = tag('td', {'class':'tc_myspoil', tgl_spoil: 0}, tglSpoilers[0]);
    ddInit(spoil, 'tagmod', tglSpoilDD);
    spoil.onclick = tglSpoilNext;

    var ismod = byClass(byId('tagtable').parentNode, 'td', 'tc_myover').length;

    byId('tagtable').appendChild(tag('tr', {id:'tgl_'+id},
      tag('td', {'class':'tc_tagname'}, tag('a', {href:'/g'+id}, name)),
      vote,
      ismod ? tag('td', {'class':'tc_myover'}, ' ') : null,
      spoil,
      tag('td', {'class':'tc_allvote'}, ' '),
      tag('td', {'class':'tc_allspoil'}, ' '),
      tag('td', {'class':'tc_allwho'}, '')
    ));
    tglSerialize();
  });
}

function tglSerialize() {
  var r = [];
  var l = byName(byId('tagtable'), 'tr');
  for(var i=0; i<l.length; i++) {
    if(hasClass(l[i], 'tagmod_cat'))
      continue;
    var vote = byClass(l[i], 'td', 'tc_myvote')[0].tgl_vote;
    if(vote != 0)
      r[r.length] = [
        l[i].id.substr(4),
        vote,
        byClass(l[i], 'td', 'tc_myspoil')[0].tgl_spoil-1
      ].join(',');
  }
  byId('taglinks').value = r.join(' ');
}

if(byId('taglinks'))
  tglLoad();

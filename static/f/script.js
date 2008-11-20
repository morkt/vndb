
/*  G L O B A L   S T U F F  */

function x(y){return document.getElementById(y)}
function cl(o,f){if(x(o))x(o).onclick=f}
function DOMLoad(y){var d=0;var f=function(){if(d++)return;y()};
if(document.addEventListener)document.addEventListener("DOMCont"
+"entLoaded",f,false);document.write("<script id=_ie defer src="
+"javascript:void(0)><\/script>");document.getElementById('_ie')
.onreadystatechange=function(){if(this.readyState=="complete")f()
};if(/WebKit/i.test(navigator.userAgent))var t=setInterval(
function(){if(/loaded|complete/.test(document.readyState)){
clearInterval(t);f()}},10);window.onload=f;}




/*  O N L O A D   E V E N T  */

DOMLoad(function() {

  // show/hide NSFW VN image
  cl('nsfw_show', function() {
    x('nsfw_show').style.display = 'none';
    x('nsfw_hid').style.display = 'block';
    x('nsfw_hid').onclick = function() {
      x('nsfw_show').style.display = 'block';
      x('nsfw_hid').style.display = 'none';
    };
    return false
  });


  // spam protection on all forms
  if(document.forms.length >= 1)
    for(i=0; i<document.forms.length; i++)
      document.forms[i].action = document.forms[i].action.replace(/\/nospam\?/,'');

});

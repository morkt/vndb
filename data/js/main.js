/* This is the main Javascript file. This file is processed by util/jsgen.pl to
 * generate the final JS file(s) used by the site. */

// Variables from jsgen.pl
VARS = /*VARS*/;

/* The include directives below automatically wrap the file contents inside an
 * anonymous function, so each file has its own local namespace. Included files
 * can't access variables or functions from other files, unless these variables
 * are explicitely shared in DOM objects or (more commonly) the global 'window'
 * object.
 */

// Reusable library functions
//include lib.js

// Reusable widgets
//include iv.js
//include dropdown.js
//include dateselector.js
//include dropdownsearch.js
//include tabs.js

// Page/functionality-specific widgets
//include vnreldropdown.js
//include tagops.js
//include charops.js
//include filter.js
//include misc.js
//include polls.js

// VN editing (/v+/edit)
//include vnrel.js
//include vnscr.js
//include vnstaff.js
//include vncast.js

// VN tag editing (/v+/tagmod)
//include vntagmod.js

// Release editing (/r+/edit)
//include relmedia.js
//include relvns.js
//include relprod.js

// Producer editing (/p+/edit)
//include prodrel.js

// Character editing (/c+/edit)
//include chartraits.js
//include charvns.js

// Staff editing (/s+/edit)
//include staffalias.js

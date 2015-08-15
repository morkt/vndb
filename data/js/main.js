/* This is the main Javascript file. This file is processed by util/jsgen.pl to
 * generate the final JS file(s) used by the site.
 *
 *
 * Internationalization note:
 *
 *   The translation keys to be inserted in the generates JS file are parsed
 *   from the source code. So when using mt(), make sure it is in the following
 *   format:
 *     mt('<exact translation key>',<more arguments>
 *   or
 *     mt('<exact translation key>')
 *   The single quotes and (lack of) spaces are significant!
 *
 *   To use non-exact translation keys as argument to mt(), make sure to
 *   indicate which keys should be inserted in the header by adding a comment
 *   containing the following format:
 *     l10n /<perl regex>/
 *   any keys matching that regex will be included.
 *
 *   In the case of an mt('<key>') without any extra arguments, the entire
 *   function call may be replaced by the TL string.
 */

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

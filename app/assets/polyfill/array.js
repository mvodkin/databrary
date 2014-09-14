'use strict';

if (!Array.isArray) {
  Array.isArray = function (a) {
    return Object.prototype.toString.call(a) === '[object Array]';
  };
}

/* These are purposefully not as robust as it ought to be, since we don't need it to be. */
if (!Array.prototype.find) {
  Object.defineProperty(Array.prototype, 'find', {
    value: function (predicate, scope) {
      for (var i = 0, l = this.length; i < l; i ++)
	if (predicate.call(scope, this[i], i, this))
	  return this[i];
      return undefined;
    }
  });
}

if (!Array.prototype.findIndex) {
  Object.defineProperty(Array.prototype, 'findIndex', {
    value: function (predicate, scope) {
      for (var i = 0, l = this.length; i < l; i ++)
	if (predicate.call(scope, this[i], i, this))
	  return i;
      return -1;
    }
  });
}

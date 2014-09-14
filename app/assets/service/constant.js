'use strict';

module.factory('constantService', [
  '$log', '$sce', 'constantData', function ($log, $sce, constants) {
    
    constants.regex = {
      doi: /^(?:[dD][oO][iI]:|(?:http:\/\/)?dx\.doi\.org\/)?(10\.[0-9\.]+\/\S+)\s*$/,
    };

    //

    var invertArray = function (data) {
      var r = {};
      angular.forEach(data, function (x, id) {
        r[x] = id;
      });
      return r;
    };

    var invertBy = function (data, field) {
      var r = {};
      angular.forEach(data, function (x) {
        if (field in x)
          r[x[field]] = x;
      });
      return r;
    };

    constants.permissionName = invertArray(constants.permission);
    constants.classificationName = invertArray(constants.classification);
    constants.consentName = invertArray(constants.consent);
    constants.categoryName = invertBy(constants.category, "name");
    constants.metricName = invertBy(constants.metric, "name");

    /* convenient aliases: */
    constants.permissionName.CONTRIBUTE = constants.permissionName.EDIT;
    constants.permissionName.SUPER = constants.permission.length;

    /* backwards compatibility: */
    angular.forEach(constants.party, function (party, name) {
      var uname = name.toUpperCase();
      if (angular.isObject(party) && name !== uname)
	constants.party[uname] = party.id;
    });

    angular.forEach(constants.category, function (cat) {
      cat.not = constants.messages['not.' + cat.name] || 'No ' + cat.name;
    });

    angular.forEach(constants.format, function (fmt) {
      var m = fmt.mimetype;
      fmt.type = m.slice(0, m.indexOf('/'));
    });

    constants.accessGlobal = [
      [constants.permissionName.NONE, constants.permissionName.NONE],
      [constants.permissionName.PUBLIC, constants.permissionName.SHARED]
    ];
    constants.accessGlobal.parties = [
      constants.party.NOBODY,
      constants.party.ROOT
    ];

    constants.message = function (key /*, args...*/) {
      var msg = constants.messages[key];

      if (msg === undefined) {
        $log.info('Message key [' + key + '] is undefined.');
        return '[' + key + ']';
      }

      var i = 1, l = arguments.length;
      var o;
      if (i < l && typeof arguments[i] === 'object')
	o = arguments[i++];
      else
	o = {};

      var g = o.sce ? $sce.getTrusted.bind($sce, o.sce) : angular.identity;
      for (var n = 0; i < l; i++, n++)
        msg = msg.replace('{' + n + '}', g(arguments[i]), 'g');
      if (o.sce)
	msg = $sce.trustAs(o.sce, msg);

      return msg;
    };

    function deepFreeze(o) {
      Object.freeze(o);
      for (var f in o)
	if (o.hasOwnProperty(f)) {
	  var v = o[f];
	  if (v instanceof Object && !Object.isFrozen(v))
	    deepFreeze(v);
	}
      return o;
    }
    constants.deepFreeze = deepFreeze;

    return deepFreeze(constants);
  }
]);

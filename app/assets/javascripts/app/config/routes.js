define(['app/modules/dbModule'], function (dbModule) {
	'use strict';

	return dbModule.config(['$locationProvider', '$routeProvider', function ($locationProvider, $routeProvider) {
		$locationProvider.html5Mode(true);

		//

		var viewStaticCtrl = {
			controller: 'ViewStaticCtrl',
			templateUrl: 'viewStaticCtrl.html',
			reloadOnSearch: false
		};

		$routeProvider.when('/', viewStaticCtrl);
		$routeProvider.when('/about/:page*', viewStaticCtrl);

		//

		$routeProvider.otherwise({
			redirectTo: '/'
		});
	}]);
});

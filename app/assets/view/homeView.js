'use strict';

module.controller('homeView', [
  '$scope', 'investigators', 'users', 'volume', 'pageService',
  function ($scope, investigators, users, volume, page) {
    page.display.title = page.constants.message('page.title.home');
    $scope.investigators = page.$filter('orderBy')(investigators, 'lastName');
    $scope.users = page.$filter('orderBy')(users, 'lastName');
    $scope.volume = volume;
  }
]);

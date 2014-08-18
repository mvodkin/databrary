'use strict';

module.controller('slotView', [
  '$scope', 'slot', 'pageService', function ($scope, slot, page) {
    page.display.title = page.types.slotName(slot);
    page.display.toolbarLinks = [];

    // helpers

    var getAsset = function (media) {
      return media && media.element ? media.asset : media;
    };

    var getMedia = function (media) {
      return media && media.element ? media : ctrl.filter(function (m) {
        return m.asset === media;
      }).pop();
    };

    // controller

    var ctrl = {
      slot: slot,

      media: [],
      current: [slot.assets[0]],

      state: {
        selection: null,
      },

      registerMedia: function (media) {
        ctrl.media.push(media);

        media.$scope.$on('$destroy', function () {
          ctrl.deregisterMedia(media);
        });
      },

      deregisterMedia: function (media) {
        var i = ctrl.media.indexOf(media);

        if (i > -1) {
          ctrl.media.splice(i, 1);
        }
      },

      setCurrent: function (asset) {
        ctrl.current[0] = asset;
      },

      isCurrent: function (media) {
        if (media.asset && media.asset.id)
          return ctrl.current[0] === media;
        else
          return ctrl.current[0] === media.asset;
      },

      select: function (media) {
        ctrl.current[0] = media.asset;
      },

      jump: function (asset) {
        var $track = $('#slot-timeline-track-' + asset.asset.id);
        page.display.scrollTo($track);
      },

      hasPosition: function (media) {
        var asset = getAsset(media);
        return asset.segment;
      },

      hasDuration: function (media) {
        var asset = getAsset(media);
        return angular.isArray(asset.segment);
      },

      hasDisplay: function (media) {
        var asset = getAsset(media);
        return ['video', 'image'].indexOf(page.types.assetMimeArray(asset, true)[0]) > -1;
      },

      hasTime: function (media) {
        var asset = getAsset(media);
        return ['video'].indexOf(page.types.assetMimeArray(asset, true)[0]) > -1;
      },

      isNowPlayable: function (media) {
        var asset = getAsset(media);
        return ctrl.clock.position > asset.segment[0] && ctrl.clock.position < asset.segment[1];
      },

      isReady: function (media) {
        media = getMedia(media);
        return media.element.readyState >= 4;
      },

      isPaused: function (media) {
        media = getMedia(media);
        return media.element.paused;
      },
    };

    // clock

    ctrl.clock = new page.slotClock(slot, ctrl);

    // callbacks

//    var callbackPlay = function () {
//      ctrl.media.forEach(function (m) {
//        if (ctrl.hasTime(m) && ctrl.hasDuration(m)) {
//          if (ctrl.isNowPlayable(m)) {
//            m.element.play();
//          } else if (!ctrl.isPaused(m)) {
//            m.element.pause();
//          }
//        }
//      });
//    };
//
//    var callbackJump = function () {
//      ctrl.media.forEach(function (m) {
//        if (ctrl.hasTime(m) && ctrl.hasDuration(m) && ctrl.isNowPlayable(m)) {
//          m.element.currentTime = (ctrl.clock.position - m.asset.segment[0]) / 1000;
//        }
//      });
//    };
//
//    var callbackPause = function () {
//      ctrl.media.forEach(function (media) {
//        if (ctrl.hasTime(media) && ctrl.hasDuration(media)) {
//          media.element.pause();
//        }
//      });
//    };

    var callbackTime = function () {
      var isTimed = ctrl.hasDuration(ctrl.current[0]);

      ctrl.media.forEach(function (media) {
        if (isTimed) { // one of many timed assets

        } else if (ctrl.isCurrent(media)) { // the one untimed asset

        }
      });
    };

//    ctrl.clock.playFn(callbackPlay);
//    ctrl.clock.jumpFn(callbackJump);
//    ctrl.clock.pauseFn(callbackPause);
    ctrl.clock.timeFn(callbackTime);

    // return

    $scope.ctrl = ctrl;
    return ctrl;
  }
]);

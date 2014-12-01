'use strict'

app.controller 'volume/overview', [
  '$scope', 'constantService',
  ($scope, constants) ->
    generateSummary = (volume) ->
      agemin = Infinity
      agemax = -Infinity
      agesum = 0
      ages = 0
      sessions = 0
      shared = 0

      Participant = constants.categoryName.participant.id
      for ci, c of volume.containers when !c.top
        sessions++
        shared++ if c.consent >= constants.consent.SHARED
        for r in c.records when 'age' of r and volume.records[r.id].category == Participant
          if r.age < agemin
            agemin = r.age
          if r.age > agemax
            agemax = r.age
          agesum += r.age
          ages++

      volume.summary =
        sessions: sessions
        shared: shared
        agemin: if agemin < Infinity then agemin
        agemax: if agemax > -Infinity then agemax
        agemean: if ages then agesum / ages

    generateSummary($scope.volume) unless $scope.volume.summary

    return
]

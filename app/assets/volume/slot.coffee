'use strict'

app.controller('volume/slot', [
  '$scope', '$location', '$sce', '$q', 'constantService', 'displayService', 'messageService', 'Offset', 'Segment', 'Store', 'slot', 'edit',
  ($scope, $location, $sce, $q, constants, display, messages, Offset, Segment, Store, slot, editing) ->
    display.title = slot.displayName
    $scope.flowOptions = Store.flowOptions
    $scope.slot = slot
    $scope.volume = slot.volume
    $scope.editing = editing
    $scope.mode = if editing then 'edit' else 'view'
    target = $location.search()
    $scope.form = {}
    ruler = $scope.ruler =
      range: new Segment(Infinity, -Infinity)
      selection: if 'select' of target then new Segment(target.select) else Segment.empty
      position: Offset.parse(target.pos)

    $flow = $scope.$flow # not really in this scope
    video = undefined
    blank = undefined

    searchLocation = (url) ->
      url
        .search('asset', undefined)
        .search('record', undefined)
        .search($scope.current?.type || '', $scope.current?.id)
        .search('select', ruler.selection?.format())

    if editing || slot.checkPermission(constants.permission.EDIT)
      url = if editing then slot.route() else slot.editRoute()
      display.toolbarLinks.push
        type: 'yellow'
        html: constants.message(if editing then 'slot.view' else 'slot.edit')
        #url: url
        click: ->
          searchLocation($location.url(url))
          return

    byId = (a, b) -> a.id - b.id
    byPosition = (a, b) -> a.segment.l - b.segment.l

    updateRange = (segment) ->
      if isFinite(slot.segment.l)
        ruler.range.l = slot.segment.l
      else if isFinite(segment.l) && segment.l < ruler.range.l
        ruler.range.l = segment.l
      
      if isFinite(slot.segment.u)
        ruler.range.u = slot.segment.u
      else if isFinite(segment.u) && segment.u > ruler.range.u
        ruler.range.u = segment.u

      return

    offsetPosition = (offset) ->
      return offset unless isFinite offset
      (offset - ruler.range.base) / (ruler.range.u - ruler.range.l)

    tl = document.getElementById('slot-timeline')
    positionOffset = (position) ->
      tlr = tl.getBoundingClientRect()
      p = (position - tlr.left) / tlr.width
      if p >= 0 && p <= 1
        ruler.range.l + p * (ruler.range.u - ruler.range.l)

    $scope.positionStyle = (p) ->
      styles = {}
      return styles unless p?
      if p instanceof Segment
        l = offsetPosition(p.l)
        if l < 0
          styles.left = '0px'
          styles['border-left'] = '0px'
          styles['border-top-left-radius'] = '0px'
          styles['border-bottom-left-radius'] = '0px'
        else if l <= 1
          styles.left = 100*l + '%'
        r = offsetPosition(p.u)
        if r > 1
          styles.right = '0px'
          styles['border-right'] = '0px'
          styles['border-top-right-radius'] = '0px'
          styles['border-bottom-right-radius'] = '0px'
        else if r >= 0
          styles.right = 100 - 100*r + '%'
      else
        p = offsetPosition(p)
        if p >= 0 && p <= 1
          styles.left = 100*p + '%'
      styles

    seekOffset = (o) ->
      if video && $scope.current?.asset?.segment.contains(o) && isFinite($scope.current.asset.segment.l)
        video[0].currentTime = (o - $scope.current.asset.segment.l) / 1000
      ruler.position = o
      return

    seekPosition = (pos) ->
      if o = positionOffset(pos)
        seekOffset(o)
        unless ruler.selection.empty || ruler.selection.contains(o) || ruler.selection.u == o # "loose" contains
          ruler.selection = Segment.empty
      return

    $scope.play = ->
      if video
        video[0].play()
      else
        $scope.playing = 1
      return

    $scope.pause = ->
      if video
        video[0].pause()
      else
        $scope.playing = 0
      return

    sortTracks = ->
      return unless $scope.tracks
      $scope.tracks.sort (a, b) ->
        if a.asset && b.asset
          isFinite(b.asset.segment.l) - isFinite(a.asset.segment.l) ||
            a.asset.segment.l - b.asset.segment.l ||
            a.asset.segment.u - b.asset.segment.u ||
            a.id - b.id
        else
          !a.asset - !b.asset || !a.file - !b.file
      return

    stayDirty = (global) ->
      if global || editing && $scope.current && $scope.form.edit && ($scope.current.dirty = $scope.form.edit.$dirty)
        not confirm(constants.message('navigation.confirmation'))

    select = (c) ->
      return false if stayDirty()

      $scope.current = c
      searchLocation($location.replace())
      delete target.asset
      delete target.record

      blank.fillData() if c == blank
      $scope.playing = 0
      editExcerpt()
      true

    $scope.selectAll = (event, c) ->
      ruler.selection = range = c.segment
      editExcerpt()
      if range && isFinite(range.l) && !range.contains(ruler.position)
        seekOffset(range.l)
      event.stopPropagation()

    $scope.select = (event, c) ->
      if !c || $scope.current == c
        seekPosition event.clientX
      else
        select(c)
      return

    $scope.dragSelection = (down, up, c) ->
      return false if c && $scope.current != c

      startPos = down.position ?= positionOffset(down.clientX)
      endPos = positionOffset(up.clientX)
      ruler.selection =
        if startPos < endPos
          new Segment(startPos, endPos)
        else if startPos > endPos
          new Segment(endPos, startPos)
        else if startPos = endPos
          new Segment(startPos)
      editExcerpt() if up.type != 'mousemove'
      return

    removed = (track) ->
      return if track.asset || track.file || track == blank
      select() if track == $scope.current
      $scope.tracks.remove(track)
      return

    addBlank = () ->
      $scope.tracks.push(blank = new Track())
      return

    class Track extends Store
      constructor: (asset) ->
        super slot, asset
        @excerpts = []
        return

      type: 'asset'

      setAsset: (asset) ->
        super asset
        return unless asset
        updateRange(@segment = new Segment(asset.segment))
        select(this) if `asset.id == target.asset`
        return

      fillData: ->
        super()
        if !@asset
          @data.position = if ruler.range.uBounded then ruler.range.u else 0

      Object.defineProperty @prototype, 'id',
        get: -> @asset?.id

      remove: ->
        r = super()
        return removed this unless r?.then
        r.then (done) =>
          removed this if done
          return
        return

      save: ->
        shift = @asset?.segment.l
        super().then (done) =>
          return unless done
          delete @dirty
          $scope.form.edit.$setPristine() if this == $scope.current
          shift -= @asset.segment.l
          if shift
            for e in @excerpts
              e.segment.l -= shift
              e.segment.u -= shift
          sortTracks()
          return

      upload: (file) ->
        addBlank() if this == blank
        super(file).then (done) =>
          return removed this unless done
          ### jshint ignore:start ###
          @data.name ||= file.file.name
          ### jshint ignore:end ###
          return
        return

      dragMove: (event) ->
        pos = positionOffset(event.clientX)
        return unless pos?
        @segment.u = pos + @segment.length
        @segment.l = pos
        if event.type != 'mousemove'
          @data.position = Math.floor(pos)
          $scope.form.edit.$setDirty()
        return

      editExcerpt: () ->
        @excerpt = undefined
        seg = ruler.selection
        return if !@asset || !seg || (@segment.full && !seg.full) || !@segment.overlaps(seg) || !@asset.checkPermission(constants.permission.EDIT)
        excerpt = @excerpts.find((e) -> seg.overlaps(e.segment))
        @excerpt =
          if !excerpt
            target: @asset.inSegment(seg)
            on: false
            classification: '0'
          else if excerpt.segment.equals(seg)
            target: excerpt
            on: true
            classification: excerpt.excerpt+''
          else
            null
        return

      saveExcerpt: () ->
        messages.clear(this)
        @excerpt.target.setExcerpt(if @excerpt.on then @excerpt.classification else null)
          .then (excerpt) =>
              @excerpts.remove(excerpt)
              @excerpts.push(excerpt) if 'excerpt' of excerpt
              @form.excerpt.$setPristine()
            , (res) =>
              messages.addError
                type: 'red'
                body: constants.message('asset.update.error', @name)
                report: res
                owner: this

      canRestore: () ->
        Store.removedAsset if editing && this == blank && Store.removedAsset?.volume.id == slot.volume.id

      restore: () ->
        Store.restore(slot).then (a) =>
          @setAsset(a)
          addBlank()
          return

    editExcerpt = ->
      $scope.current.editExcerpt() if $scope.current?.excerpts
      return

    $scope.fileAdded = (file) ->
      $flow = file.flowObj
      (!$scope.current?.file && $scope.current || blank).upload(file) if editing
      return

    $scope.fileSuccess = Store.fileSuccess
    $scope.fileProgress = Store.fileProgress

    fillExcerpts = ->
      tracks = {}
      for t in $scope.tracks when t.asset
        tracks[t.asset.id] = t
      for e in slot.excerpts
        t = tracks[e.id]
        t.excerpts.push(e) if t
      return

    videoEvents =
      pause: ->
        $scope.playing = 0
        return
      playing: ->
        $scope.playing = 1
        return
      ratechange: ->
        $scope.playing = video[0].playbackRate
        return
      timeupdate: ->
        if $scope.current?.asset && isFinite($scope.current.asset.segment.l)
          ruler.position = $scope.current.asset.segment.l + 1000*video[0].currentTime
          if ruler.selection.uBounded && ruler.position >= ruler.selection.u
            video[0].pause()
            seekOffset(ruler.selection.l) if ruler.selection.lBounded
        return
      ended: ->
        $scope.playing = 0
        # look for something else to play?
        return

    for ev, fn of videoEvents
      videoEvents[ev] = $scope.$lift(fn)

    @deregisterVideo = (v) ->
      return unless video == v
      video = undefined
      v.off(videoEvents)
      return

    @registerVideo = (v) ->
      this.deregisterVideo video if video
      video = v
      seekOffset(ruler.position)
      v.on(videoEvents)
      return

    class Record
      constructor: (r) ->
        @rec = r
        @record = r.record || slot.volume.records[r.id]
        for f in ['age'] when f of r
          @[f] = r[f]
        updateRange(@segment = new Segment(r.segment))
        if editing
          @fillData()
        return

      type: 'record'

      fillData: ->
        @data =
          measures: angular.extend({}, @record.measures)
          add: ''
        return

      Object.defineProperty @prototype, 'id',
        get: -> @rec.id

      remove: ->
        messages.clear(this)
        slot.removeRecord(@rec, @segment).then (r) =>
            return unless r
            records.remove(this)
            select() if $scope.current == this
            placeRecords()
            return
          , (res) ->
            messages.addError
              type: 'red'
              body: 'Unable to remove'
              report: res
              owner: this
            return

      ### jshint ignore:start #### fixed in jshint 2.5.7
      metrics: ->
        ident = constants.category[@record.category]?.ident || [constants.metricName.ident.id]
        (constants.metric[m] for m of @record.measures when !(+m in ident)).sort(byId)

      addMetric = {id:'',name:'Add new value...'}
      addOptions: ->
        metrics = (metric for m, metric of constants.metric when !(m of @data.measures)).sort(byId)
        metrics.unshift addMetric
        metrics
      ### jshint ignore:end ###

      add: ->
        @data.measures[@data.add] = '' if @data.add
        @data.add = ''
        return

      save: ->
        messages.clear(this)
        saves = []
        if @form.measures.$dirty
          saves.push @record.save({measures:@data.measures}).then () =>
            @form.measures.$setPristine()
            return
        if @form.position.$dirty
          saves.push slot.moveRecord(@rec, @rec.segment, @segment).then (r) =>
            @form.position.$setPristine()
            return unless r # nothing happened
            updateRange(@segment = new Segment(r.segment))
            if @segment.empty
              records.remove(this)
              select() if this == $scope.current
            placeRecords()
            return
        $q.all(saves).then =>
            @fillData()
            delete @dirty
            $scope.form.edit.$setPristine() if this == $scope.current
            return
          , (res) =>
            messages.addError
              type: 'red'
              body: 'Error saving'
              report: res
              owner: this
            return

      dragLeft: (event) ->
        pos = positionOffset(event.clientX)
        @segment.l = pos ? -Infinity
        if event.type != 'mousemove'
          @form.position.$setDirty()
        return

      dragRight: (event) ->
        pos = positionOffset(event.clientX)
        @segment.u = pos ? Infinity
        if event.type != 'mousemove'
          @form.position.$setDirty()
        return

    placeRecords = () ->
      records.sort (a, b) ->
        a.record.category - b.record.category || a.record.id - b.record.id
      t = []
      overlaps = (rr) -> rr.record.id != r.record.id && s.overlaps(rr.segment)
      for r in records
        s = r.segment
        for o, i in t
          break unless o[0].record.category != r.record.category || o.some(overlaps)
        t[i] = [] unless i of t
        t[i].push(r)
        select(r) if `r.id == target.record`
      for r in t
        r.sort byPosition
      $scope.records = t
      return

    $scope.positionBackgroundStyle = (l, i) ->
      $scope.positionStyle(new Segment(l[i].segment.l, if i+1 of l then l[i+1].segment.l else Infinity))

    class Consent
      constructor: (c) ->
        if typeof c == 'object'
          @consent = c.consent
          @segment = Segment.make(c.segment)
        else
          @consent = c
          @segment = Segment.full
        return

      type: 'consent'

      classes: ->
        cn = constants.consent[@consent]
        cls = [cn, 'hint-consent-' + cn]
        cls.push('slot-consent-select') if $scope.current == this
        cls

    class TagName
      constructor: (name) ->
        @id = name
        return

      vote: (vote) ->
        tag = this
        slot.setTag(@id, vote, editing).then (data) ->
            unless tag instanceof Tag
              tag = $scope.tags.find (t) -> t.id == data.id
              unless tag
                tag = new Tag(data)
                tag.active = true
                $scope.tags.push(tag)
            tag.fillData(data)
            $scope.tags.remove(tag) unless tag.weight
            return
          , (res) ->
            messages.addError
              body: constants.message('tags.vote.error', {sce: $sce.HTML}, name)
              report: res
              owner: $scope
            return

    $scope.vote = (name, vote) ->
      new TagName(name).vote(vote)
      return

    class Tag extends TagName
      constructor: (t) ->
        @id = t.id
        @active = false
        @fillData(t)

      fillData: (t) ->
        @weight = t.weight
        @coverage = (Segment.make(s) for s in t.coverage) if t.coverage?.length
        @vote     = (Segment.make(s) for s in t.vote)     if t.vote?.length
        @keyword  = (Segment.make(s) for s in t.keyword)  if t.keyword?.length
        return

      toggle: ->
        @active = !@active

    # implicitly initialize from slot.segment
    updateRange(Segment.full)

    ### jshint ignore:start #### fixed in jshint 2.5.7
    $scope.tracks = (new Track(asset) for assetId, asset of slot.assets)
    ### jshint ignore:end ###
    addBlank() if editing
    sortTracks()
    fillExcerpts()

    records = slot.records.map((r) -> new Record(r))
    placeRecords()

    $scope.consents =
      if Array.isArray(consents = slot.consents)
        consents.map((c) -> new Consent(c))
      else if (consents)
        [new Consent(consents)]
      else
        []

    $scope.tags = []
    ### jshint ignore:start #### fixed in jshint 2.5.7
    # $scope.tags = (new Tag(tag) for tag of slot.tags)
    ### jshint ignore:end ###

    $scope.playing = 0
    editExcerpt()

    if editing
      done = $scope.$on '$locationChangeStart', (event, url) ->
        return if url.includes(slot.editRoute())
        if $flow
          uploading = $flow.isUploading()
          $flow.pause()
        if stayDirty(uploading)
          $flow.resume() if uploading
          display.cancelRouteChange(event)
        else
          done()
        return

    $scope.$on '$destroy', ->
      $flow?.cancel()
      return

    return
])

describe "ElBorrachoStatsController", ->
  describe "constructor", ->
    it should load the store to @Store
    it should set the queue on @queue
    it should set the interval to default value
    it should set the interval to specified value
    it should create a Store at @store
    it should create the storecache at @stores

  describe "listen", ->
    it should lock the store for queue
    it should bind events to queue
    it should start polling

  describe "poll", ->
    it should set the poller for clearing
    it should call update every interval

  describe "stop", ->
    it should clear the poller
    it should unbind events
    it should unlock the store

  describe "history", ->
    it should callback with error if fetch fails
    it should fetch history
    it should fetch history for a specified start date
    it should fetch history for a specified number of days previous

  describe "total", ->
    it should callback with error if fetch fails
    it should fetch totals

  describe "storeCache", ->
    it should set a store when no store is stored
    it should return a stored store when a store is stored

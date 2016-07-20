errify = require "errify"


class ElBorrachoStatsController
  constructor: ({namespace, @queue, @interval, expire}) ->
    @Store      = require "./models/stats"
    redis       = @queue.client
    queuename   = @queue.name
    @interval or= 5 * 1000
    @store      = new @Store {redis, namespace, queuename, expire}
    @stores     = {}

    @storeCache queuename

  listen: =>
    await @store.lock defer()

    @queue.on "completed", @store.incrementCompleted
    @queue.on "failed",    @store.incrementFailed

    @poll()

  poll: =>
    @_poller = setInterval @store.update, @interval

  stop: (callback) =>
    if @_poller
      clearInterval @_poller
      delete @_poller
    @queue.removeListener "completed", @store.incrementCompleted
    @queue.removeListener "failed",    @store.incrementFailed

    @store.unlock callback

  # GET  "/stats/history"
  history: (req, res, next) =>
    ideally = errify next
    {start_date, days_previous} = req.query

    await @store.fetchHistoryForAll start_date, days_previous, ideally defer stats
    res.json stats

  # GET  "/stats"
  total: (req, res, next) =>
    ideally = errify next

    await @store.fetchForAll ideally defer total
    res.json total


  # GET  "/:queue/stats/history"
  queueHistory: (req, res, next) =>
    ideally = errify next
    {queue} = req.param
    {start_date, days_previous} = req.query

    store = @storeCache queue

    await store.fetchHistoryForQueue queue, start_date, days_previous, ideally defer stats
    res.json stats

  # GET  "/:queue/stats"
  queueTotal: (req, res, next) =>
    ideally = errify next
    {queue} = req.param

    store = @storeCache queue

    await store.fetchForQueue queue, ideally defer total
    res.json total

  storeCache: (queuename) ->
    {redis, namespace} = @store
    @stores[queuename] or= new @Store {redis, namespace, queuename}


module.exports = ElBorrachoStatsController

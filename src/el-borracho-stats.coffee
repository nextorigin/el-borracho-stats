errify = require "errify"


class ElBorrachoStatsController
  constructor: ({@redis, @namespace}) ->
    @Store      = require "./models/stats"
    @stores     = {}
    @store      = new @Store {@redis, @namespace}

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
    @stores[queuename] or= new @Store {@redis, @namespace, queuename}


module.exports = ElBorrachoStatsController

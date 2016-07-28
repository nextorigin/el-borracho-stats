

class ElBorrachoStatsWorker
  constructor: ({namespace, @queue, @interval, expire}) ->
    @Store      = require "../models/stats"
    redis       = @queue.client
    queuename   = @queue.name
    @interval or= 5 * 1000
    @store      = new @Store {redis, namespace, queuename, expire}

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


module.exports = ElBorrachoStatsWorker

SSEriesOfTubes = require "sseries-of-tubes"
Stats          = require "../el-borracho-stats"


class ElBorrachoStatsRouter
  constructor: ({server, redis, namespace, @router}) ->
    @tubes    = new SSEriesOfTubes server
    @stats    = new Stats {redis, namespace}
    @router or= new (require "express").Router

    @bindRoutes()

  bindRoutes: ->
    @router.get "/sse/all",            @tubes.combine "/sse/history", "/sse"
    @router.get "/sse/history",        @tubes.plumb @stats.history, 30, "history"
    @router.get "/sse",                @tubes.plumb @stats.total,    2, "total"
    @router.get "/history",            @stats.history
    @router.get "/",                   @stats.total


module.exports = ElBorrachoStatsRouter

SSEriesOfTubes = require "sseries-of-tubes"
Stats          = require "../el-borracho-stats"


class ElBorrachoStatsRouter
  constructor: ({server, redis, namespace, @router, @mount}) ->
    @tubes    = new SSEriesOfTubes server
    @stats    = new Stats {redis, namespace}
    @router or= new (require "express").Router
    @mount  or= "/stats"

    @bindRoutes()

  bindRoutes: ->
    @router.get "/sse/all",            @tubes.combine "#{@mount}/sse/history", "#{@mount}/sse"
    @router.get "/sse/history",        @tubes.plumb @stats.history, 30, "#{@mount}/sse/history", "history"
    @router.get "/sse",                @tubes.plumb @stats.total,    2, "#{@mount}/sse", "total"
    @router.get "/history",            @stats.history
    @router.get "/",                   @stats.total


module.exports = ElBorrachoStatsRouter

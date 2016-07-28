errify = require "errify"


class ElBorrachoStats
  completed: 0
  failed:    0

  incrementCompleted: => @completed++
  incrementFailed: => @failed++
  clearCompleted: => @completed = 0
  clearFailed: => @failed = 0

  prefixForQueue: (queue) -> "bull:#{@namespace}:#{queue}"

  shortDate: (date) -> (date.toISOString().split "T")[0]

  constructor: ({@redis, @namespace, @queuename, @expire, @overallTotal}) ->
    throw new Error "redis client required" unless @redis

    @namespace     or= "stat"
    @prefix          = @prefixForQueue @queuename
    @statistician    = "#{@prefix}:statistician"
    @expire        or= 60
    @overallTotal   ?= true

  lock: (callback) =>
    ideally = errify (err) -> throw err
    await @redis.exists @statistician, ideally defer key
    throw new Error "key #{@statistician} exists, Stats may already be running for this queue" if key

    await @redis.set @statistician, true, ideally defer()
    await @updateLock ideally defer()
    callback()

  updateLock: (callback) =>
    @redis.EXPIRE @statistician, @expire, callback

  unlock: (callback = ->) =>
    await @redis.del @statistician, defer err
    throw err if err
    callback()

  update: (callback = ->) =>
    ideally = errify (err) -> throw err
    today   = @shortDate new Date
    all     = "bull:#{@namespace}:all"

    await @updateLock ideally defer()
    if @completed
      multi = @redis.multi()
      multi.incrby "#{@prefix}:completed", @completed
      multi.incrby "#{@prefix}:completed:#{today}", @completed
      if @overallTotal
        multi.incrby "#{all}:completed", @completed
        multi.incrby "#{all}:completed:#{today}", @completed
      await multi.exec ideally defer()
      @clearCompleted()

    if @failed
      multi = @redis.multi()
      multi.incrby "#{@prefix}:failed", @failed
      multi.incrby "#{@prefix}:failed:#{today}", @failed
      if @overallTotal
        multi.incrby "#{all}:failed", @failed
        multi.incrby "#{all}:failed:#{today}", @failed
      await multi.exec ideally defer()
      @clearFailed()

    callback()

  fetch: (callback) =>
    @fetchForQueue @queuename, callback

  fetchForAll: (callback) =>
    @fetchForQueue "all", callback

  fetchForQueue: (queue, callback) =>
    ideally = errify callback
    prefix  = @prefixForQueue queue

    await @redis.get "#{prefix}:completed", ideally defer completed
    await @redis.get "#{prefix}:failed", ideally defer failed

    callback null, {completed, failed}

  fetchHistory: (startDate = new Date, daysPrevious = 30, callback) =>
    @fetchHistoryForQueue @queuename, startDate, daysPrevious, callback

  fetchHistoryForAll: (startDate = new Date, daysPrevious = 30, callback) =>
    @fetchHistoryForQueue "all", startDate, daysPrevious, callback

  fetchHistoryForQueue: (queue, startDate = new Date, daysPrevious = 30, callback) =>
    ideally = errify callback

    await @fetchStatForQueue queue, "completed", startDate, daysPrevious, ideally defer completed
    await @fetchStatForQueue queue, "failed", startDate, daysPrevious, ideally defer failed

    callback null, {completed, failed}

  fetchStat: (type, startDate = new Date, daysPrevious = 30, callback) =>
    @fetchStatForQueue @queuename, type, startDate, daysPrevious, callback

  fetchStatForAll: (type, startDate = new Date, daysPrevious = 30, callback) =>
    @fetchStatForQueue "all", type, startDate, daysPrevious, callback

  fetchStatForQueue: (queue, type, startDate = new Date, daysPrevious = 30, callback) =>
    ideally = errify callback
    prefix  = @prefixForQueue queue

    startDate = new Date startDate unless startDate instanceof Date
    statHash  = {}
    dates     = []
    keys      = for i in [0..daysPrevious-1]
      date = new Date startDate
      date.setDate date.getDate() - i
      datestr = @shortDate date
      dates.push datestr
      "#{prefix}:#{type}:#{datestr}"

    await @redis.mget keys, ideally defer stats
    stats = ({type, date: dates[i], value: stat} for stat, i in stats)

    callback null, stats


module.exports = ElBorrachoStats

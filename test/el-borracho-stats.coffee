ElBorrachoStats           = require "../src/models/stats"
ElBorrachoStatsController = require "../src/el-borracho-stats"

redis      = require "redis"
errify     = require "errify"
mocha      = require "mocha"
{expect}   = require "chai"
{spy}      = require "sinon"
spy.on     = spy


delay = (timeout, fn) -> setTimeout fn, timeout


describe "ElBorrachoStatsController", ->
  name      = "tacos"
  interval  = 0.2 * 1000
  client    = null
  instance  = null

  beforeEach ->
    client    = redis.createClient()
    instance  = new ElBorrachoStatsController {redis: client}

  afterEach ->
    client   = null
    instance = null

  describe "##constructor", ->
    it "should load the store to @Store", ->
      expect(instance.Store.name).to.equal "ElBorrachoStats"

    it "should pass namespace to @store", ->
      namespace = "universe"
      instance  = new ElBorrachoStatsController {redis: client, namespace}

      expect(instance.store.namespace).to.equal namespace

    it "should create a Store at @store", ->
      expect(instance.store).to.be.an.instanceof instance.Store

  describe "##history", ->
    req = {query: {}}
    res = {}

    today = ElBorrachoStats::shortDate new Date
    statStates = [
      "completed"
      "failed"
    ]

    statKeys = []
    for state in statStates
      statKeys = statKeys.concat [
        "bull:stat:tacos:#{state}"
        "bull:stat:tacos:#{state}:#{today}"
        "bull:stat:all:#{state}"
        "bull:stat:all:#{state}:#{today}"
      ]

    beforeEach (done) ->
      multi = client.multi()
      multi.set key, i * 2 for key, i in statKeys
      multi.exec done

    afterEach (done) ->
      ideally = errify done
      cleanup = []
      for queue in ["tacos", "all"]
        for state in statStates
          await client.keys "bull:stat:#{queue}:#{state}*", ideally defer keys
          cleanup = cleanup.concat keys

      multi = client.multi()
      multi.del key for key in cleanup
      multi.exec done

    it "should callback with error if fetch fails", (done) ->
      instance.store.redis.mget = (_, callback) -> callback new Error "fake"

      await instance.history req, res, defer err
      expect(err).to.be.instanceof Error
      expect(err.toString()).to.match /fake/
      done()

    it "should fetch overall history", (done) ->
      await
        _res = json: defer {completed, failed}
        instance.history req, _res, done

      expect(completed).to.exist
      expect(failed).to.exist
      done()

    it "should fetch overall history for a specified start date", (done) ->
      ideally = errify done

      date = new Date
      date.setDate date.getDate() - 2
      datestr = ElBorrachoStats::shortDate date

      for state, i in statStates
        await client.set "bull:stat:all:#{state}:#{datestr}", i + 1, ideally defer()

      await
        _req = query: start_date: datestr
        _res = json: defer {completed, failed}
        instance.history _req, _res, done

      expect(completed).to.exist
      expect(Number completed[0].value).to.equal 1
      expect(failed).to.exist
      expect(Number failed[0].value).to.equal 2
      done()

    it "should fetch overall history for a specified number of days previous", (done) ->
      ideally = errify done

      makeDate = (past) ->
        date = new Date
        date.setDate date.getDate() - past
        ElBorrachoStats::shortDate date

      from  = 3
      start = makeDate from
      days  = 4

      for i in [0..days-1]
        for state in statStates
          datestr = makeDate from + i
          await client.set "bull:stat:all:#{state}:#{datestr}", i + 1, ideally defer()

      await
        _req = query: start_date: start, days_previous: days
        _res = json: defer {completed, failed}
        instance.history _req, _res, done

      expect(completed).to.exist
      expect(completed).to.have.length 4
      expect(Number completed[1].value).to.equal 2
      expect(failed).to.exist
      expect(failed).to.have.length 4
      expect(Number failed[3].value).to.equal 4
      done()

  describe "##total", ->
    req = {query: {}}
    res = {}

    today = ElBorrachoStats::shortDate new Date
    statStates = [
      "completed"
      "failed"
    ]

    statKeys = []
    for state in statStates
      statKeys = statKeys.concat [
        "bull:stat:tacos:#{state}"
        "bull:stat:tacos:#{state}:#{today}"
        "bull:stat:all:#{state}"
        "bull:stat:all:#{state}:#{today}"
      ]

    beforeEach (done) ->
      multi = client.multi()
      multi.set key, i * 2 for key, i in statKeys
      multi.exec done

    afterEach (done) ->
      ideally = errify done
      cleanup = []
      for queue in ["tacos", "all"]
        for state in statStates
          await client.keys "bull:stat:#{queue}:#{state}*", ideally defer keys
          cleanup = cleanup.concat keys

      multi = client.multi()
      multi.del key for key in cleanup
      multi.exec done

    it "should callback with error if fetch fails", (done) ->
      instance.store.redis.get = (_, callback) -> callback new Error "fake"

      await instance.total req, res, defer err
      expect(err).to.be.instanceof Error
      expect(err.toString()).to.match /fake/
      done()

    it "should fetch overall totals", (done) ->
      ideally = errify done

      await
        _res = json: defer {completed, failed}
        instance.total req, _res, done

      expect(completed).to.exist
      expect(Number completed).to.equal 4
      expect(failed).to.exist
      expect(Number failed).to.equal 12
      done()

  describe "##queueHistory", ->
    req = {param: {queue: name}, query: {}}
    res = {}

    today = ElBorrachoStats::shortDate new Date
    statStates = [
      "completed"
      "failed"
    ]

    statKeys = []
    for state in statStates
      statKeys = statKeys.concat [
        "bull:stat:tacos:#{state}"
        "bull:stat:tacos:#{state}:#{today}"
        "bull:stat:all:#{state}"
        "bull:stat:all:#{state}:#{today}"
      ]

    beforeEach (done) ->
      multi = client.multi()
      multi.set key, i * 2 for key, i in statKeys
      multi.exec done

    afterEach (done) ->
      ideally = errify done
      cleanup = []
      for queue in ["tacos", "all"]
        for state in statStates
          await client.keys "bull:stat:#{queue}:#{state}*", ideally defer keys
          cleanup = cleanup.concat keys

      multi = client.multi()
      multi.del key for key in cleanup
      multi.exec done

    it "should callback with error if fetch fails", (done) ->
      instance.store.redis.mget = (_, callback) -> callback new Error "fake"

      await instance.queueHistory req, res, defer err
      expect(err).to.be.instanceof Error
      expect(err.toString()).to.match /fake/
      done()

    it "should fetch history for a specified queue", (done) ->
      await
        _res = json: defer {completed, failed}
        instance.queueHistory req, _res, done

      expect(completed).to.exist
      expect(failed).to.exist
      done()

    it "should fetch history for a specified queue and start date", (done) ->
      ideally = errify done

      queuename = "burgers"
      date = new Date
      date.setDate date.getDate() - 2
      datestr = ElBorrachoStats::shortDate date

      for state, i in statStates
        await client.set "bull:stat:#{queuename}:#{state}:#{datestr}", i + 1, ideally defer()

      await
        _req = param: {queue: queuename}, query: start_date: datestr
        _res = json: defer {completed, failed}
        instance.queueHistory _req, _res, done

      expect(completed).to.exist
      expect(Number completed[0].value).to.equal 1
      expect(failed).to.exist
      expect(Number failed[0].value).to.equal 2
      done()

    it "should fetch history for a specified queue and number of days previous", (done) ->
      ideally = errify done

      makeDate = (past) ->
        date = new Date
        date.setDate date.getDate() - past
        ElBorrachoStats::shortDate date

      queuename = "burgers"
      from  = 3
      start = makeDate from
      days  = 4

      for i in [0..days-1]
        for state in statStates
          datestr = makeDate from + i
          await client.set "bull:stat:#{queuename}:#{state}:#{datestr}", i + 1, ideally defer()

      await
        _req = param: {queue: queuename}, query: start_date: start, days_previous: days
        _res = json: defer {completed, failed}
        instance.queueHistory _req, _res, done

      expect(completed).to.exist
      expect(completed).to.have.length 4
      expect(Number completed[1].value).to.equal 2
      expect(failed).to.exist
      expect(failed).to.have.length 4
      expect(Number failed[3].value).to.equal 4
      done()

  describe "##queueTotal", ->
    req = {param: {queue: name}}
    res = {}

    today = ElBorrachoStats::shortDate new Date
    statStates = [
      "completed"
      "failed"
    ]

    statKeys = []
    for state in statStates
      statKeys = statKeys.concat [
        "bull:stat:tacos:#{state}"
        "bull:stat:tacos:#{state}:#{today}"
        "bull:stat:all:#{state}"
        "bull:stat:all:#{state}:#{today}"
      ]

    beforeEach (done) ->
      multi = client.multi()
      multi.set key, i + 2 for key, i in statKeys
      multi.exec done

    afterEach (done) ->
      ideally = errify done
      cleanup = []
      for queue in ["tacos", "all"]
        for state in statStates
          await client.keys "bull:stat:#{queue}:#{state}*", ideally defer keys
          cleanup = cleanup.concat keys

      multi = client.multi()
      multi.del key for key in cleanup
      multi.exec done

    it "should callback with error if fetch fails", (done) ->
      instance.store.redis.get = (_, callback) -> callback new Error "fake"

      await instance.queueTotal req, res, defer err
      expect(err).to.be.instanceof Error
      expect(err.toString()).to.match /fake/
      done()

    it "should fetch totals for a specified queue", (done) ->
      ideally = errify done

      await
        _res = json: defer {completed, failed}
        instance.queueTotal req, _res, done

      expect(completed).to.exist
      expect(Number completed).to.equal 2
      expect(failed).to.exist
      expect(Number failed).to.equal 6
      done()

  describe "##storeCache", ->
    it "should set a store when no store is stored", (done) ->
      names = Object.keys instance.stores
      n     = "burger"
      expect(names).to.have.length 0
      expect(instance.stores[n]).to.not.exist

      instance.storeCache n

      names = Object.keys instance.stores
      expect(names).to.have.length 1
      expect(instance.stores[n]).to.be.an.instanceof ElBorrachoStats
      done()

    it "should return a stored store when a store is stored", (done) ->
      store = instance.storeCache name

      expect(store).to.exist
      expect(store).to.be.an.instanceof ElBorrachoStats
      done()

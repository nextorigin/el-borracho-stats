ElBorrachoStats           = require "../src/models/stats"
ElBorrachoStatsController = require "../src/el-borracho-stats"

redis      = require "redis"
Bull       = require "bull"
errify     = require "errify"
mocha      = require "mocha"
{expect}   = require "chai"
{spy}      = require "sinon"
spy.on     = spy


delay = (timeout, fn) -> setTimeout fn, timeout


describe "ElBorrachoStatsController", ->
  name      = "tacos"
  expire    = 2
  interval  = 0.2 * 1000
  client    = null
  queue     = null
  instance  = null

  beforeEach ->
    client    = redis.createClient()
    createClient = -> client
    queue     = new Bull name, {createClient}
    instance  = new ElBorrachoStatsController {queue, interval}

  afterEach ->
    client   = null
    instance = null
    queue    = null

  describe "##constructor", ->
    it "should load the store to @Store", ->
      expect(instance.Store.name).to.equal "ElBorrachoStats"

    it "should set the queue on @queue", ->
      expect(instance.queue).to.equal queue

    it "should set the interval to default value", ->
      instance = new ElBorrachoStatsController {queue}
      expect(instance.interval).to.equal 5000

    it "should set the interval to specified value", ->
      instance = new ElBorrachoStatsController {queue, interval: 6000}

      expect(instance.interval).to.equal 6000

    it "should pass namespace and expire to @store", ->
      namespace = "universe"
      expire    = 7
      instance  = new ElBorrachoStatsController {queue, namespace, expire}

      expect(instance.store.expire).to.equal expire
      expect(instance.store.namespace).to.equal namespace

    it "should create a Store at @store", ->
      expect(instance.store).to.be.an.instanceof instance.Store

    it "should create the storecache at @stores", ->
      expect(instance.stores).to.be.an "object"

  describe "##listen", ->
    # afterEach (done) ->
    arbitraryWaitTime = 50

    it "should lock the store for queue", (done) ->
      doubleoh = spy.on instance.store, "lock"

      instance.listen()

      await delay arbitraryWaitTime, defer()
      expect(doubleoh.called).to.be.true
      instance.stop done

    it "should bind events to queue", (done) ->
      blackhat = spy.on instance.store, "incrementCompleted"
      whitehat = spy.on instance.store, "incrementFailed"

      instance.listen()
      await delay arbitraryWaitTime, defer()
      queue.emit "completed"
      queue.emit "failed"

      expect(blackhat.called).to.be.true
      expect(whitehat.called).to.be.true
      instance.stop done

    it "should start polling", (done) ->
      doubleoh = spy.on instance, "poll"

      instance.listen()
      await delay arbitraryWaitTime, defer()

      expect(doubleoh.called).to.be.true
      instance.stop done

  describe "##poll", ->
    it "should set the poller for clearing", (done) ->
      {interval} = instance

      instance.poll()
      await delay interval * 1.5, defer()

      expect(instance._poller).to.exist
      instance.stop done

    it "should call update every interval", (done) ->
      doubleoh = spy.on instance.store, "update"

      instance.listen()
      await delay interval * 2.5, defer()

      expect(doubleoh.calledTwice).to.be.true
      instance.stop done

  describe "##stop", ->
    arbitraryWaitTime = 50

    it "should clear the poller", (done) ->
      ideally = errify done

      instance.poll()
      await delay interval * 1.5, defer()

      await instance.stop ideally defer()
      expect(instance._poller).to.not.exist
      done()

    it "should unbind events", (done) ->
      ideally = errify done

      blackhat = spy.on instance.store, "incrementCompleted"
      whitehat = spy.on instance.store, "incrementFailed"

      instance.listen()
      await delay arbitraryWaitTime, defer()

      await instance.stop ideally defer()
      queue.emit "completed"
      queue.emit "failed"

      expect(blackhat.called).to.be.false
      expect(whitehat.called).to.be.false
      done()

    it "should unlock the store", (done) ->
      ideally = errify done

      doubleoh = spy.on instance.store, "unlock"

      instance.listen()
      await delay arbitraryWaitTime, defer()

      await instance.stop ideally defer()
      expect(doubleoh.called).to.be.true
      done()

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
      expect(names).to.have.length 1
      expect(instance.stores[n]).to.not.exist

      instance.storeCache n

      names = Object.keys instance.stores
      expect(names).to.have.length 2
      expect(instance.stores[n]).to.be.an.instanceof ElBorrachoStats
      done()

    it "should return a stored store when a store is stored", (done) ->
      store = instance.storeCache name

      expect(store).to.exist
      expect(store).to.be.an.instanceof ElBorrachoStats
      done()

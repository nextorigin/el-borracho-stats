ElBorrachoStats = require "../src/models/stats"

redis      = require "redis"
errify     = require "errify"
mocha      = require "mocha"
{expect}   = require "chai"
{spy}      = require "sinon"
spy.on     = spy


dontCatch = ->
  listeners = process.listeners "uncaughtException"
  process.removeAllListeners "uncaughtException"
  restore: -> process.on "uncaughtException", listener for listener in listeners


describe "ElBorrachoStats", ->
  queuename = "tacos"
  expire    = 2
  client    = null
  instance  = null

  beforeEach ->
    client   = redis.createClient()
    instance = new ElBorrachoStats {redis: client, queuename, expire}

  afterEach ->
    client = null
    instance = null

  describe "##incrementCompleted", ->
    it "should increment completed", ->
      count = instance.completed
      instance.incrementCompleted()
      expect(instance.completed).to.equal count + 1

  describe "##incrementFailed", ->
    it "should increment failed", ->
      count = instance.failed
      instance.incrementFailed()
      expect(instance.failed).to.equal count + 1

  describe "##clearCompleted", ->
    it "should clear completed", ->
      instance.completed = 2
      instance.clearCompleted()
      expect(instance.completed).to.equal 0

  describe "##clearFailed", ->
    it "should clear failed", ->
      instance.failed = 2
      instance.clearFailed()
      expect(instance.failed).to.equal 0

  describe "##constructor", ->
    it "should throw an error unless redisClient is passed in", ->
      newInstance = -> new ElBorrachoStats
      expect(newInstance).to.throw Error

    it "should initialize namespace to default value", ->
      expect(instance.namespace).to.equal "stat"

    it "should initialize namespace to specified value", ->
      namespace = "universe"
      instance  = new ElBorrachoStats {redis: client, namespace}
      expect(instance.namespace).to.equal namespace

    it "should initialize queuename to specified value", ->
      instance  = new ElBorrachoStats {redis: client, queuename}
      expect(instance.queuename).to.equal queuename

    it "should initialize the prefix", ->
      queuename = "tacos"
      instance  = new ElBorrachoStats {redis: client, queuename}
      expect(instance.prefix).to.equal instance.prefixForQueue queuename

    it "should initialize the statistician", ->
      expect(instance.statistician).to.equal "#{instance.prefix}:statistician"

    it "should initialize expire to default value", ->
      instance  = new ElBorrachoStats {redis: client, queuename}
      expect(instance.expire).to.equal 60

    it "should initialize expire to specified value", ->
      expire    = 100
      instance  = new ElBorrachoStats {redis: client, expire}
      expect(instance.expire).to.equal expire

    it "should initialize overallTotal to default value", ->
      expect(instance.overallTotal).to.be.true

    it "should initialize overallTotal to specified value", ->
      overallTotal = false
      instance  = new ElBorrachoStats {redis: client, overallTotal}
      expect(instance.overallTotal).to.equal overallTotal

  describe "lock methods", ->
    _runTest = null

    before ->
      # https://github.com/mochajs/mocha/issues/1985
      _runTest = mocha.Runner.prototype.runTest
      mocha.Runner.prototype.runTest = ->
        @allowUncaught = true
        _runTest.apply this, arguments

    after ->
      mocha.Runner.prototype.runTest = _runTest

    beforeEach (done) ->
      instance.lock done

    afterEach (done) ->
      instance.unlock done

    describe "##lock", ->
      it "should set the lock in redis", (done) ->
        ideally = errify done

        await client.keys instance.statistician, ideally defer lock
        expect(lock?[0]).to.exist
        done()

      it "should set the lock to expire in redis", (done) ->
        ideally = errify done

        await client.ttl instance.statistician, ideally defer ttl
        expect(ttl).to.equal expire
        done()

      it "should throw an error if already locked", (done) ->
        process.removeAllListeners "uncaughtException"

        await
          process.once "uncaughtException", defer err
          instance.lock()

        expect(err).to.be.an.instanceof Error
        expect(err.toString()).to.match /exists/
        done()

    describe "##updateLock", ->
      it "should update the lock TTL", (done) ->
        ideally = errify done

        instance.expire = 60
        await instance.updateLock ideally defer()

        await client.ttl instance.statistician, ideally defer ttl
        expect(ttl).to.equal instance.expire
        done()

    describe "##unlock", ->
      it "should throw an error if error in lock removal", (done) ->
        handler = dontCatch()

        _del = client.del
        client.del = (_, callback) -> callback new Error "fake"

        expectation = (err) ->
          expect(err).to.be.an.instanceof Error
          expect(err.toString()).to.match /fake/

          client.del = _del
          handler.restore()
          done()

        process.once "uncaughtException", expectation
        instance.unlock()

      it "should remove the lock", (done) ->
        ideally = errify done

        await instance.unlock ideally defer()

        await client.keys instance.statistician, ideally defer result
        expect(result).to.be.empty
        done()

  describe "##update", ->
    statStates = [
      "completed"
      "failed"
    ]
    for state in statStates then do (state) ->
      today = ElBorrachoStats::shortDate new Date
      statKeys = [
        "bull:stat:tacos:#{state}"
        "bull:stat:tacos:#{state}:#{today}"
        "bull:stat:all:#{state}"
        "bull:stat:all:#{state}:#{today}"
      ]
      beforeEach (done) ->
        multi = client.multi()
        multi.del key for key in statKeys
        multi.exec done

      it "should throw an error if lock update failed", (done) ->
        handler = dontCatch()
        _EXPIRE = client.EXPIRE
        client.EXPIRE = (_, __, callback) -> callback new Error "fake"

        expectation = (err) ->
          expect(err).to.be.an.instanceof Error
          expect(err.toString()).to.match /fake/

          client.EXPIRE = _EXPIRE

          handler.restore()
          done()

        process.once "uncaughtException", expectation
        instance.update()

      it "should not increase totals for #{state} if empty", (done) ->
        ideally = errify done
        {prefix} = instance

        await instance.update ideally defer()

        await client.keys "#{prefix}:#{state}*", ideally defer keys
        expect(keys).to.be.empty
        done()

      it "should increase alltime queue totals for #{state}", (done) ->
        ideally = errify done
        {prefix} = instance

        expected = instance[state] = 2
        await instance.update ideally defer()

        await client.get "#{prefix}:#{state}", ideally defer result
        expect(Number result).to.equal expected
        done()

      it "should increase todays queue totals for #{state}", (done) ->
        ideally = errify done
        {prefix} = instance

        expected = instance[state] = 4
        await instance.update ideally defer()

        await client.get "#{prefix}:#{state}:#{today}", ideally defer result
        expect(Number result).to.equal expected
        done()

      it "should not increase alltime totals for #{state} if overallTotal option is false", (done) ->
        ideally = errify done
        instance = new ElBorrachoStats {redis: client, queuename, expire, overallTotal: false}
        prefix   = "bull:#{instance.namespace}:all"

        instance[state] = 4
        await instance.update ideally defer()

        await client.get "#{prefix}:#{state}", ideally defer result
        expect(Number result).to.equal 0
        done()

      it "should increase alltime overall totals for #{state}", (done) ->
        ideally = errify done
        prefix  = "bull:#{instance.namespace}:all"

        expected = instance[state] = 4
        await instance.update ideally defer()

        await client.get "#{prefix}:#{state}", ideally defer result
        expect(Number result).to.equal expected
        done()

      it "should increase todays overall totals for #{state}", (done) ->
        ideally = errify done
        prefix  = "bull:#{instance.namespace}:all"

        expected = instance[state] = 6
        await instance.update ideally defer()

        await client.get "#{prefix}:#{state}:#{today}", ideally defer result
        expect(Number result).to.equal expected
        done()

      it "should throw an error if atomic #{state} update failed", (done) ->
        handler = dontCatch()
        _multi = client.multi.bind client
        client.multi = ->
          m = _multi()
          m.exec = (callback) -> callback new Error "fake"
          m

        prefix   = instance.prefix = " "
        expected = instance[state] = 2

        expectation = (err) ->
          expect(err).to.be.an.instanceof Error
          expect(err.toString()).to.match /fake/

          client.multi = _multi
          handler.restore()
          done()

        process.once "uncaughtException", expectation
        instance.update()


  describe "fetch methods", ->
    today = ElBorrachoStats::shortDate new Date

    beforeEach (done) ->
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
      multi = client.multi()
      multi.del key for key in statKeys
      multi.exec done

    describe "##fetch", ->
      it "should callback with totals for queue", (done) ->
        ideally = errify done

        expectedCompleted = instance.completed = 6
        expectedFailed    = instance.failed = 3
        await instance.update ideally defer()

        await instance.fetch ideally defer {completed, failed}
        expect(Number completed).to.equal expectedCompleted
        expect(Number failed).to.equal expectedFailed
        done()

    describe "##fetchForAll", ->
      it "should callback with overall totals", (done) ->
        ideally = errify done

        expectedCompleted = instance.completed = 8
        expectedFailed    = instance.failed = 4
        await instance.update ideally defer()

        await instance.fetchForAll ideally defer {completed, failed}
        expect(Number completed).to.equal expectedCompleted
        expect(Number failed).to.equal expectedFailed
        done()

    describe "##fetchHistory", ->
      it "should callback with history for queue", (done) ->
        ideally = errify done

        expectedCompleted = instance.completed = 6
        expectedFailed    = instance.failed = 3
        await instance.update ideally defer()

        await instance.fetchHistory null, null, ideally defer {completed, failed}
        completedToday = do -> return stat for stat in completed when stat.date is today
        failedToday = do -> return stat for stat in failed when stat.date is today
        expect(Number completedToday.value).to.equal expectedCompleted
        expect(Number failedToday.value).to.equal expectedFailed
        done()

  describe "shortDate", ->
    it "should return a date in YYYY-MM-DD format", (done) ->
      datestr = "2002-02-02"
      date = instance.shortDate new Date datestr

      expect(date).to.equal datestr
      done()

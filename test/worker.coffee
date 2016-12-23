ElBorrachoStats           = require "../src/models/stats"
ElBorrachoStatsWorker     = require "../src/controllers/worker"

redis      = require "ioredis"
Bull       = require "bull"
errify     = require "errify"
mocha      = require "mocha"
{expect}   = require "chai"
{spy}      = require "sinon"
spy.on     = spy


delay = (timeout, fn) -> setTimeout fn, timeout


describe "ElBorrachoStatsWorker", ->
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
    instance  = new ElBorrachoStatsWorker {queue, interval, expire}

  afterEach ->
    client   = null
    instance = null
    queue    = null

  describe "##constructor", ->
    it "should load the store to @Store", (done) ->
      expect(instance.Store.name).to.equal "ElBorrachoStats"
      done()
    it "should set the queue on @queue", (done) ->
      expect(instance.queue).to.equal queue
      done()

    it "should set the interval to default value", (done) ->
      instance = new ElBorrachoStatsWorker {queue}
      expect(instance.interval).to.equal 5000
      done()

    it "should set the interval to specified value", (done) ->
      instance = new ElBorrachoStatsWorker {queue, interval: 6000}

      expect(instance.interval).to.equal 6000
      done()

    it "should pass namespace and expire to @store", (done) ->
      namespace = "universe"
      _expire   = 7
      instance  = new ElBorrachoStatsWorker {queue, namespace, expire: _expire}

      expect(instance.store.expire).to.equal _expire
      expect(instance.store.namespace).to.equal namespace
      done()

    it "should create a Store at @store", (done) ->
      expect(instance.store).to.be.an.instanceof instance.Store
      done()

  describe "##listen", ->
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


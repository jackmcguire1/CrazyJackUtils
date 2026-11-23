local wow = require("spec.helpers.wow")

-- Names of the callbacks a wow.module() has received, in order.
local function calls(module)
  local names = {}
  for i, call in ipairs(module.calls) do names[i] = call[1] end
  return names
end

describe("saved variables", function()
  it("fills in defaults", function()
    local w = wow.load()
    assert.same(w.ns.DEFAULTS, w.db)
    assert.is_not.equal(w.ns.DEFAULTS.modules, w.db.modules)
  end)

  it("keeps existing settings", function()
    local w = wow.load({ db = { minimapHide = true, minimapAngle = 90 } })
    assert.is_true(w.db.minimapHide)
    assert.equal(90, w.db.minimapAngle)
    assert.is_true(w.db.enabled)
  end)

  it("ignores other addons loading", function()
    local w = wow.load()
    w.db.minimapAngle = 10
    w:Fire("ADDON_LOADED", "SomethingElse")
    assert.equal(10, w.db.minimapAngle)
  end)
end)

describe("modules", function()
  it("start enabled, with their defaults filled in", function()
    local m = wow.module("thing", { defaults = { colour = "red", nested = { depth = 2 } } })
    local w = wow.load({ modules = { m } })
    assert.same({ enabled = true, colour = "red", nested = { depth = 2 } }, w.db.modules.thing)
    assert.equal(w.db.modules.thing, m.db)
    assert.same({ "OnInit", "OnEnable" }, calls(m))
    assert.is_true(m.active)
  end)

  it("keep their saved settings", function()
    local m = wow.module("thing", { defaults = { colour = "red", size = 3 } })
    wow.load({ modules = { m }, db = { modules = { thing = { enabled = false, colour = "blue" } } } })
    assert.same({ enabled = false, colour = "blue", size = 3 }, m.db)
    assert.same({ "OnInit" }, calls(m))
  end)

  it("can be off by default", function()
    local m = wow.module("thing", { defaults = { enabled = false } })
    wow.load({ modules = { m } })
    assert.is_false(m.active)
    assert.same({ "OnInit" }, calls(m))
  end)

  it("stay off while ForeverUtils is off", function()
    local m = wow.module("thing")
    local w = wow.load({ modules = { m }, db = { enabled = false } })
    assert.same({ "OnInit" }, calls(m))
    w:Slash("on")
    assert.same({ "OnInit", "OnEnable" }, calls(m))
    w:Slash("off")
    assert.same({ "OnInit", "OnEnable", "OnDisable" }, calls(m))
    assert.is_true(m.db.enabled) -- the module's own setting is untouched
  end)

  it("get their events only while enabled", function()
    local m = wow.module("thing")
    local w = wow.load({ modules = { m } })
    w:Fire("SOME_EVENT", "a", 2)
    assert.same({ "SOME_EVENT", "a", 2 }, m.calls[#m.calls])
    w:Slash("thing off")
    local before = #m.calls
    w:Fire("SOME_EVENT")
    assert.equal(before, #m.calls)
  end)

  it("don't get events they didn't ask for", function()
    local a = wow.module("a")
    local b = wow.module("b", { events = {} })
    local w = wow.load({ modules = { a, b } })
    w:Fire("SOME_EVENT")
    assert.same({ "OnInit", "OnEnable", "SOME_EVENT" }, calls(a))
    assert.same({ "OnInit", "OnEnable" }, calls(b))
  end)

  it("work without any callbacks", function()
    local w = wow.load({ modules = { { key = "bare" } } })
    w:Slash("bare off")
    w:Slash("bare on")
    assert.is_true(w.db.modules.bare.enabled)
  end)

  for _, key in ipairs({ "Thing", "two words", "1st", "", "status", "on" }) do
    it(("reject the key %q"):format(key), function()
      assert.has_error(function() wow.load({ modules = { { key = key } } }) end)
    end)
  end

  it("reject a duplicate key", function()
    assert.has_error(function() wow.load({ modules = { { key = "a" }, { key = "a" } } }) end)
  end)

  it("reject registering after login", function()
    local w = wow.load()
    assert.has_error(function() w.ns.RegisterModule({ key = "late" }) end)
  end)
end)

describe("slash commands", function()
  it("/fu opens the options", function()
    local w = wow.load()
    w:Slash("")
    assert.equal(1, w.optionsOpened)
  end)

  it("/fu off and on toggle everything", function()
    local w = wow.load()
    w:Slash("off")
    assert.is_false(w.db.enabled)
    w:Slash(" ON ")
    assert.is_true(w.db.enabled)
  end)

  it("/fu <module> toggles it, and on|off sets it", function()
    local m = wow.module("thing", { name = "The Thing" })
    local w = wow.load({ modules = { m } })
    w:Slash("thing")
    assert.is_false(m.db.enabled)
    assert.is_false(m.active)
    assert.matches("The Thing off", w.printed[#w.printed], 1, true)
    w:Slash("thing off")
    assert.is_false(m.db.enabled)
    w:Slash("THING on")
    assert.is_true(m.active)
    assert.same({ "OnInit", "OnEnable", "OnDisable", "OnEnable" }, calls(m))
  end)

  it("/fu status lists the modules", function()
    local w = wow.load({
      modules = { wow.module("a"), wow.module("b") },
      db = { modules = { b = { enabled = false } } },
    })
    w:Slash("status")
    assert.matches("enabled, a on, b off", w.printed[1], 1, true)
  end)

  it("/fu status works with no modules", function()
    local w = wow.load({ db = { enabled = false } })
    w:Slash("status")
    assert.matches("disabled, no modules installed", w.printed[1], 1, true)
  end)

  it("/fu debug toggles debug output", function()
    local m = wow.module("thing")
    local w = wow.load({ modules = { m } })
    w:Slash("debug")
    assert.is_true(w.db.debug)
    w:Slash("thing off")
    assert.matches("thing disabled", w.printed[2], 1, true)
  end)

  it("prints help for anything else", function()
    local w = wow.load({ modules = { wow.module("thing") } })
    w:Slash("nonsense")
    w:Slash("thing sideways")
    assert.matches("options | on | off", w.printed[1], 1, true)
    assert.matches("options | on | off", w.printed[2], 1, true)
  end)
end)

describe("errors in a module", function()
  local function broken()
    return wow.module("broken", { events = { SOME_EVENT = function() error("boom") end } })
  end

  it("are caught, counted and reported once, without stopping other modules", function()
    local other = wow.module("other")
    local w = wow.load({ modules = { broken(), other } })
    w:Fire("SOME_EVENT")
    w:Fire("SOME_EVENT")
    assert.equal(1, #w.ns.errors)
    assert.equal(2, w.ns.errors[1].count)
    assert.matches("^broken SOME_EVENT: .*boom", w.ns.errors[1].text)
    assert.same({ "SOME_EVENT" }, other.calls[#other.calls])
    local notices = 0
    for _, line in ipairs(w.printed) do
      if line:find("/fu errors", 1, true) then notices = notices + 1 end
    end
    assert.equal(1, notices)
  end)

  it("are listed by /fu errors", function()
    local w = wow.load({ modules = { broken() } })
    w:Slash("errors")
    assert.matches("no errors caught", w.printed[#w.printed])
    w:Fire("SOME_EVENT")
    w:Slash("errors")
    assert.matches("1x broken SOME_EVENT: .*boom", w.printed[#w.printed])
  end)

  it("passes results through when nothing goes wrong", function()
    local w = wow.load()
    assert.equal(3, w.ns.Safe("adding", function(a, b) return a + b end, 1, 2))
    assert.is_nil(w.ns.Safe("failing", function() error("no") end))
  end)
end)

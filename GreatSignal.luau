-- Roblox Username: dragon33233 | Discord Username: biggiecheese13
-- This module implements a high-performance Linked-List Signal system with Parallel Luau support.
-- https://drive.google.com/file/d/175LwDjl2vEonw_B88sf0mAtJy5uCSBma/view?usp=sharing

--[[ 
    INTERNAL SIGNAL MODULE
    Works like a BindableEvent but with better performance and strict typing.
    
    USAGE:
    - Server <--> Server Communication
    - Client <--> Client Communication
--]]

--!strict
local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

type PackedArgs = { n: number, [number]: any }

--[[ 
    TYPE DEFINITIONS
]]
export type Connection = {
	Connected: boolean,
	_signal: Signal?,
	_callback: ((...any) -> ())?,
	_next: Connection?,
	_prev: Connection?,
	_parallel: boolean,
	_traceback: string?,
	Disconnect: (self: Connection) -> (),
	Destroy: (self: Connection) -> (),
}

export type Signal = {
	_head: Connection?,
	_tail: Connection?,
	_count: number,
	_name: string,
	_isDestroyed: boolean,
	_debugMode: boolean,
	_proxyConns: {[RBXScriptConnection]: true},
	_waiters: {[thread]: true},
	Connect: (self: Signal, callback: (...any) -> ()) -> Connection,
	ConnectParallel: (self: Signal, callback: (...any) -> ()) -> Connection,
	Once: (self: Signal, callback: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	FireImmediate: (self: Signal, ...any) -> (),
	FireDeferred: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	GetCount: (self: Signal) -> number,
	IsDestroyed: (self: Signal) -> boolean,
	DisconnectAll: (self: Signal) -> (),
	Proxy: (self: Signal, otherSignal: RBXScriptSignal) -> RBXScriptConnection,
	Destroy: (self: Signal) -> (),
}

--[[ 
    UTILITIES
]]
local function packArgs(...): PackedArgs
	return table.pack(...)
end

local function runCallback(cb: (...any) -> (), name: string, tb: string?, args: PackedArgs)
	local ok, err = pcall(function()
		cb(table.unpack(args, 1, args.n))
	end)

	if not ok then
		warn(`Signal '{name}' Error: {err}\nTraceback: {tb or "N/A"}`)
	end
end

local function runParallel(cb: (...any) -> (), name: string, tb: string?, args: PackedArgs)

	local success = pcall(task.desynchronize)
	if not success then
		warn("There was a problem during function runParallel!")
	end
	runCallback(cb, name, tb, args)
end

local function weakSet<T>(): {[T]: true}
	return (setmetatable({}, { __mode = "k" }) :: any)
end

--[[ 
    CONNECTION IMPLEMENTATION
]]
function Connection.new(signal: Signal, callback: (...any)->(), parallel: boolean?): Connection
	local self = (setmetatable({
		Connected = true,
		_signal = signal,
		_callback = callback,
		_next = nil,
		_prev = nil,
		_parallel = parallel or false,
		_traceback = if signal._debugMode then debug.traceback(nil, 3) else nil,
	}, Connection) :: any)

	return self :: Connection
end

function Connection:Disconnect()
	local self = self :: Connection
	if not self.Connected then return end

	local signal = self._signal
	if not signal then return end

	self.Connected = false
	signal._count -= 1

	local nextNode = self._next
	local prevNode = self._prev

	if prevNode then
		prevNode._next = nextNode
	else
		signal._head = nextNode
	end

	if nextNode then
		nextNode._prev = prevNode
	else
		signal._tail = prevNode
	end

	self._signal = nil
	self._callback = nil
	self._next = nil
	self._prev = nil
end

function Connection:Destroy()
	(self :: Connection):Disconnect()
end

--[[ 
    SIGNAL IMPLEMENTATION
]]
function Signal.new(name: string?, debugMode: boolean?): Signal
	local self = (setmetatable({
		_head = nil,
		_tail = nil,
		_count = 0,
		_name = name or "Signal",
		_isDestroyed = false,
		_debugMode = debugMode or false,
		_proxyConns = weakSet(),
		_waiters = weakSet(),
	}, Signal) :: any)

	return self :: Signal
end

function Signal:Connect(cb: (...any) -> ()): Connection
	local self = self :: Signal
	assert(not self._isDestroyed, "Signal destroyed")
	local conn = Connection.new(self, cb, false)

	if self._tail then
		self._tail._next = conn
		conn._prev = self._tail
		self._tail = conn
	else
		self._head = conn
		self._tail = conn
	end

	self._count += 1
	return conn :: any
end

function Signal:ConnectParallel(cb: (...any) -> ()): Connection
	local self = self :: Signal
	assert(not self._isDestroyed, "Signal destroyed")
	local conn = Connection.new(self, cb, true)

	if self._tail then
		self._tail._next = conn
		conn._prev = self._tail
		self._tail = conn
	else
		self._head = conn
		self._tail = conn
	end

	self._count += 1
	return conn :: any
end

function Signal:Fire(...)
	local self = self :: Signal
	if self._isDestroyed then return end
	local args = packArgs(...)
	local current = self._head

	while current do
		local nextNode = current._next
		if current.Connected and current._callback then
			if current._parallel then
				task.spawn(runParallel, current._callback, self._name, current._traceback, args)
			else
				task.spawn(runCallback, current._callback, self._name, current._traceback, args)
			end
		end
		current = nextNode
	end
end

function Signal:FireImmediate(...)
	local self = self :: Signal
	if self._isDestroyed then return end
	local args = packArgs(...)
	local current = self._head

	while current do
		local nextNode = current._next
		if current.Connected and current._callback then
			runCallback(current._callback, self._name, current._traceback, args)
		end
		current = nextNode
	end
end

function Signal:FireDeferred(...)
	local self = self :: Signal
	if self._isDestroyed then return end
	local args = packArgs(...)
	local current = self._head

	while current do
		local nextNode = current._next
		if current.Connected and current._callback then
			task.defer(runCallback, current._callback, self._name, current._traceback, args)
		end
		current = nextNode
	end
end

function Signal:GetCount(): number
	return (self :: Signal)._count
end

function Signal:IsDestroyed(): boolean
	return (self :: Signal)._isDestroyed
end

function Signal:DisconnectAll()
	local self = self :: Signal
	local current = self._head
	while current do
		local nextNode = current._next
		current:Disconnect()
		current = nextNode
	end
end

function Signal:Once(callback: (...any) -> ()): Connection
	local self = self :: Signal
	local conn: Connection
	conn = self:Connect(function(...)
		if conn.Connected then conn:Disconnect() end
		callback(...)
	end)
	return conn
end

function Signal:Wait(): ...any
	local self = self :: Signal
	local thread = coroutine.running()
	self._waiters[thread] = true

	local conn: Connection
	conn = self:Connect(function(...)
		if self._waiters[thread] then
			self._waiters[thread] = nil
			conn:Disconnect()
			coroutine.resume(thread, ...) 
		end
	end)

	return coroutine.yield()
end
function Signal:Proxy(otherSignal: RBXScriptSignal): RBXScriptConnection
	local self = self :: Signal
	local conn = (otherSignal:Connect(function(...)
		self:Fire(...)
	end) :: RBXScriptConnection)
	self._proxyConns[conn] = true
	return conn
end

function Signal:Destroy()
	local self = self :: Signal
	if self._isDestroyed then return end
	self._isDestroyed = true

	self:DisconnectAll()

	for c in pairs(self._proxyConns) do
		c:Disconnect()
	end

	for t in pairs(self._waiters) do
		task.spawn(t)
	end

	self._head = nil
	self._tail = nil
	self._count = 0
end

function Signal:Diagnose()
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		warn("[Signal Diagnosis] Access Denied: Diagnose can only be called from a Server Script.")
		return
	end

	local self = self :: Signal

	print("\n--- [SIGNAL SYSTEM DIAGNOSIS] ---")
	print(`Signal Name: {self._name}`)
	print(`Current Connections: {self._count}`)
	print(`Is Destroyed: {self._isDestroyed}`)
	print(`Debug Mode: {self._debugMode}`)

	local testsPassed = 0
	local totalTests = 5

	local immediateCheck: any = false
	local conn = self:Connect(function(val: any)
		immediateCheck = val
	end)

	self:FireImmediate(true)

	if immediateCheck == true then 
		print("✅ [1/5] FireImmediate: Success") 
		testsPassed += 1
	end
	conn:Disconnect()

	local onceCount = 0
	self:Once(function()
		onceCount += 1
	end)
	self:FireImmediate(nil)
	self:FireImmediate(nil)

	if onceCount == 1 then
		print("✅ [2/5] Once: Success (Fired exactly once)")
		testsPassed += 1
	else
		warn("❌ [2/5] Once: Failed")
	end

	local disconnectCheck = true
	local conn2 = self:Connect(function()
		disconnectCheck = false
	end)
	conn2:Disconnect()
	self:FireImmediate(nil)

	if disconnectCheck then
		print("✅ [3/5] Disconnect: Success (Link severed)")
		testsPassed += 1
	else
		warn("❌ [3/5] Disconnect: Failed")
	end

	local waitSuccess = false
	task.spawn(function()
		local val: any = self:Wait()
		if typeof(val) == "string" and val == "WaitTest" then
			waitSuccess = true
		end
	end)
	task.wait(0.1) 
	self:FireImmediate("WaitTest")

	if waitSuccess then
		print("✅ [4/5] Wait: Success")
		testsPassed += 1
	else
		warn("❌ [4/5] Wait: Failed")
	end

	local proxySuccess = false
	local bindable = Instance.new("BindableEvent")
	self:Proxy(bindable.Event)

	local conn3 = self:Connect(function(val: any)
		if typeof(val) == "string" and val == "ProxyTest" then 
			proxySuccess = true 
		end
	end)

	bindable:Fire("ProxyTest")

	task.defer(function()
		if proxySuccess then
			print("✅ [5/5] Proxy: Success")
			testsPassed += 1
		else
			warn("❌ [5/5] Proxy: Failed")
		end

		conn3:Disconnect()
		bindable:Destroy()

		print(`--- DIAGNOSIS COMPLETE: {testsPassed}/{totalTests} PASSED ---\n`)
	end)
end

return Signal

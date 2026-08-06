--!strict
-- Fakes.luau
-- Injectable fakes for Roblox services and ProfileStore library so unit tests
-- run without touching live Roblox services (TEST_PLAN.md §1).

local Fakes = {}

--------------------------------------------------------------------------------
-- Fake Instance & Player
--------------------------------------------------------------------------------

type FakePlayerSignal = {
	Connect: (self: any, fn: (player: Player) -> ()) -> (),
	Fire: (self: any, player: Player) -> (),
}

function Fakes.createFakeSignal(): FakePlayerSignal
	local listeners = {}
	return {
		Connect = function(_, fn)
			table.insert(listeners, fn)
		end,
		Fire = function(_, player)
			for _, fn in ipairs(listeners) do
				fn(player)
			end
		end,
	}
end

function Fakes.createFakePlayer(userId: number, name: string): Player
	local player = {
		UserId = userId,
		Name = name,
		Parent = nil,
		IsA = function(_, className: string)
			return className == "Player" or className == "Instance"
		end,
		Kick = function(_, reason: string)
			-- recorded for tests
		end,
	}
	return player :: any
end

--------------------------------------------------------------------------------
-- Fake RemoteFunction & RemoteEvent
--------------------------------------------------------------------------------

export type FakeRemoteFunction = {
	OnServerInvoke: ((player: Player, ...any) -> ...any)?,
	InvokeServer: (self: any, player: Player, ...any) -> ...any,
}

export type FakeRemoteEvent = {
	FireClient: (self: any, player: Player, data: any) -> (),
	fired: { { player: Player, data: any } },
}

function Fakes.createFakeRemoteFunction(): FakeRemoteFunction
	local remote = {
		OnServerInvoke = nil :: ((player: Player, ...any) -> ...any)?,
		InvokeServer = function(self, player, ...)
			if self.OnServerInvoke then
				return self.OnServerInvoke(player, ...)
			end
			return nil
		end,
	}
	return remote
end

function Fakes.createFakeRemoteEvent(): FakeRemoteEvent
	local firedList = {}
	return {
		fired = firedList,
		FireClient = function(_, player, data)
			table.insert(firedList, { player = player, data = data })
		end,
	}
end

--------------------------------------------------------------------------------
-- Fake ProfileStore profile object
--------------------------------------------------------------------------------

export type FakeProfile = {
	Data: any,
	MetaData: { ActiveSession: any, ProfileId: string },
	_is_active: boolean,
	IsActive: (self: any) -> boolean,
	EndSession: (self: any) -> (),
	Release: (self: any) -> (),
	ListenToRelease: (self: any, fn: () -> ()) -> (),
	OnSessionEnd: { Connect: (self: any, fn: () -> ()) -> () },
	Save: (self: any) -> (),
	Reconcile: (self: any) -> (),
	AddUserId: (self: any, userId: number) -> (),
	_release_listeners: { () -> () },
}

function Fakes.createFakeProfile(data: any): FakeProfile
	local releaseListeners = {}
	local prof: FakeProfile = {
		Data = data,
		MetaData = { ActiveSession = { "PlaceId", "JobId" }, ProfileId = "FakeId" },
		_is_active = true,
		_release_listeners = releaseListeners,
		IsActive = function(self)
			return self._is_active
		end,
		EndSession = function(self)
			self._is_active = false
			for _, fn in ipairs(self._release_listeners) do
				fn()
			end
		end,
		Release = function(self)
			self:EndSession()
		end,
		ListenToRelease = function(_, fn)
			table.insert(releaseListeners, fn)
		end,
		OnSessionEnd = {
			Connect = function(_, fn)
				table.insert(releaseListeners, fn)
			end,
		},
		Save = function(_)
			-- no-op fake
		end,
		Reconcile = function(_)
		end,
		AddUserId = function(_, _)
		end,
	}
	return prof
end

return Fakes

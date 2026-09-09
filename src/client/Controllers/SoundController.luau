--!strict
-- Client audio routing (spec §9, docs/INTERFACES.md M3): three SoundGroups under
-- SoundService from Sounds.json, one pre-created Sound per non-zero id, per-setting group
-- volumes, and a looping per-era ambient. Every id ships as 0, so the whole module must be
-- a silent no-op path: unknown keys, id 0, or a missing Sounds.json never warn or error.
-- Init builds everything synchronously — Catalog.GetSoundsConfig never yields — so Play is
-- usable from the first Start; before Init it is a harmless no-op (empty tables).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local Create = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Create"))

local ASSET_PREFIX = "rbxassetid://"
local MUSIC_GROUP = "Music" -- the one group that follows the `music` setting; others follow `sfx`

export type Settings = { music: boolean, sfx: boolean }
export type PlayOptions = { milestones: number? }

local groups: { [string]: SoundGroup } = {}
local groupBaseVolumes: { [string]: number } = {}
local sounds: { [string]: Sound } = {}
local pitchPerMilestone: { [string]: number } = {}
local ambientSounds: { [string]: Sound } = {}
local currentAmbient: string? = nil
local currentSettings: Settings = { music = true, sfx = true }

local function groupEnabled(groupName: string): boolean
	return if groupName == MUSIC_GROUP then currentSettings.music else currentSettings.sfx
end

local function applyGroupVolumes(): ()
	for name, group in groups do
		group.Volume = if groupEnabled(name) then groupBaseVolumes[name] else 0
	end
end

-- Returns nil for id 0 (silent by contract) or a malformed entry; never warns.
local function makeSound(name: string, def: Types.SoundDef, looped: boolean): Sound?
	if typeof(def) ~= "table" or typeof(def.id) ~= "number" or def.id <= 0 then
		return nil
	end
	-- A sound outside the three groups would ignore the Music/SFX toggles; stay silent instead.
	local group: SoundGroup? = groups[def.group]
	if group == nil then
		return nil
	end
	local volume = if typeof(def.volume) == "number" then def.volume else 1
	return Create("Sound", {
		Name = name,
		SoundId = ASSET_PREFIX .. tostring(math.floor(def.id)),
		Volume = volume,
		Looped = looped,
		SoundGroup = group,
		Parent = SoundService,
	}) :: Sound
end

local SoundController = {}

function SoundController.Init(): ()
	local config = Catalog.GetSoundsConfig()
	if typeof(config.groups) == "table" then
		for name, volume in config.groups do
			if typeof(volume) ~= "number" then
				continue
			end
			groups[name] = Create("SoundGroup", {
				Name = name,
				Volume = volume,
				Parent = SoundService,
			}) :: SoundGroup
			groupBaseVolumes[name] = volume
		end
	end
	if typeof(config.sounds) == "table" then
		for key, def in config.sounds do
			local sound = makeSound(key, def, false)
			if sound == nil then
				continue
			end
			sounds[key] = sound
			if typeof(def.pitchPerMilestone) == "number" then
				pitchPerMilestone[key] = def.pitchPerMilestone
			end
		end
	end
	if typeof(config.ambient) == "table" then
		for eraName, def in config.ambient do
			local sound = makeSound("Ambient_" .. eraName, def, true)
			if sound ~= nil then
				ambientSounds[eraName] = sound
			end
		end
	end
	applyGroupVolumes()
end

function SoundController.Start(): () end

-- Unknown key or id 0 ⇒ no-op. `milestones` only matters for keys that declare
-- pitchPerMilestone (levelUp): each milestone already reached raises PlaybackSpeed.
function SoundController.Play(key: string, opts: PlayOptions?): ()
	local sound: Sound? = sounds[key]
	if sound == nil then
		return
	end
	local speed = 1
	local perMilestone = pitchPerMilestone[key]
	local milestones = if opts ~= nil then opts.milestones else nil
	if perMilestone ~= nil and milestones ~= nil then
		speed += perMilestone * milestones
	end
	sound.PlaybackSpeed = speed
	sound:Play()
end

-- UI and SFX groups follow `sfx`; Music (including ambient) follows `music`.
function SoundController.ApplySettings(settings: Settings): ()
	if typeof(settings) ~= "table" then
		return
	end
	if typeof(settings.music) == "boolean" then
		currentSettings.music = settings.music
	end
	if typeof(settings.sfx) == "boolean" then
		currentSettings.sfx = settings.sfx
	end
	applyGroupVolumes()
end

-- nil stops the ambient. Same era twice is a no-op so snapshots never restart the loop.
function SoundController.SetAmbientEra(eraName: string?): ()
	if eraName == currentAmbient then
		return
	end
	local previousName = currentAmbient
	if previousName ~= nil then
		local previous: Sound? = ambientSounds[previousName]
		if previous ~= nil then
			previous:Stop()
		end
	end
	currentAmbient = eraName
	if eraName ~= nil then
		local nextAmbient: Sound? = ambientSounds[eraName]
		if nextAmbient ~= nil then
			nextAmbient:Play()
		end
	end
end

return SoundController

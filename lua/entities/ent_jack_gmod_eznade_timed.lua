-- Jackarunda 2019
AddCSLuaFile()
ENT.Base = "ent_jack_gmod_ezmininade"
ENT.Author="Jackarunda, TheOnly8Z"
ENT.Category="JMod - EZ"
ENT.PrintName="EZminiNade-Timed"
ENT.Spawnable=true

ENT.Material = "models/mats_jack_nades/gnd_ylw"
ENT.MiniNadeDamageMin = 80
ENT.MiniNadeDamageMax = 120

local BaseClass = baseclass.Get(ENT.Base)

if(SERVER)then
	function ENT:Arm()
		self:SetBodygroup(2,1)
		self:SetState(JMOD_EZ_STATE_ARMED)
		timer.Simple((IsValid(self.AttachedBomb) and 10 or 3),function()
			if(IsValid(self))then self:Detonate() end
		end)
	end
elseif(CLIENT)then
	language.Add("ent_jack_gmod_eznade_timed","EZminiNade-Timed")
end
local function IsDamageThisType(dmg,typ)
	if(typ==DMG_BULLET)then
		local AmmoTyp=dmg:GetAmmoType()
		if(AmmoTyp)then
			if(game.GetAmmoName(AmmoTyp)=="Buckshot")then
				return false
			end
		end
	elseif(typ==DMG_BUCKSHOT)then
		local AmmoTyp=dmg:GetAmmoType()
		if(AmmoTyp)then
			if(game.GetAmmoName(AmmoTyp)=="Buckshot")then
				return true
			end
		end
	end
	return dmg:IsDamageType(typ)
end
local function IsDamageOneOfTypes(dmg,types)
	for k,v in pairs(types)do
		if(IsDamageThisType(dmg,v))then return true end
	end
	return false
end
function JModEZarmorSync(ply)
    if not(ply.EZarmor)then return end
    ply.EZarmor.effects={}
	ply.EZarmor.mskmat=nil
	ply.EZarmor.sndlop=nil
    for id,item in pairs(ply.EZarmor.items)do
		if not(item.disengaged)then
			local ArmorInfo=JMod_ArmorTable[item.name]
			if(ArmorInfo.eff)then
				local Depleted=item.chrg and item.chrg.electricity and item.chrg.electricity<=0
				if not(Depleted)then
					for effName,effMag in pairs(ArmorInfo.eff)do
						if(type(effMag)=="number")then
							ply.EZarmor.effects[effName]=(ply.EZarmor.effects or 0)+effMag
						else
							ply.EZarmor.effects[effName]=true
						end
					end
				end
			end
			if(ArmorInfo.mskmat)then ply.EZarmor.mskmat=ArmorInfo.mskmat end
			if(ArmorInfo.sndlop)then ply.EZarmor.sndlop=ArmorInfo.sndlop end
		end
    end
    net.Start("JMod_EZarmorSync")
	net.WriteEntity(ply)
	net.WriteTable(ply.EZarmor)
    net.Broadcast()
end
local function IsHitToFace(ply,dmg)
	local FacingDir,DmgDir=ply:GetAimVector(),dmg:GetDamageForce():GetNormalized()
	local ApproachAngle=-math.deg(math.asin(DmgDir:DotProduct(FacingDir)))
	return ApproachAngle>45
end
local function IsHitToBack(ply,dmg)
	local FacingDir,DmgDir=ply:GetAimVector(),dmg:GetDamageForce():GetNormalized()
	local ApproachAngle=-math.deg(math.asin(DmgDir:DotProduct(FacingDir)))
	return ApproachAngle<-45
end
local function GetProtectionFromSlot(ply,slot,dmg,dmgAmt,protectionMul,shouldDmgArmor)
	local Protection,Busted=0,false
	for id,armorData in pairs(ply.EZarmor.items)do
		local ArmorInfo=JMod_ArmorTable[armorData.name]
		if(ArmorInfo)then
			for armorSlot,coverage in pairs(ArmorInfo.slots)do
				if(armorSlot==slot)then
					for damType,damProtection in pairs(ArmorInfo.def)do
						if(IsDamageThisType(dmg,damType))then
							Protection=Protection+damProtection*coverage*protectionMul
							if(shouldDmgArmor)then
								if not(IsDamageOneOfTypes(dmg,JMod_BiologicalDmgTypes))then
									local ArmorDmgAmt=Protection*dmgAmt*JMOD_CONFIG.ArmorDegredationMult
									if(damType==DMG_BUCKSHOT)then ArmorDmgAmt=ArmorDmgAmt/2 end
									armorData.dur=armorData.dur-ArmorDmgAmt
									if(armorData.dur<=0)then
										JMod_RemoveArmorByID(ply,id,true)
										Busted=true
									end
								elseif((armorData.chrg)and(armorData.chrg.biochem))then
									local SubtractAmt=Protection*dmgAmt*JMOD_CONFIG.ArmorDegredationMult/10
									armorData.chrg.biochem=math.Clamp(armorData.chrg.biochem-SubtractAmt,0,9e9)
									if(armorData.chrg.biochem<=0)then Protection=0 end
								end
							end
							break
						end
					end
					break
				end
			end
		end
	end
	return Protection,Busted
end
local function LocationalDmgHandling(ply,hitgroup,dmg)
	if(#table.GetKeys(ply.EZarmor.items)<=0)then return end
	local Mul,RelevantSlots,DmgAmt=1,{},dmg:GetDamage()
	if(hitgroup==HITGROUP_HEAD)then
		RelevantSlots.ears=.25
		if(IsHitToFace(ply,dmg))then
			RelevantSlots.eyes=.5
			RelevantSlots.mouthnose=.5
		else
			RelevantSlots.head=1
		end
	elseif(hitgroup==HITGROUP_CHEST)then
		RelevantSlots.chest=1
		if(IsHitToBack(ply,dmg))then
			RelevantSlots.back=.25
		end
	elseif(hitgroup==HITGROUP_STOMACH)then
		RelevantSlots.abdomen=.5
		RelevantSlots.pelvis=.5
	elseif(hitgroup==HITGROUP_RIGHTARM)then
		RelevantSlots.rightshoulder=.5
		RelevantSlots.rightforearm=.5
	elseif(hitgroup==HITGROUP_LEFTARM)then
		RelevantSlots.leftshoulder=.5
		RelevantSlots.leftforearm=.5
	elseif(hitgroup==HITGROUP_RIGHTLEG)then
		RelevantSlots.rightthigh=.5
		RelevantSlots.rightcalf=.5
	elseif(hitgroup==HITGROUP_LEFTLEG)then
		RelevantSlots.leftthigh=.5
		RelevantSlots.leftcalf=.5
	end
	local Protection,ArmorPieceBroke=0,false
	for slot,relevance in pairs(RelevantSlots)do
		local ProtectionForThisSlot,Busted=GetProtectionFromSlot(ply,slot,dmg,DmgAmt,relevance,true)
		if((slot~="ears")and(slot~="back"))then
			Protection=Protection+ProtectionForThisSlot
		end
		ArmorPieceBroke=ArmorPieceBroke or Busted
	end
	Mul=(Mul-Protection)/JMOD_CONFIG.ArmorProtectionMult
	dmg:ScaleDamage(Mul)
	if(ArmorPieceBroke)then JModEZarmorSync(ply) end
end
local function FullBodyDmgHandling(ply,dmg,biological)
	if(#table.GetKeys(ply.EZarmor.items)<=0)then return end
	local Mul,Protection,DmgAmt,ArmorPieceBroke=1,0,dmg:GetDamage(),false
	for slot,healthMult in pairs(JMod_BodyPartHealthMults)do
		local ProtectionForThisSlot,Busted=GetProtectionFromSlot(ply,slot,dmg,DmgAmt,(biological and 1) or healthMult,true)
		if((slot~="ears")and(slot~="back"))then
			Protection=Protection+ProtectionForThisSlot
		end
		ArmorPieceBroke=ArmorPieceBroke or Busted
	end
	Mul=(Mul-Protection)/JMOD_CONFIG.ArmorProtectionMult
	dmg:ScaleDamage(Mul)
	if(ArmorPieceBroke)then JModEZarmorSync(ply) end
end
hook.Add("ScalePlayerDamage","JMod_ScalePlayerDamage",function(ply,hitgroup,dmginfo)
	if(ply.EZarmor)then LocationalDmgHandling(ply,hitgroup,dmginfo) end
end)
hook.Add("EntityTakeDamage","JMod_EntityTakeDamage",function(victim,dmginfo)
	if((victim:IsPlayer())and(victim.EZarmor))then
		if(IsDamageOneOfTypes(dmginfo,JMod_LocationalDmgTypes))then
			return -- scaling handled in scaleplayerdamage
		elseif(IsDamageOneOfTypes(dmginfo,JMod_FullBodyDmgTypes))then
			FullBodyDmgHandling(victim,dmginfo,false)
		elseif(IsDamageOneOfTypes(dmginfo,JMod_BiologicalDmgTypes))then
			FullBodyDmgHandling(victim,dmginfo,true)
		end
	end
end)
local function CalcSpeed(ply)
    local Walk,Run,TotalWeight=ply.EZoriginalWalkSpeed or 200,ply.EZoriginalRunSpeed or 400,0
    for k,v in pairs(ply.EZarmor.items)do
		local ArmorInfo=JMod_ArmorTable[v.name]
        TotalWeight=TotalWeight+ArmorInfo.wgt
    end
    local WeighedFrac=TotalWeight/250
    ply.EZarmor.speedfrac=math.Clamp(1-(.8*WeighedFrac*JMOD_CONFIG.ArmorWeightMult),.05,1)
end
hook.Add("PlayerFootstep","JMOD_PlayerFootstep",function(ply,pos,foot,snd,vol,filter)
	if(ply.EZarmor)then
		local Num=#table.GetKeys(ply.EZarmor.items)
		if(Num>=6)then
			ply:EmitSound("snd_jack_gear"..tostring(math.random(1,6))..".wav",58,math.random(70,130))
		end
	end
end)
local EquipSounds={"snd_jack_clothequip.wav","snds_jack_gmod/equip1.wav","snds_jack_gmod/equip2.wav","snds_jack_gmod/equip3.wav","snds_jack_gmod/equip4.wav","snds_jack_gmod/equip5.wav"}
function JMod_RemoveArmorByID(ply,ID,broken)
    local Info=ply.EZarmor.items[ID]
    if not(Info)then return end
    local Specs=JMod_ArmorTable[Info.name]
    timer.Simple(math.Rand(0,.5),function()
        if(broken)then
            ply:EmitSound("snds_jack_gmod/armorbreak.wav",60,math.random(80,120))
        else
            ply:EmitSound(table.Random(EquipSounds),60,math.random(80,120))
        end
    end)
    if not(broken)then
        local Ent=ents.Create(Specs.ent)
        Ent:SetPos(ply:GetShootPos()+ply:GetAimVector()*30+VectorRand()*math.random(1,20))
        Ent:SetAngles(AngleRand())
        Ent.ArmorDurability=Info.dur
		if(Info.chrg)then Ent.ArmorCharges=table.FullCopy(Info.chrg) end
		Ent.EZID=ID
        Ent:SetColor(Info.col)
        Ent:Spawn()
        Ent:Activate()
        Ent:GetPhysicsObject():SetVelocity(ply:GetVelocity())
    end
    ply.EZarmor.items[ID]=nil
end
local function AreSlotsClear(currentArmorItems,newArmorName)
	local NewArmorInfo=JMod_ArmorTable[newArmorName]
	local RequiredSlots=NewArmorInfo.slots
	for id,currentArmorData in pairs(currentArmorItems)do
		local CurrentArmorInfo=JMod_ArmorTable[currentArmorData.name]
		for newSlotName,newCoverage in pairs(RequiredSlots)do
			for oldSlotName,oldCoverage in pairs(CurrentArmorInfo.slots)do
				if(oldSlotName==newSlotName)then return false,id end
			end
		end
	end
	return true,nil
end
function JMod_EZ_Equip_Armor(ply,nameOrEnt)
	local NewArmorName=nameOrEnt
	local NewArmorID,NewArmorDurability,NewArmorColor,NewArmorSpecs,NewArmorCharges
	if(type(nameOrEnt)~="string")then
		if not(IsValid(nameOrEnt))then return end
		NewArmorName=nameOrEnt.ArmorName
		NewArmorSpecs=JMod_ArmorTable[NewArmorName]
		NewArmorID=nameOrEnt.EZID
		NewArmorDurability=nameOrEnt.ArmorDurability or NewArmorSpecs.dur
		NewArmorColor=nameOrEnt:GetColor()
		NewArmorCharges=nameOrEnt.ArmorCharges
		nameOrEnt:Remove()
	else
		NewArmorSpecs=JMod_ArmorTable[NewArmorName]
		NewArmorID=JMod_GenerateGUID()
		NewArmorColor=Color(128,128,128)
		NewArmorDurability=NewArmorSpecs.dur
		if(NewArmorSpecs.chrg)then NewArmorCharges=table.FullCopy(NewArmorSpecs.chrg) end
	end
	local AreSlotsClear,ConflictingItemID=AreSlotsClear(ply.EZarmor.items,NewArmorName)
	if not(AreSlotsClear)then JMod_RemoveArmorByID(ply,ConflictingItemID) end
	local NewVirtualArmorItem={
		name=NewArmorName,
		dur=NewArmorDurability,
		col=NewArmorColor,
		chrg=NewArmorCharges,
		id=NewArmorID
	}
	ply.EZarmor.items[NewArmorID]=NewVirtualArmorItem
	CalcSpeed(ply)
    JModEZarmorSync(ply)
end
function JMod_EZ_Remove_Armor(ply)
    for k,v in pairs(ply.EZarmor.items)do
        JMod_RemoveArmorByID(ply,k)
    end
    CalcSpeed(ply)
    JModEZarmorSync(ply)
end
concommand.Add("jmod_debug_fullarmor",function(ply,cmd,args)
	if not((ply)and(ply:IsSuperAdmin()))then return end
	JMod_EZ_Equip_Armor(ply,"BallisticMask")
	JMod_EZ_Equip_Armor(ply,"Heavy-Helmet")
	JMod_EZ_Equip_Armor(ply,"Heavy-Vest")
	JMod_EZ_Equip_Armor(ply,"Pelvis-Panel")
	JMod_EZ_Equip_Armor(ply,"Heavy-Left-Shoulder")
	JMod_EZ_Equip_Armor(ply,"Heavy-Right-Shoulder")
	JMod_EZ_Equip_Armor(ply,"Left-Forearm")
	JMod_EZ_Equip_Armor(ply,"Right-Forearm")
	JMod_EZ_Equip_Armor(ply,"Left-Thigh")
	JMod_EZ_Equip_Armor(ply,"Right-Thigh")
	JMod_EZ_Equip_Armor(ply,"Left-Calf")
	JMod_EZ_Equip_Armor(ply,"Right-Calf")
end)
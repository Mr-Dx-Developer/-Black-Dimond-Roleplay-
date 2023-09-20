Utils = exports['lc_utils']:GetUtils()
local menu_active = false
local current_market_id = nil
local job_data = {}
local cooldown = nil

-----------------------------------------------------------------------------------------------------------------------------------------
-- LOCAL
-----------------------------------------------------------------------------------------------------------------------------------------	

function createMarkersThread()
	Citizen.CreateThreadNow(function()
		local timer = 1
		while true do
			timer = 3000
			for market_id,market_data in pairs(Config.market_locations) do
				if not menu_active then
					local x,y,z = table.unpack(market_data.coord)
					if Utils.Entity.isPlayerNearCoords(x,y,z,20.0) then
						timer = 1
						Utils.Markers.createMarkerInCoords(market_id,x,y,z,Utils.translate('open'),openOwnerUiCallback)
					end
				end

				for _,customer_blip_location in pairs(market_data.sell_blip_coords) do
					if not menu_active then
						local x,y,z = table.unpack(customer_blip_location)
						if Utils.Entity.isPlayerNearCoords(x,y,z,20.0) then
							timer = 1
							Utils.Markers.createMarkerInCoords(market_id,x,y,z,Utils.translate('open_market'),openCustomerUiCallback)
						end
					end
				end

				if not Config.trucker_logistics.enable then
					local x,y,z = table.unpack(market_data.deliveryman_coord)
					if Utils.Entity.isPlayerNearCoords(x,y,z,20.0) then
						timer = 1
						renderDeliverymanJobBlip(market_id,x,y,z)
					end
				end
			end
			Citizen.Wait(timer)
		end
	end)
end
function createTargetsThread()
	Citizen.CreateThreadNow(function()
		for market_id,market_data in pairs(Config.market_locations) do
			local x,y,z = table.unpack(market_data.coord)
			Utils.Target.createTargetInCoords(market_id,x,y,z,openOwnerUiCallback,Utils.translate('open_target'),"fas fa-shop","#2986cc")

			for customer_blip_id,customer_blip_location in pairs(market_data.sell_blip_coords) do
				local x,y,z = table.unpack(customer_blip_location)
				Utils.Target.createTargetInCoords(market_id,x,y,z,openCustomerUiCallback,Utils.translate('open_market_target'),"fas fa-shopping-cart","#2986cc",market_id .. ":" .. customer_blip_id)
			end
		end
		local timer = 1
		while not Config.trucker_logistics.enable do
			timer = 3000
			for market_id,market_data in pairs(Config.market_locations) do
				local x,y,z = table.unpack(market_data.deliveryman_coord)
				if Utils.Entity.isPlayerNearCoords(x,y,z,20.0) then
					timer = 1
					renderDeliverymanJobBlip(market_id,x,y,z)
				end
			end
			Citizen.Wait(timer)
		end
	end)
end

function renderDeliverymanJobBlip(market_id,x,y,z)
	Utils.Markers.drawMarker(21,x,y,z)
	if Utils.Entity.isPlayerNearCoords(x,y,z,1.0) then
		if job_data[market_id] == nil then
			Utils.Markers.drawText3D(x,y,z-0.6, Utils.translate('download_jobs'))
			if IsControlJustPressed(0,38) then
				TriggerServerEvent('stores:loadJobData',market_id)
			end
		else
			Utils.Markers.drawText3D(x,y,z-0.6, Utils.translate('show_jobs'):format(job_data[market_id].name,job_data[market_id].reward))
			if IsControlJustPressed(0,38) then
				if canStartJob(market_id) then
					current_market_id = market_id
					TriggerServerEvent('stores:startDeliverymanJob',current_market_id,job_data[market_id].id)
				end
			end
		end
	else
		job_data[market_id] = nil
	end
end

function openOwnerUiCallback(market_id)
	current_market_id = market_id
	TriggerServerEvent("stores:getData",current_market_id)
end

function openCustomerUiCallback(market_id)
	current_market_id = market_id
	TriggerServerEvent("stores:openMarket",current_market_id)
end

RegisterNetEvent('stores:setJobData')
AddEventHandler('stores:setJobData', function(market_id,data)
	job_data[market_id] = data
end)

RegisterNetEvent('stores:open')
AddEventHandler('stores:open', function(dados,update,isMarket)
	TriggerScreenblurFadeIn(1000)
	SendNUIMessage({
		showmenu = true,
		update = update,
		isMarket = isMarket,
		dados = dados,
		utils = { config = Utils.Config, lang = Utils.Lang },
		resourceName = GetCurrentResourceName()
	})
	if update == false then
		menu_active = true
		SetNuiFocus(true,true)
	end
end)

RegisterNetEvent('stores:openRequest')
AddEventHandler('stores:openRequest', function(price, market_categories)
	SendNUIMessage({
		showmenu = true,
		price = price,
		market_categories = market_categories,
		utils = { config = Utils.Config, lang = Utils.Lang },
		resourceName = GetCurrentResourceName(),
	})
	SetNuiFocus(true,true)
end)

-----------------------------------------------------------------------------------------------------------------------------------------
-- CALLBACKS
-----------------------------------------------------------------------------------------------------------------------------------------

RegisterNUICallback('post', function(body, cb)
	if cooldown == nil then
		cooldown = true

		if body.event == "changeTheme" then
			exports['lc_utils']:changeTheme(body.data.dark_theme)
		end
		if body.event == "close" then
			closeUI()
		elseif (body.event == "startImportJob" or body.event == "startExportJob") and not canStartJob(current_market_id) then
			-- Do nothing :)
		else
			TriggerServerEvent('stores:'..body.event,current_market_id,body.event,body.data)
		end
		cb(200)

		SetTimeout(100,function()
			cooldown = nil
		end)
	end
end)

RegisterNUICallback('loadBalanceHistory', function(body, cb)
	Utils.Callback.TriggerServerCallback('stores:loadBalanceHistory', function(store_balance)
		cb(store_balance)
	end,current_market_id,body.data)
end)

RegisterNUICallback('close', function(data, cb)
	closeUI()
	cb(200)
end)

RegisterNetEvent('stores:closeUI')
AddEventHandler('stores:closeUI', function()
	closeUI()
end)

function closeUI()
	current_market_id = nil
	menu_active = false
	SetNuiFocus(false,false)
	SendNUIMessage({ hidemenu = true })
	TriggerScreenblurFadeOut(1000)
end

-----------------------------------------------------------------------------------------------------------------------------------------
-- FUNÇÕES
-----------------------------------------------------------------------------------------------------------------------------------------

RegisterNetEvent('stores:startJob')
AddEventHandler('stores:startJob', function(truck_level,is_import)
	local key = current_market_id
	job_data[key] = nil

	local destination
	if is_import then
		destination = vector3(table.unpack(Config.delivery_locations[math.random(#Config.delivery_locations)]))
	else
		destination = vector3(table.unpack(Config.export_locations[math.random(#Config.export_locations)]))
	end
	local distance_traveled = Utils.Math.round(((#(GetEntityCoords(PlayerPedId()) - destination) * 2)/1000), 2)
	local route_blip = Utils.Blips.createBlipForCoords(destination.x,destination.y,destination.z,Config.route_blip.id,Config.route_blip.color,Utils.translate('blip_route'),0.8,true)

	local garage_coord = vector4(table.unpack(Config.market_locations[key]['garage_coord']))
	local truck_model = Config.market_types[Config.market_locations[key].type].trucks[truck_level]
	local blip_data = { name = Utils.translate('truck_blip'), sprite = 477, color = 26 }
	local properties = { plate = Utils.translate('truck_plate')..tostring(math.random(1000, 9999)) }
	local truck_vehicle,truck_blip = Utils.Vehicles.spawnVehicle(truck_model,garage_coord.x,garage_coord.y,garage_coord.z,garage_coord.w,blip_data,properties)
	exports['lc_utils']:notify("success",Utils.translate('already_is_in_garage'))

	closeUI()
	local object = nil
	local delivery_phase = 1
	local timer = 2000
	while IsEntityAVehicle(truck_vehicle) do
		timer = 2000
		local ped = PlayerPedId()
		local current_vehicle = GetVehiclePedIsIn(ped,false)

		if delivery_phase == 1 then
			if is_import then
				local distance = #(GetEntityCoords(PlayerPedId()) - destination)
				if distance <= 50 then
					timer = 5
					Utils.Markers.drawMarker(39,destination.x,destination.y,destination.z,1.0)
					if distance <= 2 then
						Utils.Markers.drawText3D(destination.x,destination.y,destination.z-0.6, Utils.translate('objective_marker'))
						if IsControlJustPressed(0,38) then
							if not (IsPedSittingInAnyVehicle(ped) or IsPedInAnyVehicle(ped, true)) then
								object = createObjectAttachedToEntity("anim@heists@box_carry@","idle","hei_prop_heist_box",50,28422)
								SetVehicleDoorOpen(truck_vehicle,2,false,false)
								SetVehicleDoorOpen(truck_vehicle,3,false,false)
								SetVehicleDoorOpen(truck_vehicle,5,false,false)

								Utils.Blips.removeBlip(route_blip)
								delivery_phase = 2

								exports['lc_utils']:notify("success",Utils.translate('bring_to_van'))
							else
								exports['lc_utils']:notify("error",Utils.translate('out_of_veh'))
							end
						end
					end
				end
			else
				local distance = #(GetEntityCoords(PlayerPedId()) - destination)
				if current_vehicle == truck_vehicle and distance <= 50 then
					timer = 5
					Utils.Markers.drawMarker(39,destination.x,destination.y,destination.z,1.0)
					if distance <= 2 then
						Utils.Markers.drawText2D(Utils.translate('objective_marker_3'),8,0.5,0.95,0.50,255,255,255,235)
						if IsControlJustPressed(0,38) then
							BringVehicleToHalt(truck_vehicle, 2.5, 1, false)
							Citizen.Wait(10)
							DoScreenFadeOut(500)
							Citizen.Wait(500)
							Utils.Blips.removeBlip(route_blip)
							route_blip = Utils.Blips.createBlipForCoords(garage_coord.x,garage_coord.y,garage_coord.z,Config.route_blip.id,Config.route_blip.color,Utils.translate('blip_route'),0.8,true)
							delivery_phase = 3
							PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", false)
							Citizen.Wait(1000)
							DoScreenFadeIn(1000)
							Utils.Scaleform.showScaleform(Utils.translate('sucess_2'), Utils.translate('sucess_in_progess_2'), 3)
						end
					end
				end
			end
		elseif delivery_phase == 2 then
			if is_import then
				local xa,ya,za = table.unpack(GetWorldPositionOfEntityBone(truck_vehicle,GetEntityBoneIndexByName(truck_vehicle,"door_dside_r")))
				local xb,yb,zb = table.unpack(GetWorldPositionOfEntityBone(truck_vehicle,GetEntityBoneIndexByName(truck_vehicle,"door_pside_r")))
				local vehicle_trunk = vector3((xa+xb)/2,(ya+yb)/2,((za+zb)/2)-1.0)
				local distance = #(GetEntityCoords(ped) - vehicle_trunk)

				if distance <= 50 then
					timer = 5
					Utils.Markers.drawMarker(39,vehicle_trunk.x,vehicle_trunk.y,vehicle_trunk.z+1.5,1.0)
					if distance <= 2.0 then
						Utils.Markers.drawText3D(vehicle_trunk.x,vehicle_trunk.y,vehicle_trunk.z+1.0, Utils.translate('objective_marker_2'))
						if IsControlJustPressed(0,38) then
							if not (IsPedSittingInAnyVehicle(ped) or IsPedInAnyVehicle(ped, true))  then
								deleteObject(object)
								route_blip = Utils.Blips.createBlipForCoords(garage_coord.x,garage_coord.y,garage_coord.z,Config.route_blip.id,Config.route_blip.color,Utils.translate('blip_route'),0.8,true)
								delivery_phase = 3

								exports['lc_utils']:notify("success",Utils.translate('bring_to_store'))

								SetTimeout(3000,function()
									SetVehicleDoorShut(truck_vehicle,2,false)
									SetVehicleDoorShut(truck_vehicle,3,false)
									SetVehicleDoorShut(truck_vehicle,5,false)
								end)
							else
								exports['lc_utils']:notify("error",Utils.translate('out_of_veh'))
							end
						end
					end
				end
			end
		elseif delivery_phase == 3 then
			local distance = #(GetEntityCoords(ped) - garage_coord.xyz)
			if distance <= 50 and current_vehicle == truck_vehicle then
				timer = 5
				Utils.Markers.drawMarker(39,garage_coord.x,garage_coord.y,garage_coord.z+1.5,1.0)
				if distance <= 4 then
					BringVehicleToHalt(truck_vehicle, 2.5, 1, false)
					Citizen.Wait(10)
					DoScreenFadeOut(500)
					Citizen.Wait(500)
					Utils.Blips.removeBlip(truck_blip)
					Utils.Blips.removeBlip(route_blip)
					Utils.Framework.removeVehicleKeys(truck_vehicle)
					Utils.Vehicles.deleteVehicle(truck_vehicle)
					PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", false)
					Citizen.Wait(1000)
					DoScreenFadeIn(1000)
					if is_import then
						Utils.Scaleform.showScaleform(Utils.translate('sucess'), Utils.translate('sucess_finished'), 3)
						TriggerServerEvent("stores:finishImportJob",key,distance_traveled)
					else
						Utils.Scaleform.showScaleform(Utils.translate('sucess_2'), Utils.translate('sucess_finished_2'), 3)
						TriggerServerEvent("stores:finishExportJob",key,distance_traveled)
					end
					return
				end
			end
		end

		local vehicles = { truck_vehicle }
		local peds = { ped }
		local has_error, error_message = Utils.Entity.isThereSomethingWrongWithThoseBoys(vehicles,peds)
		if has_error then
			deleteObject(object)
			Utils.Framework.removeVehicleKeys(truck_vehicle)
			Utils.Blips.removeBlip(truck_blip)
			Utils.Blips.removeBlip(route_blip)
			PlaySoundFrontend(-1, "PROPERTY_PURCHASE", "HUD_AWARDS", false)
			if Utils.Table.contains({'vehicle_almost_destroyed','vehicle_undriveable','ped_is_dead'}, error_message) then
				SetVehicleEngineHealth(truck_vehicle,-4000)
				SetVehicleUndriveable(truck_vehicle,true)
			end
			if error_message == 'ped_is_dead' then
				exports['lc_utils']:notify("error",Utils.translate('you_died'))
			else
				exports['lc_utils']:notify("error",Utils.translate('vehicle_destroyed'))
			end
			TriggerServerEvent("stores:failed")
			return
		end

		Citizen.Wait(timer)
	end
	deleteObject(object)
	Utils.Blips.removeBlip(truck_blip)
	Utils.Blips.removeBlip(route_blip)
	exports['lc_utils']:notify("error",Utils.translate('vehicle_destroyed'))
	TriggerServerEvent("stores:failed")
end)

-----------------------------------------------------------------------------------------------------------------------------------------
-- createObjectAttachedToEntity
-----------------------------------------------------------------------------------------------------------------------------------------

function createObjectAttachedToEntity(dict,anim,prop,flag,hand)
	local ped = PlayerPedId()

	RequestModel(GetHashKey(prop))
	while not HasModelLoaded(GetHashKey(prop)) do
		Citizen.Wait(10)
	end

	RequestAnimDict(dict)
	while not HasAnimDictLoaded(dict) do
		Citizen.Wait(10)
	end

	TaskPlayAnim(ped,dict,anim,3.0,3.0,-1,flag,0,false,false,false)
	local coords = GetOffsetFromEntityInWorldCoords(ped,0.0,0.0,-5.0)
	local object = CreateObject(GetHashKey(prop),coords.x,coords.y,coords.z,true,true,true)
	SetEntityCollision(object,false,false)
	AttachEntityToEntity(object,ped,GetPedBoneIndex(ped,hand),0.0,0.0,0.0,0.0,0.0,0.0,false,false,false,false,2,true)
	return object
end

function deleteObject(object)
	if DoesEntityExist(object) and IsEntityAnObject(object) then
		Utils.Animations.stopPlayerAnim(true)
		SetEntityAsMissionEntity(object, false, true)
		DeleteObject(object)
    end
end

-----------------------------------------------------------------------------------------------------------------------------------------
-- createBlips
-----------------------------------------------------------------------------------------------------------------------------------------

local market_blips = {}

Citizen.CreateThread(function()
	Wait(5000)
	TriggerServerEvent("stores:getBlips")
end)

RegisterNetEvent('stores:setBlips')
AddEventHandler('stores:setBlips', function(blips_table)
	for k,v in pairs(Config.market_locations) do
		local x,y,z = table.unpack(v.map_blip_coord)
		local blips = Config.market_types[v.type].blips
		if blips_table[k] and blips_table[k].market_blip and blips_table[k].market_name and blips_table[k].market_color then
			market_blips[k] = Utils.Blips.createBlipForCoords(x,y,z,tonumber(blips_table[k].market_blip),tonumber(blips_table[k].market_color),blips_table[k].market_name,blips.scale)
		else
			market_blips[k] = Utils.Blips.createBlipForCoords(x,y,z,blips.id,blips.color,blips.name,blips.scale)
		end
	end
end)

RegisterNetEvent('stores:updateBlip')
AddEventHandler('stores:updateBlip', function(key,name,color,blip)
	Utils.Blips.removeBlip(market_blips[key])
	local x,y,z = table.unpack(Config.market_locations[key].map_blip_coord)
	local blips = Config.market_types[Config.market_locations[key].type].blips
	market_blips[key] = Utils.Blips.createBlipForCoords(x,y,z,tonumber(blip),tonumber(color),name,blips.scale)
end)

function canStartJob(market_id)
	local x,y,z = table.unpack(Config.market_locations[market_id]['garage_coord'])
	local isSpawnPointClear = Utils.Vehicles.isSpawnPointClear({['x']=x,['y']=y,['z']=z},5.001)
	if isSpawnPointClear == false then
		exports['lc_utils']:notify("error",Utils.translate('occupied_places'))
		return false
	end
	return true
end

RegisterNetEvent('stores:Notify')
AddEventHandler('stores:Notify', function(type,message)
	exports['lc_utils']:notify(type,message)
end)

Citizen.CreateThread(function()
	Wait(1000)
	SetNuiFocus(false,false)

	Utils.loadLanguageFile(Lang)

	for k, _ in pairs(Config.export_locations) do
		if Config.export_locations[k][4] then
			Config.export_locations[k][4] = nil
		end
	end
	for k, _ in pairs(Config.delivery_locations) do
		if Config.delivery_locations[k][4] then
			Config.delivery_locations[k][4] = nil
		end
	end

	if Utils.Config.custom_scripts_compatibility.target == "disabled" then
		createMarkersThread()
	else
		createTargetsThread()
	end
end)
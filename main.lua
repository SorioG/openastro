--OpenAstro by SorioG
FORCE_UPDATE = false
local sin = math.sin
local cos = math.cos
local random = math.random
local global_dt
local menu_ship_a = 0
local sock = require "lib.sock"
local bitser = require "lib.bitser"
local utf8 = require("utf8")
require "utils"
--ship parameters--
local ship_radius = 10
local ship_acc = 500
local ship_turnrate = 5
local ship_max_energy = 100
local ship_energy_per_shot = 25
local ship_energy_recharge = 50
local shield_max_power = 100
local shield_drain = 40
local ship_firerate = 500
--bullet parameters--
local bullet_speed = 100
local bullet_min_speed = 5000
local bullet_radius = 4
--rock parameters--
local rock_speed = 1
local large_rock_radius = 60
local medium_rock_radius = 30
local small_rock_radius = 15

local console = "nix"
local update_timer = 0 	 --increased in update(dt) by +dt
local time_to_update = 0.0 --if update_timer > time_to_update then update the physics, particles etc
local update_skip_count = 0 --how often updating was skipped until update_timer was big enough

local level = 0
local res_w = 800
local res_h = 600
local res
local show_debug = false
local play_sounds = true
local animated_background = false
local AIrange = {}

local sound_laser
local sound_rockexplode
local sound_newlevel
local sound_shipexplode
local sound_chat
local backgroundgfx_obj = {}	--x, y, size, grow
local bullets = {}
local walls = {}
local rocks = {}
local players = {} --key_shot  key_left  key_right  key_up  body  shape shield_power  ship_energy  lives  points 
				   --want_shot want_left want_right want_up joystick_nr p.button_left p.button_right p.button_up p.button_shot is_ai is_active

local game_status --MENU INGAME GAMEOVER CONTROLLCONFIG
local game_mode ="A" --"A": level, 3 lives per player  "B": continously spawn new rocks, lose points when ship explodes, and more.
local mini_font
local small_font
local large_font
local font
local ingame_messages = {} --lifetime text
local buttons = {} --x, y, w, h, text, name
local netbuttons = {}
local setbuttons = {}
local mouse_was_down = false --to recognize "button down then up" clicks
local game_name = "OpenAstro"
local game_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS") and true or false
local max_players = 12
local type_state = false
local CScreen = require "lib.cscreen"
MAX_FPS = 60 -- Server Only

TYPING = {
	host = "",
	port = "",
	username = "",
	chat = "",
}

SERVER = false --Netplay Server
DEDICATED = false --Netplay Dedicated/Headless Server
CLIENT = false --Netplay Client
IS_NETPLAY = false --Playing on a netplay session?

multihost = "127.0.0.1" -- Address of a Netplay Server
multiport = 9797 -- Port of a Netplay Server

FORCE_SERVER = false
NetClient = nil
NetServer = nil
MAX_BOTS = 0

for i,a in pairs(arg) do
    if a == "--dedicated" or a == "--headless" then
        DEDICATED = true
    end
	if a == "--server" or a == "--host" then
		if not DEDICATED then
        	FORCE_SERVER = true
		end
    end
	if a == "--connect" then
		NET_CONNECT = arg[i+1]
	end
	if (NET_CONNECT and not DEDICATED) or FORCE_SERVER then
		if a == "--port" then
			multiport = tonumber(arg[i+1])
		end
	end
	if DEDICATED then
		if a == "--port" then
			multiport = tonumber(arg[i+1])
		end
		if a == "--gamemode" then
			local g = arg[i+1]
			if g == "1" then
				game_mode = "A"
			elseif g == "2" then
				game_mode = "B"
			elseif g == "3" then
				game_mode = "C"
			elseif g == "4" then
				game_mode = "D"
			else
				print("[WARN] Invaild gamemode, Not changing.")
			end
		end
		if a == "--max-bots" then
			local g = tonumber(arg[i+1])
			if g > max_players then
				print("[WARN] Maximum of players reached for bots.")
				g = max_players
			end
			MAX_BOTS = g
		end
		if a == "--force-update" then
			FORCE_UPDATE = true
		end
		if a == "--max-fps" then
			MAX_FPS = tonumber(arg[i+1])
		end
	end
end

function save_data()
	local data = ""
	local fs
	local ps
	if FULLSCREEN then
		fs = "y"
	else
		fs = "n"
	end

	if play_sounds then
		ps = "y"
	else
		ps = "n"
	end

	data = data .. fs .. "~"
	data = data .. NET_USERNAME .. "~"
	data = data .. ps .. "~"

	love.filesystem.write("data.dat", data)
end

function load_data()
	if not love.filesystem.getInfo("data.dat") then return end
	if love.filesystem.getInfo("data.dat").type == "file" then
		local data = love.filesystem.read("data.dat")
		local s = data:split("~")
		FULLSCREEN = (s[1] == "y") and true or false
		NET_USERNAME = s[2]
		play_sounds = (s[3] == "y") and true or false
	end
end

function love.load(arg)
	load_data()
world = love.physics.newWorld(0, 0) --create a world for the bodies to exist in
--world:setGravity(0, 0)
--world:setMeter(64) --the height of a meter in this world will be 64px (removed in a latest love version)
world:setCallbacks(add_collide) --add_collide, add_collide, add_collide)


--[[
world:setContactFilter(function (a,b)
	local aData = a:getUserData()
	local bData = b:getUserData()


end)
]]
if not DEDICATED then
backgroundgfx_setup()
end
--	player = love.physics.newBody(world, 100, 100, 10, 5)
--	player:setBullet (true) --I MUST BECOME THE BULLET
for i=1,max_players do
add_player ()
end
if not DEDICATED then
love.window.setMode(res_w, res_h, {
	vsync = 1,
	resizable = true,
	fullscreen = FULLSCREEN,
})
love.window.setTitle(game_name)
--love.window.setFullscreen()
love.window.setIcon(love.image.newImageData("assets/icon.png"))
sound_laser = love.audio.newSource("assets/default/laser.wav", "static")
sound_rockexplode = love.audio.newSource("assets/default/explode.wav", "static")
sound_newlevel = love.audio.newSource("assets/default/newlevel.wav", "static")
sound_shipexplode = love.audio.newSource("assets/default/shipexplode.wav", "static")
sound_chat = love.audio.newSource("assets/default/chat.wav", "static")

mini_font = love.graphics.newFont( 15 )
small_font = love.graphics.newFont( 20 )
large_font = love.graphics.newFont( 30 )
font = love.graphics.newFont( 1.0 )
CScreen.init(res_w, res_h, true)
else
	sound_laser = "LASER"
	sound_rockexplode = "ROCKEXPLODE"
	sound_newlevel = "NEWLEVEL"
	sound_shipexplode = "SHIPEXPLODE"
	sound_chat = "CHAT"
	play_sounds = false
end
------menu buttons
add_button (buttons, res_w/2-220, res_h/4+30, 400, 20, "Start Game", "button_newgame")
add_button (buttons, res_w/2-220, res_h/4+130, 400, 20, "Gamemode: Levels" , "button_gamemode")
add_button (buttons, res_w/2-220, res_h/4+160, 400, 20, "Sound: on", "button_sound")
local px, py = 340, 190
for i=1,max_players do
--add_button (buttons, res_w/2-220, res_h/4+190, 40, 20, "", i)
add_button (buttons, res_w/2-px, res_h/4+py, 40, 20, "", i)
--add_button (buttons, res_w/2-220, res_h/4+240, 40, 20, "", 2)
--add_button (buttons, res_w/2-220, res_h/4+290, 40, 20, "", 3)
--add_button (buttons, res_w/2-220, res_h/4+340, 40, 20, "", 4)
py = py + 50
if py > 340 then
	py = 190
	px = px - 280
end
end
add_button (buttons, res_w-100, res_h-40, 90, 20, "Quit", "button_quit")
add_button (buttons, 50, res_h-40, 350, 20, "Animated Background: Off", "button_background")
add_button (buttons, res_w-100, res_h-80, 90, 20, "Netplay", "button_netplay")
add_button (buttons, res_w-250, res_h-40, 100, 20, "Settings", "button_settings")
--add_button love.graphics.print("press n for a new game.", res_w/2-300, res_h/4+100)

game_status = "MENU"

add_button (setbuttons, res_w/2-220, res_h/4+30, 400, 20, "Fullscreen: off", "set_fullscreen")
add_button (setbuttons, res_w/2-220, res_h/4+60, 400, 20, "Netplay Username: "..NET_USERNAME, "set_netplay")
add_button (setbuttons, res_w-100, res_h-40, 90, 20, "Back", "set_back")

add_button (netbuttons, res_w/2-220, res_h/4+30, 400, 20, "Host: 127.0.0.1", "net_address")
add_button (netbuttons, res_w/2-220, res_h/4+60, 400, 20, "Port: 9797", "net_port")
add_button (netbuttons, res_w/2-220, res_h/4+200, 400, 20, "New Server", "net_host")
add_button (netbuttons, res_w/2-220, res_h/4+220, 400, 20, "Join Server", "net_join")
add_button (netbuttons, res_w-100, res_h-40, 90, 20, "Back", "net_back")

if not DEDICATED then
--Particle system:
particle_gfx_rock_explosion = love.graphics.newImage("assets/explosion_particle.png");
ps_rock_explosion = love.graphics.newParticleSystem(particle_gfx_rock_explosion, 1000)
ps_rock_explosion:setEmissionRate(100)
ps_rock_explosion:setSpeed(300, 300)
--ps_rock_explosion:setGravity(0, 0)
ps_rock_explosion:setSizes(1, 1)
ps_rock_explosion:setColors(200, 255, 255, 255,   0, 55, 0, 200)  -- r1, g1, b1, a1, r2, g2, b2, a2 )
ps_rock_explosion:setPosition(400, 300)
ps_rock_explosion:setEmitterLifetime(0.1)
ps_rock_explosion:setParticleLifetime(0.5)
ps_rock_explosion:setDirection(360)
ps_rock_explosion:setSpread(20)
ps_rock_explosion:stop()

particle_gfx_ship_explosion = love.graphics.newImage("assets/explosion_particle_ship.png");
ps_ship_explosion = love.graphics.newParticleSystem(particle_gfx_ship_explosion, 100)
ps_ship_explosion:setEmissionRate(60)
ps_ship_explosion:setSpeed(20, 100)
ps_ship_explosion:setDirection(360)
--ps_ship_explosion:setGravity(0, 0)
ps_ship_explosion:setSizes(0.4, 0.4)
--ps_ship_explosion:setColor(0, 255, 200, 255,   0, 255, 0, 0)  -- r1, g1, b1, a1, r2, g2, b2, a2 )
ps_ship_explosion:setColors(255, 255, 200, 255,   0, 0, 0, 0)  -- r1, g1, b1, a1, r2, g2, b2, a2 )
ps_ship_explosion:setPosition(400, 300)
ps_ship_explosion:setEmitterLifetime(0.1)
ps_ship_explosion:setParticleLifetime(3)
ps_ship_explosion:setSpin(-10, 10)
ps_ship_explosion:setSpread(20)
ps_ship_explosion:stop()

particle_gfx_ship_exhaust = love.graphics.newImage("assets/exhaust_particle.png");
ps_ship_exhaust = love.graphics.newParticleSystem(particle_gfx_ship_exhaust, 1000)
ps_ship_exhaust:setEmissionRate(20)
ps_ship_exhaust:setSpeed(150, 200)
ps_ship_exhaust:setDirection(360)
--ps_ship_exhaust:setGravity(0, 0)
ps_ship_exhaust:setSizes(0.4, 0.4)
ps_ship_exhaust:setColors(200, 255, 200, 220,   0, 150, 0, 200)  -- r1, g1, b1, a1, r2, g2, b2, a2 )
ps_ship_exhaust:setPosition(400, 300)
ps_ship_exhaust:setEmitterLifetime(0.1)
ps_ship_exhaust:setParticleLifetime(0.5)
ps_ship_exhaust:setSpin(-10, 10)
ps_ship_exhaust:setSpread(.3)
ps_ship_exhaust:stop()

particle_gfx_backgroundgfx = love.graphics.newImage("assets/back_particle.png")

ps_backgroundgfx = love.graphics.newParticleSystem(particle_gfx_backgroundgfx, 1000)

ps_backgroundgfx:setEmissionRate(20)
ps_backgroundgfx:setSpeed(200, 400)
ps_backgroundgfx:setSizes(1, 2)
ps_backgroundgfx:setColors(0, 0, 0, 200,  0, 255, 255, 200)
ps_backgroundgfx:setPosition(res_w/2, res_h/2)
ps_backgroundgfx:setEmitterLifetime (0.1)
ps_backgroundgfx:setParticleLifetime(1.5)
ps_backgroundgfx:setDirection(0)
ps_backgroundgfx:setSpread(360)
ps_backgroundgfx:setSpin(-5, 5)
ps_backgroundgfx:setTangentialAcceleration(-800)
ps_backgroundgfx:setRadialAcceleration(-8)
end

if DEDICATED then
	print ("-------- OpenAstro Dedicated Server --------")
	print ("Initializing the netplay server...")
	InitServer("*", multiport)
	if MAX_BOTS > 0 then
		print ("Activating and changing players to AIs...")
		for i=1,MAX_BOTS do
			local p = players[i]
			p.is_active = true
			p.is_ai = true
		end
	end
	new_game()
	print ("Game started!")
end

if FORCE_SERVER and not NET_CONNECT then
	if not NetServer then
		InitServer("*", multiport)
		game_status = "LOBBY"
		InitClient("localhost", multiport)
	end
end

if NET_CONNECT and not DEDICATED then
	InitClient(NET_CONNECT, multiport)
	game_status = "NETPLAY_CONNECTING"
end
end


function new_game ()
for i,p in ipairs(players) do
	p.b:setPosition (res_w/2,res_h/2)
	p.b:setLinearVelocity (0,0)
	p.b:setAngle (0)
	p.points = 0
	if (p.is_ai) then p.lives = 6 else p.lives = 3 end
	p.shield_power = shield_max_power
	if p.is_active then p.playstatus = "INGAME" else p.playstatus = "DEAD" end
	end
rocks = {}
bullets = {}
walls = {}
shield_power = shield_max_power
game_status = "INGAME"
if SERVER then
	ServerSend({
		type = "gameinfo",
		status = "INGAME",
	})
end
--players[1].playstatus = "INGAME"
level = 1
PVP_ROUND = 1
new_level()
ingame_messages = {}
if IS_NETPLAY then
	if SERVER then
if (game_mode == "B") then add_ingame_message ("Get 1000 Points to win!") end
if (game_mode == "A" or game_mode == "C") then add_ingame_message ("Incoming Space Rocks!") end
if (game_mode == "D") then add_ingame_message ("Round 1") end
	end
else
	if (game_mode == "B") then add_ingame_message ("Get 1000 Points to win!") end
	if (game_mode == "A" or game_mode == "C") then add_ingame_message ("Incoming Space Rocks!") end
	if (game_mode == "D") then add_ingame_message ("Round 1") end
end
if FULLSCREEN then
	--Make sure the mouse is invisible while in fullscreen.
	love.mouse.setVisible(false)
end
end

function new_ship (pres)
pres.b:setPosition (math.random(res_w), math.random(res_h))--(res_w/2,res_h/2)
pres.b:setLinearVelocity (0,0)
pres.b:setAngle (0)
pres.is_active = true
--lives = lives -1
pres.status="SHIP"
pres.destroyed_by = nil
pres.shield_power = shield_max_power
pres.ship_energy = ship_max_energy
pres.playstatus = "INGAME"
pres.gun_blocktime = 0
end

function love.draw()
--love.graphics.setColorMode("modulate")
CScreen.apply()
love.graphics.setBlendMode("alpha")
if (game_status == "MENU" or game_status == "GAMEOVER" or game_status == "SETTINGS" or game_status == "LOBBY" or game_status == "NETPLAY") then draw_menu () end
	if (show_debug == true) then
		love.graphics.setColor(255, 0, 255, 255)
		font:setLineHeight (1.0)
		love.graphics.setFont( mini_font )
		love.graphics.print("#bullets:" .. #bullets, 200, 200)
		love.graphics.print("#rocks:" .. #rocks, 200, 210)		
		love.graphics.print("game_status:" .. game_status, 10, 50)	
		love.graphics.print("level:" ..level, 10, 60)
		love.graphics.print("press F10 to toggle this debug info", 10, 70)
		love.graphics.print("#players:" .. #players, 10, 80)
		love.graphics.print("Melder:" .. console, 10, 400)
		love.graphics.print("world:getbodyCount:" .. world:getBodyCount(), 300, 100)
		love.graphics.print("update_timer" .. update_timer, 10, 110)
		for i,p in ipairs(players) do
			love.graphics.print(p.gun_blocktime,  p.b:getX(), p.b:getY()+ship_radius*2)
			love.graphics.print("playstatus=" .. p.playstatus .. " energy=" .. math.floor(p.ship_energy) .. " shield" .. math.floor(p.shield_power) .. "Pos:" .. math.floor(p.b:getX()) .. ":" 
			 .. math.floor(p.b:getY()) .. "gun_blocktime:" .. p.gun_blocktime,  50, 120+i*12)
			if (p.is_ai==true and p.is_active==true) then --show ai ranges
				love.graphics.circle ("line", p.b:getX(), p.b:getY(), AIrange.runaway)
				love.graphics.circle ("line", p.b:getX(), p.b:getY(), AIrange.moveaway)
				love.graphics.circle ("line", p.b:getX(), p.b:getY(), AIrange.engage)
				end
				
			
			end

		local bodies = world:getBodies()
		for i,p in pairs(bodies) do
			local size = 10
			if (p:getFixtures()[1]) then
				local shape = p:getFixtures()[1]:getShape()
				if shape then
					size = shape:getRadius() or 10
				end
			end
			love.graphics.circle ("line", p:getX(), p:getY(), size)
		end
		end

if (game_status == "INGAME" or game_status =="RESPAWN" ) then draw_ingame () end

love.graphics.setBlendMode("add")
love.graphics.setColor(1,1,1)
love.graphics.draw(ps_ship_explosion, 0, 0)
love.graphics.draw(ps_rock_explosion, 0, 0)
love.graphics.draw(ps_ship_exhaust, 0, 0)

love.graphics.setBlendMode("alpha")
if IS_NETPLAY then
	local cx, cy = 50, res_h-100
	love.graphics.setColor(1,1,1)
	for i=#CHAT_LOGS, 1, -1 do
		local c = CHAT_LOGS[i]
		love.graphics.setFont(mini_font)
		love.graphics.print(c.msg, cx, cy)
		cy = cy - 30
	end
	if type_state == "CHAT" then
		love.graphics.setFont(mini_font)
		love.graphics.print("Chat: " .. TYPING.chat .. "|", 50, res_h-80)
	end
end
CScreen.cease()
end
PAUSED = false
function draw_ingame ()
--backgroundgfx_draw ()
if (animated_background) then love.graphics.draw(ps_backgroundgfx, 0, 0) end
love.graphics.setColor(0, 255, 255, 255)
draw_walls ()
draw_bullets ()
draw_rocks ()
show_ingame_messages ()
--draw players--
	love.graphics.setFont(large_font)
	if (game_status == "INGAME") then
	for i,p in ipairs(players) do
			if (p.is_active == true) then
			set_player_color (i)
	--		if (p.playstatus == "INGAME") then draw_ship (p.b:getX(), p.b:getY(), p.player_a, p.shield_power) end
			draw_ship (p.b:getX(), p.b:getY(), p.b:getAngle(), p.shield_power)
			love.graphics.printf(p.name, small_font, p.b:getX()+20, p.b:getY()+20, 400)
			local dx = ((i-1) * 200)
			local dy = res_h-30
			if (i > 4) then
				dx = ((i-5) * 200)
				dy = 30
			end
			if (i > 8) then
				dx = 0
				dy = ((i-8) * 200)+50
			end
			if (i > 10) then
				dx = res_w-200
				dy = ((i-10) * 200)+50
			end
			love.graphics.print("Score:"..p.points, dx, dy)
			--lives display
			if (game_mode == "A") then
				if (p.lives > 0) then
					for bla = 1, p.lives, 1 do
						draw_ship (dx+bla*ship_radius*1.8, dy-20,0)
						end
					end
				end
			end
		end
	end
	if PAUSED then
		love.graphics.setColor(1,1,1)
		love.graphics.printf("PAUSED",0,(res_h/2),res_w,"center")
	end
end

function love.resize(width, height)
	CScreen.update(width, height)
end
--COLLIDED = false
function add_collide (a, b, coll)
	if IS_NETPLAY and not SERVER then return end
local cx, cy
--ps_rock_explosion:setPosition(cx,cy)
--ps_rock_explosion:start()
--print(a,b,coll)
if (a == nil or b == nil) then return end
local a_status
local b_status
local aData = a:getUserData()
local bData = b:getUserData()
a_status = aData.status
b_status = bData.status 
--console = a.status .. " " .. b.status
if (a_status == b_status) then return end
--ship vs bullet - bullet explodes
if (game_mode ~= "D") then
	if (a_status == "SHIP" and b_status == "BULLET") then b_status = "HIT" end
	if (a_status == "BULLET" and b_status == "SHIP") then a_status = "HIT" end
end
-- rock vs bullet - both explodes
if (a_status == "BULLET" and b_status == "ROCK") then a_status = "HIT" b_status = "HIT" bData.destroyed_by = aData.owner end
if (a_status == "ROCK" and b_status == "BULLET") then a_status = "HIT" b_status = "HIT" aData.destroyed_by = bData.owner end
--rock vs ship - ship explodes
if (a_status == "ROCK" and b_status == "SHIP") then if (bData.shield_power < 1) then b_status = "HIT" end end
if (a_status == "SHIP" and b_status == "ROCK") then if (aData.shield_power < 1) then a_status = "HIT" end end
--ship vs bullet - only on pvp gamemode (both explodes)
if (game_mode == "D") then
	if (a_status == "SHIP" and b_status == "BULLET") then a_status = "HIT" b_status = "HIT" aData.destroyed_by = bData.owner end
	if (a_status == "BULLET" and b_status == "SHIP") then b_status = "HIT" a_status = "HIT" bData.destroyed_by = aData.owner end
end
aData.status = a_status
bData.status = b_status
--collision()
--COLLIDED = true
end



function collision()
--players
for i,p in ipairs(players) do
	--screen edges
	if (p.b:getX() < -ship_radius/2) then p.b:setX (res_w+ship_radius/2) end
	if (p.b:getX() > res_w+ship_radius/2) then p.b:setX (-ship_radius/2) end
	if (p.b:getY() < -ship_radius/2) then p.b:setY (res_h+ship_radius/2) end
	if (p.b:getY() > res_h+ship_radius/2) then p.b:setY (-ship_radius/2) end
	if (p.playstatus == "RESPAWN" or p.playstatus == "DEAD") then
		p.b:setX(-666) p.b:setY(-666) --so no rocks hit the hidden dead ship
		p.b:setLinearVelocity (0,0)
	end
	if (p.playstatus == "INGAME" and p.status == "HIT" and p.shield_power < 1) then
		if not DEDICATED then
			ps_ship_explosion:setPosition(p.b:getX(),p.b:getY())
			ps_ship_explosion:start()
		end
		if SERVER then
			ServerSend({
				type = "particle",
				ptype = "shipexplode",
				x = p.b:getX(),
				y = p.b:getY(),
			})
		end
			p.b:setX(-666) p.b:setY(-666) --so no rocks hit the hidden dead ships
			p.b:setLinearVelocity (0,0)
			p.status = "SHIP"
			if (game_mode == "A") then
				if (p.lives > 0) then p.lives = p.lives - 1 p.playstatus = "RESPAWN" else p.playstatus = "DEAD" end
			end
				if (game_mode == "D") then
						
					p.playstatus = "DEAD"
					if (p.destroyed_by and p.destroyed_by ~= p) then
						--p.lives = 0
						
						p.destroyed_by.points = p.destroyed_by.points+30
						--p.points = math.floor(p.points / 2)
						--if (p.points < 0) then p.points = 0 end
					end
					p.destroyed_by = nil
				end
			if (game_mode == "B" or game_mode == "C") then
				p.points = math.floor (p.points / 2)  p.playstatus = "RESPAWN"
				if (p.points < 0) then p.points = 0 end
			end
			play_sound (sound_shipexplode)			
		end
	end

--rocks
local rock_delete_count = 0
for u,r in ipairs(rocks) do	
	if not r.b:isDestroyed() then
	local rx = r.b:getX()
	local ry = r.b:getY()
	local rr = r.s:getRadius()		
	if (rx < -rr) then rx = res_w+rr r.b:setPosition (rx,ry) end
	if (rx > res_w+rr) then rx = -rr r.b:setPosition (rx,ry) end
	if (ry < -rr) then ry = res_h+rr r.b:setPosition (rx,ry) end
	if (ry > res_h+rr) then ry = -rr r.b:setPosition (rx,ry) end
	
	if (r.status == "HIT") then
		if (game_mode ~= "D") then
			if (r.destroyed_by.points~=nil) then r.destroyed_by.points = r.destroyed_by.points + r.size*15 end	
		end			
		local new_size = r.size - 1
		local nrx,nry = r.b:getX(), r.b:getY()	
		r.status = "DELETE"
		rock_delete_count = rock_delete_count + 1
		--		table.remove (rocks, u)
		if (new_size == 1) then
			add_rock (1, nrx, nry)
			add_rock (1, nrx,nry)
			end
		if (new_size == 2) then
			add_rock (2, nrx,nry)
			add_rock (2, nrx,nry)
			end
		--table.insert (rocks_to_delete, u)
		--table.remove(bullets, i)
		if not DEDICATED then
		ps_rock_explosion:setPosition(rx,ry)  
		ps_rock_explosion:start()		
		end		
		if SERVER then
			ServerSend({
				type = "particle",
				ptype = "rockexplode",
				x = rx,
				y = ry,
			})
		end
		play_sound(sound_rockexplode)		
		end
	end
	end
	
	
for i = #rocks, 1, -1 do
	if rocks[i] then
	if (rocks[i].status =="DELETE") then
	rocks[i].b:setX(-555) rocks[i].b:setY(-555)
	rocks[i].b:setLinearVelocity (0,0)	
	rocks[i].b:destroy()
	--rocks[i] = nil
	if SERVER then
		ServerSend({
			type = "rockdelete",
			index = i,
		})
	end
	table.remove(rocks, i)
end
end
end

	--[[
for bla = 1, rock_delete_count, 1 do
	for u,r in ipairs(rocks) do	
	if (r.status == "DELETE") then 
	r.b:setX(-555) r.b:setY(-555) --get the fuck away from me
	r.b:setLinearVelocity (0,0)	
	table.remove (rocks, u) 
		rock_delete_count = rock_delete_count - 1 
		break 
		end
	end
	end	]]
	--------------
	--table.remove (rocks, rocks_to_delete)
--bullets
local bullet_delete_count = 0
	for i,v in ipairs(bullets) do
--		if (is_offscreen (v.b:getX(), v.b:getY()) == true) then table.remove(bullets, i) end --remove bullets outside of screen	
		--if (v.status=="HIT") then table.remove(bullets, i) end --remove bullets that hit things	
		if not v.b:isDestroyed() then
		local xs, ys = v.b:getLinearVelocity()		
		if ((xs*xs) + (ys*ys) < bullet_min_speed or v.status=="HIT" or is_offscreen (v.b:getX(), v.b:getY()) == true) then 
		bullet_delete_count = bullet_delete_count +1
		v.status = "DELETE"
		end
	end
		end

for i = #bullets, 1, -1 do
	if bullets[i] then
	if (bullets[i].status =="DELETE") then
	bullets[i].b:setX(-555) bullets[i].b:setY(-555) 
	bullets[i].b:setLinearVelocity (0,0)
		 bullets[i].b:destroy()
		 if SERVER then
			ServerSend({
				type = "bulletdelete",
				index = i,
			})
		end
		table.remove(bullets, i)
	end
end
end		


		
--[[
	for bla = 1, bullet_delete_count, 1 do
	for i,v in ipairs(bullets) do	
		if (v.status == "DELETE") then 
			v.b:setX(-555) v.b:setY(-555) 
			v.b:setLinearVelocity (0,0)				
			--v.b:destroy()
--			v.s = nil
			table.remove (bullets, i) 
			bullet_delete_count = bullet_delete_count - 1 
			break 
			end
		end
	end	-]]
	--------------

	
end


function is_offscreen (x,y)
if (x < 0) then return true end
if (y < 0) then return true end 
if (x > res_w) then return true end 
if (y > res_h) then return true end
return false
end

function is_far_offscreen (x,y)
if (x < -res_w/2) then return true end
if (y < -res/2) then return true end
if (x > res_w*1.5) then return true end
if (y > res_h*1.5) then return true end
return false
end

function is_almost_offscreen (x,y)
if (x < res_w*0.1) then return true end
if (y < res_h*0.1) then return true end 
if (x > res_w*0.9) then return true end 
if (y > res_h*0.9) then return true end
return false
end

local old_game_status
function love.update(dt)
global_dt = dt
menu_ship_a = menu_ship_a+ship_turnrate*dt
--------------------------------------------------------------------
----------------------------   INGAME   ----------------------------
--------------------------------------------------------------------
if (game_status == "INGAME") and not PAUSED then 
	backgroundgfx_animate (dt)
	timeout_ingame_messages (dt)
	for i,p in ipairs(players) do
		if IS_NETPLAY and not DEDICATED then
			if CLIENT and not SERVER then break end
		end
		if p.is_client then
			p.want_left = p.net_left
			p.want_right = p.net_right
			p.want_up = p.net_up
			p.want_shot = p.net_shot
		end
		if (p.playstatus == "RESPAWN" and p.is_ai) then new_ship (p) end
		if (p.playstatus == "RESPAWN" and not p.is_ai and p.want_shot) then new_ship (p) end
		if (p.playstatus == "INGAME") then
			if (p.is_ai) then
			local ai_l, ai_r, ai_u, ai_s = shipAI_getdecision (p)
			p.want_left = ai_l
			p.want_right = ai_r
			p.want_up = ai_u
			p.want_shot = ai_s
			end
			
			if (not p.is_ai) and not IS_NETPLAY then
				local joystick = love.joystick.getJoysticks()[p.joystick_nr]
		if (not joystick) then
			----keyboard controls -----
			if love.keyboard.isDown(p.key_left) then p.want_left = true end
			if love.keyboard.isDown(p.key_right) then p.want_right = true end
			if love.keyboard.isDown(p.key_up) then p.want_up = true end
			if love.keyboard.isDown(p.key_shot) and p.gun_blocktime < 1 then p.want_shot = true end
		else
			if (joystick.isDown(p.button_left )) then p.want_left=true end
			if (joystick.isDown(p.button_right )) then p.want_right=true end
			if (joystick.isDown(p.button_up )) then p.want_up=true end
			if (joystick.isDown(p.button_shot)) then p.want_shot=true end
		end
	end
		
		----ship movement physics----
		local old_a = p.b:getAngle()
		p.b:setAngularVelocity (0)
		if (p.want_left)  then p.b:setAngle (old_a + (ship_turnrate*dt)) p.want_left = false end
		if (p.want_right) then p.b:setAngle (old_a - (ship_turnrate*dt)) p.want_right = false end
		--if (p.b:getAngle() >  math.pi*2) then p.b:setAngle(math.pi*2-p.b:getAngle() ) end
		--if (p.b:getAngle() <  0) then p.b:setAngle(math.pi*2-p.b:getAngle() ) end
		
		if (p.want_up) then 
			local thrust_fx = -sin(p.b:getAngle()) *  ship_acc
			local thrust_fy = -cos(p.b:getAngle()) *  ship_acc
			p.b:applyForce (thrust_fx, thrust_fy)
			if not DEDICATED then
			ps_ship_exhaust:setPosition (p.b:getX()+ sin(p.b:getAngle())*ship_radius/2, p.b:getY()+cos(p.b:getAngle())*ship_radius/2)
			ps_ship_exhaust:setDirection(-p.b:getAngle()+(3.14/2))
			ps_ship_exhaust:start()		
			end
			if SERVER then
				ServerSend({
					type = "particle",
					ptype = "shipexhaust",
					index = i,
				})
			end
			p.want_up = false
			end

		if CLIENT and p.is_moving then
			ps_ship_exhaust:setPosition (p.b:getX()+ sin(p.b:getAngle())*ship_radius/2, p.b:getY()+cos(p.b:getAngle())*ship_radius/2)
			ps_ship_exhaust:setDirection(-p.b:getAngle()+(3.14/2))
			ps_ship_exhaust:start()	
		end
		----- ship shoots -----
		if (p.want_shot == true and p.ship_energy > ship_energy_per_shot and p.shield_power < 1 and p.gun_blocktime < 1) then
				p.gun_blocktime = 100
				shoot_bullet (p.b:getX()  -sin(p.b:getAngle()) *ship_radius*1.5, p.b:getY()-cos(p.b:getAngle()) *ship_radius*1.5, p.b:getAngle(), p)
				p.ship_energy = p.ship_energy - ship_energy_per_shot
				p.want_shot = false
				end
		p.want_shot = false
		end
		---- stuff recharges ----
		if (p.ship_energy < ship_max_energy) then p.ship_energy = p.ship_energy + ship_energy_recharge * dt end  --energy recharges over time
		if (p.shield_power > 0) then p.shield_power = p.shield_power - shield_drain * dt end					--shield power goes down over time			
		if (p.gun_blocktime > 0) then p.gun_blocktime = p.gun_blocktime - ship_firerate *dt end
		end	
	if ((game_mode == "A" or game_mode == "C") and #rocks == 0) then new_level () end
	if ((game_mode == "B" or game_mode == "D") and #rocks < 5) then add_rock (3) end	
	end
	
--hackish jostick controlls
--if (joystick.isDown( 1 )) then players[1].want_left=true end
--if (joystick.isDown( 2 )) then players[1].want_right=true end
--if (joystick.isDown( 3 )) then players[1].want_up=true end
--if (joystick.isDown( 4)) then players[1].want_shot=true end
--[[
if (old_game_status == "MENU" or old_game_status == "GAMEOVER") and game_status == "INGAME" then
	ps_ship_exhaust:reset()
	ps_rock_explosion:reset()
	ps_ship_explosion:reset()
	ps_backgroundgfx:reset()
end

if (old_game_status == "INGAME") and game_status == "MENU" or game_status == "GAMEOVER" then
	ps_ship_exhaust:reset()
	ps_rock_explosion:reset()
	ps_ship_explosion:reset()
	ps_backgroundgfx:reset()
end]]
	if not PAUSED then
		update_timer = update_timer + dt
--console = update_skip_count
if (update_timer > time_to_update) then	
	if game_status == "INGAME" then
	world:update(update_timer)
	end
	if not world:isLocked() then collision() end
	if not DEDICATED then
	ps_rock_explosion:update(update_timer)
	ps_ship_explosion:update(update_timer)
	ps_ship_exhaust:update(update_timer)
	if (game_status=="INGAME" and animated_background) then ps_backgroundgfx:start() ps_backgroundgfx:update(update_timer) end
	end
	update_timer = 0
	update_skip_count = 0
end
update_skip_count = update_skip_count +1
end
local players_ingame = 0 
if DEDICATED and not FORCE_UPDATE then
	for i,p in ipairs(players) do
		if (p.is_client==true) then players_ingame = players_ingame + 1 end
	end

	if players_ingame < 1 then
		if not PAUSED then
			print("Nobody is playing on this server, pausing the game...")
		end
		PAUSED = true
	else
		if PAUSED then
			print("One or more players are playing, unpausing the game...")
			--new_game()
		end
		PAUSED = false
	end
end
----end game conditions----
if (game_status == "INGAME") and not PAUSED then
	
	if (game_mode == "B") then
		for i,p in ipairs(players) do
		if (p.points > 1000) then game_status = "GAMEOVER" end
		end
	end
	players_ingame = 0 
	if (game_mode == "A") then
		for i,p in ipairs(players) do
			if (p.lives > 0 and p.is_active==true) then players_ingame = players_ingame + 1 end
		end
		if (players_ingame == 0) then game_status = "GAMEOVER" end
	end
	if (game_mode == "D") then
		for i,p in ipairs(players) do
			if (p.playstatus == "INGAME" and p.is_active==true) then players_ingame = players_ingame + 1 end
		end
		if (players_ingame <= 1) then 
			--rocks = {}
			for i,p in ipairs(players) do
				if (p.is_active==true) then 
					--p.lives = 1
					new_ship(p)
				end
			end
			PVP_ROUND = PVP_ROUND + 1
			add_ingame_message("Round " .. tostring(PVP_ROUND))
			for i,v in ipairs(rocks) do
				v.b:destroy()
				if SERVER then
					ServerSend({
						type = "rockdelete",
						index = i
					})
				end
			end
			for i,v in ipairs(bullets) do
				v.b:destroy()
				if SERVER then
					ServerSend({
						type = "bulletdelete",
						index = i
					})
				end
			end
			rocks = {}
			bullets = {}
		end
	end

	
end
if old_game_status ~= game_status then
	old_game_status = game_status
	if SERVER then
		ServerSend({
			type = "gameinfo",
			status = game_status,
			mode = game_mode,
		})
	end
end
--------------------------------------------------------------------
----------------------------   MENU --------------------------------
--------------------------------------------------------------------
if (game_status == "MENU" or game_status == "GAMEOVER" or game_status == "LOBBY") then
	PAUSED = false
	if not DEDICATED then love.mouse.setVisible(true) end
	for i,v in ipairs(rocks) do
		if not v.b:isDestroyed() then
		v.b:destroy()
		end
		--[[
		if SERVER then
			ServerSend({
				type = "rockdelete",
				index = i,
			})
		end]]
	end
	for i,v in ipairs(bullets) do
		if not v.b:isDestroyed() then
		v.b:destroy()
		end
		--[[
		if SERVER then
			ServerSend({
				type = "bulletdelete",
				index = i,
			})
		end]]
	end
	rocks = {}
	bullets = {}
	for i=1,#buttons do
		local b = buttons[i]
		if b.name == "button_newgame" then
			if CLIENT and not SERVER then
				b.text = "Ready!"
			else
				b.text = "Start Game"
			end
		end

		if b.name == "button_sound" then
			local sound_s = "off"
			if (play_sounds==true) then sound_s = "on" end
			b.text = "Sound: " .. sound_s
		end

		if b.name == "button_quit" then
			if CLIENT then
				b.text = "Leave"
			else
				b.text = "Quit"
			end
		end
		if b.name == "button_gamemode" then
			local gamemode_displayname = "Unknown"
			if (game_mode=="A") then gamemode_displayname = "Levels" end
			if (game_mode=="B") then gamemode_displayname = "Master Blaster" end
			if (game_mode=="C") then gamemode_displayname = "Endless" end
			if (game_mode=="D") then gamemode_displayname = "Player vs Player" end
			b.text = "Gamemode: " .. gamemode_displayname
		end

	end
	local clicked_button_name, clicked_button_i = clicked_button (buttons)
	if (clicked_button_name == "button_gamemode") then  --button: game mode
		local change = true
		if CLIENT and not SERVER then return end
		if (change and game_mode == "A") then game_mode ="B" change=false end
		if (change and game_mode == "B") then game_mode ="C" change=false end
		if (change and game_mode == "C") then game_mode ="D" change=false end
		if (change and game_mode == "D") then game_mode ="A" change=false end
		
		play_sound(sound_laser)

		if not change then
			if SERVER then
				ServerSend({
					type = "gameinfo",
					status = game_status,
					mode = game_mode,
				})
			end
		end
		end
	if (clicked_button_name == "button_newgame") then 
		if IS_NETPLAY then
			if SERVER then
				new_game()
			else
					ClientSend({
						type = "set_ready",
					})
			end
		else
			new_game()
		end
		
	end
	if (clicked_button_name == "button_sound") then
		local change = true
		if (play_sounds == true) then play_sounds = false change=false end
		if (change and play_sounds == false) then play_sounds = true end
		local sound_s = "off"
		if (play_sounds==true) then sound_s = "on" end
		buttons [clicked_button_i].text = "Sound: " .. sound_s
		play_sound(sound_laser)
		end
	for z,v in ipairs(players) do
		if (clicked_button_name == v.id) then
			if not CLIENT or not SERVER then
				local i = clicked_button_name
				if not (z > 4) then
					v.is_ai = v.is_active and not v.is_ai
					v.is_active = v.is_ai or not v.is_active
				else
					v.is_active = not v.is_active
					v.is_ai = v.is_active
				end
				play_sound(sound_laser)
			end
		end
	end
	if (clicked_button_name == "button_quit") then 
		if CLIENT then
			StopClient()

			if SERVER then
				StopServer()
			end

			game_status = "MENU"
			play_sound(sound_laser)

			if NET_CONNECT then
				love.event.quit()
			end
		else
			love.event.quit() 
		end
	end
	if (clicked_button_name == "button_settings") then 
		if CLIENT then return end
		game_status = "SETTINGS"
		play_sound(sound_laser)
	end
	if (clicked_button_name == "button_netplay") then 
		if CLIENT then return end
		game_status = "NETPLAY"
		play_sound(sound_laser)
	end
	if (clicked_button_name == "button_background") then 
		animated_background = true and not animated_background
		local back_s = "Animated Background: Off"
		if (animated_background) then back_s = "Animated Background: On" end
		buttons [clicked_button_i].text = back_s
		play_sound(sound_laser)
		end
	elseif game_status == "SETTINGS" then
		local clicked_button, clicked_button_i = clicked_button(setbuttons)
		for i=1,#setbuttons do
			local b = setbuttons[i]
			if b.name == "set_netplay" then
				b.text = "Netplay Username: "
				if type_state == "USERNAME" then
					b.text = b.text .. TYPING.username .. "|"
				else
					b.text = b.text .. NET_USERNAME
				end
			end
			if b.name == "set_fullscreen" then
				local fs_s = "Fullscreen: off"
				if (FULLSCREEN) then fs_s = "Fullscreen: on" end
				b.text = fs_s
			end
		end
		if not type_state then
		if (clicked_button == "set_fullscreen") then
			FULLSCREEN = not FULLSCREEN
			local fs_s = "Fullscreen: off"
			if (FULLSCREEN) then fs_s = "Fullscreen: on" end
			setbuttons [clicked_button_i].text = fs_s
			play_sound(sound_laser)
		end
		if (clicked_button == "set_back") then
			play_sound(sound_laser)
			love.window.setFullscreen(FULLSCREEN, "exclusive")
			game_status = "MENU"
		end
		if (clicked_button == "set_netplay") then
			play_sound(sound_laser)
			type_state = "USERNAME"
			TYPING.username = NET_USERNAME
		end
	end
	elseif game_status == "NETPLAY" then
		local clicked_button, clicked_button_i = clicked_button(netbuttons)
		for i=1,#netbuttons do
			local b = netbuttons[i]
			if b.name == "net_address" then
				b.text = "Host: "
				if type_state == "HOST" then
					b.text = b.text .. TYPING.host .. "|"
				else
					b.text = b.text .. multihost
				end
			end
			if b.name == "net_port" then
				b.text = "Port: "
				if type_state == "PORT" then
					b.text = b.text .. TYPING.port .. "|"
				else
					b.text = b.text .. multiport
				end
			end

		end
		if not type_state then
			if (clicked_button == "net_back") then
				play_sound(sound_laser)
				game_status = "MENU"
			end
			if (clicked_button == "net_host") then
				play_sound(sound_laser)
				game_status = "LOBBY"
				InitServer("*", multiport)
				InitClient("localhost", multiport)
			end
			if (clicked_button == "net_join") then
				play_sound(sound_laser)
				game_status = "NETPLAY_CONNECTING"
				InitClient(multihost, multiport)
			end
			if (clicked_button == "net_address") then
				play_sound(sound_laser)
				type_state = "HOST"
			end
			if (clicked_button == "net_port") then
				play_sound(sound_laser)
				type_state = "PORT"
			end
		end
		
	end
if DEDICATED then
	--Start a new game again, so we don't need a input from the user anymore.
	if game_status == "GAMEOVER" or game_status == "MENU" or game_status == "LOBBY" then
		new_game()
	end
end

if NetServer then
	NetServer:update()
	if SERVER then ServerUpdate(dt) end
end

if NetClient then
	NetClient:update()
	if CLIENT and not IS_DISCONNECTED then ClientUpdate(dt) end
	if NetClient:isDisconnected() then
		if not IS_DISCONNECTED then
			IS_DISCONNECTED = true
		end
	end
end
end
IS_DISCONNECTED = false
FULLSCREEN = false
NET_USERNAME = os.getenv("USER") or os.getenv("USERNAME") or "Commander"
GAME_VERSION = "1.0.0"
CHAT_LOGS = {}

-- Initialize the netplay client and connect to a host with a port.
function InitClient(host,port)
	CLIENT = true
	IS_NETPLAY = true
	CHAT_LOGS = {}
	IS_DISCONNECTED = false
	--net_delete_queue = {}
	CLIENT_ID = 0
	NetClient = sock.newClient(host, port)
	NetClient:setSerialization(bitser.dumps, bitser.loads)
	NetClient:enableCompression()
	--game_status = "NETPLAY_CONNECTING"

	for z,v in ipairs(players) do
		v.is_active = false
		v.is_ai = false
		v.netindex = false
		if not SERVER then
			v.b:setType("static")
		end
	end

	NetClient:on("connect", function ()
		--print("Connected to the server!")
		game_status = "LOBBY"
		NetClient:send("clientinfo", {
			version = GAME_VERSION,
			username = NET_USERNAME,
		})
	end)

	NetClient:on("netmsg", function (data)
		ClientReceive(data)
	end)
	NetClient:on("disconnect", function ()
		table.insert(CHAT_LOGS, {
			msg = "Disconnected from the server.",
			lifetime = 100,
		})
		game_status = "NETPLAY_CONNECTING"
		play_sound(sound_shipexplode)
	end)
	table.insert(CHAT_LOGS, {
		msg = "Connecting to the server, please wait...",
		lifetime = 10,
	})
	NetClient:connect()
	love.window.setTitle(game_name .. " (Netplay)")
end
-- Disconnects the client
function StopClient()
	NetClient:disconnectNow()
	love.window.setTitle(game_name)
	CLIENT = false
	if not SERVER then IS_NETPLAY = false end
	NetClient = nil
	for i,v in ipairs(players) do
		v.is_active = false
		v.is_ai = true
		v.name = "Player " .. i
		v.b:setType("dynamic")
	end
	if type_state == "CHAT" then
		type_state = false
	end
	players[1].is_active = true
	players[1].is_ai = false
end
-- Stops the server
function StopServer()
	NetServer:destroy()
	SERVER = false
	IS_NETPLAY = false
	NetServer = nil
end
-- Initialize the netplay server and let clients to connect into it.
-- (On local server, local client always connects into it.)
function InitServer(host,port)
	SERVER = true
	IS_NETPLAY = true
	NetServer = sock.newServer(host, port, max_players)
	NetServer:setSerialization(bitser.dumps, bitser.loads)
	NetServer:enableCompression()
	if DEDICATED then
		-- While in a dedicated server, Make sure the players are not active on the server as the local client would do while connecting to a local or remote server.
		for z,v in ipairs(players) do
			v.is_active = false
			v.is_ai = false
		end
	end

	NetServer:on("connect", function (data, client)
		local pl = players[client:getIndex()]
		print("CONNECT: " .. pl.name .. " has joined the server")
		if pl then
			pl.is_active = true
			pl.is_client = true
			pl.is_ready = false
			pl.points = 0 -- Make sure we set score to 0, so we don't feel like cheating.
			
			pl.net_up = false
			pl.net_shot = false
			pl.net_left = false
			pl.net_right = false
			ServerSendExcept(client,{
				type = "playerinfo",
				index = client:getIndex(),
				is_active = pl.is_active,
				username = "Commander",
			})

			ServerSendToPeer(client, {
				type = "index",
				index = client:getIndex(),
			})

			for z,v in ipairs(players) do
				ServerSendToPeer(client,{
					type = "playerinfo",
					index = v.id,
					is_active = v.is_active,
					is_ready = v.is_ready,
					username = v.name,
				})
			end

			ServerSendToPeer(client,{
				type = "chat",
				message = "Connected to the server, playing as player " .. pl.id
			})
			ServerSendToPeer(client,{
				type = "chat",
				message = "Server Version: " .. GAME_VERSION .. ", OS: " .. love.system.getOS()
			})
			ServerSendExcept(client,{
				type = "chat",
				message = pl.name .. " joined the server"
			})

			if game_status == "INGAME" then
				if pl.playstatus == "DEAD" and not pl.is_ai then
					pl.lives = 3
					new_ship(pl)
				elseif pl.playstatus == "INGAME" then
					pl.shield_power = shield_max_power
				end
			end
			pl.is_ai = false
		else
			--client:disconnect()
			print("[WARN] Player Index '".. client:getIndex() .."' does not exist on this server.")
		end

		ServerSendToPeer(client,{
			type = "gameinfo",
			status = game_status,
			mode = game_mode,
		})
	end)

	NetServer:on("netmsg", function (data, client)
		ServerReceive(client, data)
	end)

	NetServer:on("disconnect", function (data, client)
		local pl = players[client:getIndex()]
		if not pl then return end
		ServerSend({
			type = "chat",
			message = pl.name .. " left the server"
		})
		print("DISCONNECT: " .. pl.name .. " left the server")
		if game_status == "LOBBY" or game_status == "GAMEOVER" then
			pl.is_active = false
		elseif game_status == "INGAME" then
			pl.is_active = false
			pl.playstatus = "DEAD"
			pl.is_ai = false
			pl.name = "Player " .. pl.id
		end
		if pl.id < MAX_BOTS then
			pl.is_ai = true
			pl.is_active = true
			pl.lives = 6
			pl.points = 0
			--print(pl.name .. " is now a bot again.")
			new_ship(pl)
		end
		pl.is_client = false
		ServerSend({
			type = "playerinfo",
			index = client:getIndex(),
			is_active = pl.is_active,
			username = pl.name,
		})
		
	end)

	NetServer:on("clientinfo", function (data, client)
		local pl = players[client:getIndex()]
		if not pl then return end
		local on = pl.name
		pl.name = data.username
		pl.is_active = true
		ServerSend({
			type = "playerinfo",
			index = client:getIndex(),
			is_active = pl.is_active,
			username = data.username or "Commander",
		})
		ServerSendExcept(client,{
			type = "chat",
			message = on .. " changed their name to: " .. data.username
		})
		print("CHANGE: " .. on .. " changed their name to: " .. data.username)
		if data.version ~= GAME_VERSION then
			print("[WARN] " .. pl.name .. " is using a outdated version (client: " .. data.version .. ", server: " .. GAME_VERSION .. ")")
		end
	end)

	print("Listening on "..NetServer:getSocketAddress())
end
local sticks = 1/MAX_FPS
local stick = 0

local cticks = 1/60
local ctick = 0
-- Updates the server for logic and sending network messages.
function ServerUpdate(dt)
	stick = stick + dt
	if game_status == "INGAME" and stick >= sticks then
		for i,v in ipairs(rocks) do
			ServerSend({
				type = "rockinfo",
				index = i,
				x = rocks[i].b:getX(),
				y = rocks[i].b:getY(),
				angle = rocks[i].b:getAngle(),
				size = rocks[i].size,
			})
		end

		for i,v in ipairs(bullets) do
			ServerSend({
				type = "bulletinfo",
				index = i,
				x = bullets[i].b:getX(),
				y = bullets[i].b:getY(),
				owner = bullets[i].owner.id,
			})
		end

		ServerSend({
			type = "paused",
			paused = PAUSED,
		})
	end

	if stick >= sticks then
		stick = 0
		for i,v in ipairs(players) do
			ServerSend({
				type = "playerinfo",
				index = i,
				is_active = v.is_active,
				is_ai = v.is_ai,
				username = v.name,
				x = v.b:getX(),
				y = v.b:getY(),
				angle = v.b:getAngle(),
				shield_power = v.shield_power,
				points = v.points,
				lives = v.lives,
				is_moving = v.want_up,
				is_ready = v.is_ready,
				playstatus = v.playstatus,
			})
		end
	end
end
-- Updates the client for logic and receiving network messages.
function ClientUpdate(dt)
	ctick = ctick+dt
	if game_status == "INGAME" and type_state ~= "CHAT" and ctick >= cticks then
	local controlstate = {} controlstate.want_left = false controlstate.want_right = false controlstate.want_shot = false controlstate.want_up = false
	local p = players[1]
	local joystick = love.joystick.getJoysticks()[1]
		if (not joystick) then
			if love.keyboard.isDown(p.key_left) then controlstate.want_left = true end
			if love.keyboard.isDown(p.key_right) then controlstate.want_right = true end
			if love.keyboard.isDown(p.key_up) then controlstate.want_up = true end
			if love.keyboard.isDown(p.key_shot) then controlstate.want_shot = true end
		else
			if (joystick.isDown(p.button_left )) then controlstate.want_left=true end
			if (joystick.isDown(p.button_right )) then controlstate.want_right=true end
			if (joystick.isDown(p.button_up )) then controlstate.want_up=true end
			if (joystick.isDown(p.button_shot)) then controlstate.want_shot=true end
		end
		ClientSend({
			type = "controlstate",
			want_left = controlstate.want_left,
			want_right = controlstate.want_right,
			want_up = controlstate.want_up,
			want_shot = controlstate.want_shot,
		})
	end
	--[[
	for i = #net_delete_queue, 1, -1 do
		local a = net_delete_queue[i]
		if not world:isLocked() then
			if not a.b:isDestroyed() then
				a.b:destroy()
			end
		end
		table.remove(net_delete_queue, i)
	end

	for i = #bullet_delete_queue, 1, -1 do
		local a = bullet_delete_queue[i]
		if not world:isLocked() then
			if not a.b:isDestroyed() then
				a.b:destroy()
				
			end
		end
		table.remove(bullet_delete_queue, i)
	end]]

	for i,a in ipairs(CHAT_LOGS) do
		a.lifetime = a.lifetime - dt
		if a.lifetime < 1 then
			table.remove(CHAT_LOGS, i)
		end
	end

	if ctick >= cticks then
		ctick = 0
	end
end
--rock_delete_queue = {}
--bullet_delete_queue = {}
function ClientReceive(data)
	local typ = data.type
	if not typ then return end

	if typ == "playerinfo" and not SERVER then
		local pl = players[data.index]
		if not pl then return end
		pl.name = data.username or "Commander"
		pl.is_active = data.is_active or pl.is_active
		pl.is_ai = data.is_ai or pl.is_ai
		pl.shield_power = data.shield_power or pl.shield_power
		pl.points = data.points or pl.points
		pl.lives = data.lives or pl.lives
		pl.is_moving = data.is_moving or pl.is_moving
		pl.playstatus = data.playstatus or pl.playstatus
		pl.is_ready = data.is_ready or pl.is_ready
		if not world:isLocked() then
			pl.b:setX(data.x or pl.b:getX())
			pl.b:setY(data.y or pl.b:getY())
			pl.b:setAngle(data.angle or pl.b:getAngle())
		end
	end

	if typ == "rockinfo" and not SERVER then
		local rock = rocks[data.index]
		if not rock then
			add_rock(data.size, data.x, data.y, data.index)
			rock = rocks[data.index]
		end
		if rock then
			if rock.size ~= data.size and not world:isLocked() then
				if not rock.b:isDestroyed() then
					rock.b:destroy()
				end
				table.remove(rocks, data.index)
				add_rock(data.size, data.x, data.y, data.index)
				rock = rocks[data.index]
			end
			if not world:isLocked() and not rock.b:isDestroyed() then
				rock.b:setAngle(data.angle or rock.b:getAngle())
				rock.b:setX(data.x or rock.b:getX())
				rock.b:setY(data.y or rock.b:getY())
			end
		end
	end

	if typ == "bulletinfo" and not SERVER then
		local rock = bullets[data.index]
		if not rock then
			local angle = players[data.owner].b:getAngle()
			shoot_bullet(data.x, data.y, angle, data.owner, data.index)
			rock = bullets[data.index]
		end
		if rock then
			if not world:isLocked() and not rock.b:isDestroyed() then
				--rock.b:setAngle(data.angle or rock.b:getAngle())
				rock.b:setX(data.x or rock.b:getX())
				rock.b:setY(data.y or rock.b:getY())
			end
		end
	end

	if typ == "rockdelete" and not SERVER then
		local rock = rocks[data.index]
		if rock and not world:isLocked() then
			--table.insert(net_delete_queue, rock)
			if not rock.b:isDestroyed() then
				rock.b:destroy()
			end
			table.remove(rocks, data.index)
		end
	end

	if typ == "bulletdelete" and not SERVER then
		local rock = bullets[data.index]
		if rock and not world:isLocked() then
			--table.insert(net_delete_queue, rock)
			if not rock.b:isDestroyed() then
				rock.b:destroy()
			end
			table.remove(bullets, data.index)
		end
	end

	if typ == "sound" and not SERVER then
		if data.sound == "SHIPEXPLODE" then
			play_sound(sound_shipexplode)
		end
		if data.sound == "LASER" then
			play_sound(sound_laser)
		end
		if data.sound == "ROCKEXPLODE" then
			play_sound(sound_rockexplode)
		end
		if data.sound == "NEWLEVEL" then
			play_sound(sound_newlevel)
		end

		if data.sound == "CHAT" then
			play_sound(sound_chat)
		end
	end

	if typ == "gameinfo" and not SERVER then
		game_mode = data.mode or game_mode
		if data.status == "INGAME" then
			new_game()
		else
			game_status = data.status or game_status
		end
	end

	if typ == "ingamemsg" and not SERVER then
		add_ingame_message(data.text)
	end

	if typ == "particle" and not SERVER then
		local ptype = data.ptype
		if ptype then
			if ptype == "shipexplode" then
				ps_ship_explosion:setPosition(data.x,data.y)
				ps_ship_explosion:start()
			end
			if ptype == "rockexplode" then
				ps_rock_explosion:setPosition(data.x,data.y)
				ps_rock_explosion:start()
			end
			if ptype == "shipexhaust" then
				local p = players[data.index]
				if not p then return end
				ps_ship_exhaust:setPosition (p.b:getX()+ sin(p.b:getAngle())*ship_radius/2, p.b:getY()+cos(p.b:getAngle())*ship_radius/2)
				ps_ship_exhaust:setDirection(-p.b:getAngle()+(3.14/2))
				ps_ship_exhaust:start()	
			end
		end
	end

	if typ == "paused" and not SERVER then
		PAUSED = data.paused
	end

	if typ == "index" then
		CLIENT_ID = data.index
	end

	if typ == "chat" then
		table.insert(CHAT_LOGS, {
			msg = data.message,
			lifetime = 10,
		})
	end
end
CLIENT_ID = 0
function ServerReceive(peer, data)
	local typ = data.type
	if not typ then return end
	local player = players[peer:getIndex()]
	if typ == "controlstate" then
		if not player then return end
		player.net_up = data.want_up or false
		player.net_left = data.want_left or false
		player.net_right = data.want_right or false
		player.net_shot = data.want_shot or false
	end
	if typ == "set_ready" then
		player.is_ready = not player.is_ready
		if player.is_ready then
			play_sound(sound_laser)
		else
			play_sound(sound_shipexplode)
		end
	end
	if typ == "chat" then
		if not data.message or data.message=="" then return end
		ServerSend({
			type = "chat",
			index = player.id,
			message = player.name .. ": " .. data.message,
		})
		print("CHAT: " .. player.name .. ": " .. data.message)
		play_sound(sound_chat)
	end
end

function ClientSend(data)
	if not CLIENT then return end
	NetClient:send("netmsg", data)
end

function ServerSend(data)
	if not SERVER then return end
	NetServer:sendToAll("netmsg", data)
end

function ServerSendExcept(peer, data)
	if not SERVER then return end
	if not peer then return end
	NetServer:sendToAllBut(peer, "netmsg", data)
end

function ServerSendToPeer(peer, data)
	if not peer then return end
	if not SERVER then return end
	NetServer:sendToPeer(peer, "netmsg", data)
end




function love.textinput(text)
	if not type_state then return end
	--play_sound(sound_laser)
	if type_state == "HOST" then
		TYPING.host = TYPING.host .. text
	end
	if type_state == "PORT" then
		TYPING.port = TYPING.port .. text
	end
	if type_state == "USERNAME" then
		TYPING.username = TYPING.username .. text
	end
	if type_state == "CHAT" then
		if TYPING.chat == false then
			-- This is to prevent a letter being typed for no reason.
			TYPING.chat = ""
		else
			TYPING.chat = TYPING.chat .. text
		end
		
	end
end

function DoneTyping()
	if type_state == "HOST" then
		multihost = TYPING.host
	end
	if type_state == "PORT" then
		multiport = tonumber(TYPING.port)
	end
	if type_state == "USERNAME" then
		NET_USERNAME = TYPING.username
	end
	if type_state == "CHAT" then
		if CLIENT then
			ClientSend({
				type = "chat",
				message = TYPING.chat,
			})
		end
		TYPING.chat = ""
	end
	type_state = false
end

function love.keypressed(key, unicode)
	
	--[[
if (key=="f2") then
players[1].points = 550
players[2].points = 50
players[3].points = 620
players[4].points = 380
end
if (key=="f9") then new_level () end
if (key=="f12") then game_status = "GAMEOVER" end
]]
if type_state then
	if key == "backspace" then
		--play_sound(sound_rockexplode)
		local text = ""
		if type_state == "HOST" then
			text = TYPING.host
		end
		if type_state == "PORT" then
			text = TYPING.port
		end
		if type_state == "USERNAME" then
			text = TYPING.username
		end
		if type_state == "CHAT" then
			text = TYPING.chat
		end
		local byteoffset = utf8.offset(text, -1)

		if byteoffset then
			text = string.sub(text, 1, byteoffset - 1)
		end

		if type_state == "HOST" then
			TYPING.host = text
		end
		if type_state == "PORT" then
			TYPING.port = text
		end
		if type_state == "USERNAME" then
			TYPING.username = text
		end
		if type_state == "CHAT" then
			TYPING.chat = text
		end
	end

	if key == "return" then
		DoneTyping()
	end
else
if (key=="p") and game_status == "INGAME" then
	if IS_NETPLAY and not SERVER then return end
	PAUSED = not PAUSED
end
if (key=="f10") then
	if (show_debug==true) then show_debug = false else show_debug = true end
	end
--if (key=='a') then add_rock (3) end
if (game_status=="INGAME") then
	for i,p in ipairs(players) do		
			--[[das ist jetzt in love.update mit gun_blocktime
			if (p.playstatus == "INGAME" and key == p.key_shot and p.ship_energy > ship_energy_per_shot and p.shield_power < 1) then
				shoot_bullet (p.b:getX()  -sin(p.player_a) *ship_radius*1.5, p.b:getY()-cos(p.player_a) *ship_radius*1.5, p.player_a, p)
				p.ship_energy = p.ship_energy - ship_energy_per_shot
				end		
				--]]	
				if IS_NETPLAY then
					if not SERVER then break end
				end	
		if (key == p.key_shot and p.playstatus == "RESPAWN" and p.lives > 0) then new_ship (p) end
		end
	end
if (key == "n" and (game_status == "MENU" or game_status=="GAMEOVER")) then  new_game () end

if (key == "c" and (game_status == "MENU" or game_status=="GAMEOVER")) then  game_status = "CONTROLLCONFIG" end
if (key == "escape" and (game_status == "MENU" or game_status =="GAMEOVER" or game_status == "LOBBY")) then 
	if IS_NETPLAY then
		if CLIENT then
			StopClient()
			game_status = "MENU"
		end

		if SERVER then
			StopServer()
		end
		play_sound(sound_laser)

		if NET_CONNECT then
			love.event.quit()
		end
	else
		love.event.quit()
	end 
end
if (key == "escape" and (game_status == "INGAME" or game_status == "RESPAWN" or game_status == "NETPLAY_CONNECTING")) then 
	game_status = "MENU" 
	if SERVER then
		ServerSend({
			type = "gameinfo",
			status = "LOBBY",
		})
		game_status = "LOBBY"
	end
	if CLIENT and not SERVER then
		play_sound(sound_laser)
		StopClient()
		if NET_CONNECT then
			love.event.quit()
		end
	end
end
if (key == "g" and (game_status == "MENU" or game_status=="GAMEOVER")) then  
	if (game_mode == "A") then game_mode ="B" return end
	if (game_mode == "B") then game_mode ="C" return end
	if (game_mode == "C") then game_mode ="D" return end
	if (game_mode == "D") then game_mode ="A" return end
	play_sound(sound_laser)
	end
if (key == "f1") then 
	if (play_sounds == true) then play_sounds = false return end
	if (play_sounds == false) then play_sounds = true return end
	play_sound(sound_laser)
	end	
--if (key == "f3") then add_wall (300,300) end
if key == "t" and IS_NETPLAY then
	type_state = "CHAT"
	TYPING.chat = false
end
end
end
PVP_ROUND = 0

function shoot_bullet (gunx, guny, guna, bullet_owner, pos)
--local gunx,gun_y,guna
if (gunx==nil or guny==nil or guna==nil) then
--	gunx = player:getX()
--	guny = player:getY()
--	guna = player_a
	gunx = 100
	guny= 100
	guna = 1
	end
	if IS_NETPLAY then
		if SERVER then
			play_sound(sound_laser)
		end
	else
		play_sound(sound_laser)
	end
local newbullet = {}
local bt = "dynamic"
if IS_NETPLAY then
	if CLIENT and not SERVER then
		bt = "static"
	end
end
newbullet.b = love.physics.newBody(world, gunx, guny, bt)
newbullet.s = love.physics.newCircleShape(bullet_radius)
newbullet.status = "BULLET"
newbullet.f = love.physics.newFixture(newbullet.b, newbullet.s)
newbullet.owner = bullet_owner
--newbullet.s:setRestitution (1)
newbullet.f:setUserData (newbullet)
newbullet.b:setBullet (true)
newbullet.b:applyLinearImpulse (-sin(guna) *  bullet_speed, -cos(guna) *  bullet_speed)
if pos then
	table.insert(bullets, pos, newbullet)
else
	table.insert(bullets, newbullet)
end
--newbullet.b:destroy()
--newbullet.s:destroy()
--newbullet = nil
end

function draw_ship (x,y, a, shield)
--love.graphics.setColor(0, 255, 150, 255)
--love.graphics.setColor(255, 255, 50, 255)
love.graphics.setLineWidth(3)
local p1x = (x-sin(a)*ship_radius)
local p1y=(y-cos(a)*ship_radius)
   local p2x= (x+sin(a)*ship_radius/2)
   local p2y=(y+cos(a)*ship_radius/2)
local p3x= (x+sin(a-0.8)*ship_radius)
local p3y= (y+cos(a-0.8)*ship_radius)
   local p4x= (x+sin(a+0.8)*ship_radius)
   local p4y= (y+cos(a+0.8)*ship_radius)
love.graphics.line (p1x,p1y, p4x,p4y)
love.graphics.line (p1x,p1y, p3x,p3y)
love.graphics.line (p4x,p4y, p2x,p2y)
love.graphics.line (p3x,p3y, p2x,p2y)
 	if (shield ~= nil) then
		if (shield > 1) then 
		local e = 2
		if (shield < shield_max_power / 4) then e = math.random(18,20)/10 end
		love.graphics.circle ("line",x,y, ship_radius*e,16)
		end	
	end
	if (show_debug==true) then
		love.graphics.setColor(255, 0, 255, 255)
		love.graphics.circle ("line",x,y, ship_radius,20)	
	end
 end
 
 function draw_bullets ()
 love.graphics.setColor(1,1,1)
 for i,v in ipairs(bullets) do
	love.graphics.setColor(1,1,1)
	if not v.b:isDestroyed() then
		if type(v.owner)=="table" or type(v.owner)=="userdata" then
			set_player_color(v.owner.id)
		elseif type(v.owner)=="number" then
			set_player_color(v.owner)
		end
	love.graphics.circle ("line", v.b:getX(), v.b:getY(), bullet_radius, 8)
	--love.graphics.circle("fill", v.b:getX(), v.b:getY(), bullet_radius, 8)
	end
end
 end

 
function add_rock (size, x,y, pos)
if (x==nil) then x = random (0, res_w) end
if (y==nil) then y = random (-500, -200) end
local newrock = {}
local nr = small_rock_radius
if (size == 3) then nr = large_rock_radius end
if (size == 2) then nr = medium_rock_radius end
if (size == 1) then nr = small_rock_radius end
local bt = "dynamic"
if IS_NETPLAY then
	if CLIENT and not SERVER then
		bt = "static"
	end
end
newrock.b = love.physics.newBody(world, x, y, bt)--nr*100,5)
newrock.b:setAngularVelocity (math.random(-2,2))
newrock.s = love.physics.newCircleShape(nr)
newrock.status = "ROCK"
newrock.size = size
newrock.destroyed_by = nil
newrock.f = love.physics.newFixture(newrock.b, newrock.s)
--newrock.s:setRestitution (0.95)
newrock.f:setUserData (newrock)
if (size == 1) then newrock.b:applyLinearImpulse (random (-900,800), random (-900,900))
else newrock.b:applyLinearImpulse (random (-800,800), random (-800,800))
end
if pos then
	table.insert(rocks, pos, newrock)
	rocks[pos].f:setUserData (rocks[pos])
else
table.insert(rocks, newrock)
rocks[#rocks].f:setUserData (rocks[#rocks])
end

--newrock.b:destroy()
--newrock.s:destroy()
--newrock = nil
end


function new_level ()
rocks = {}
if IS_NETPLAY then
	if SERVER then
if (level == 1) then add_rock (3) end
if (level == 2) then 
	add_rock (3)
	add_rock (2)
	end
if (level == 3) then 
	add_rock (3)
	add_rock (2)
	add_rock (1) 
	end	
if (level > 3) then
	for blabla = 0, level*2, 1 do
		add_rock (math.random(1,3))
		end
	end
end
else
	if (level == 1) then add_rock (3) end
if (level == 2) then 
	add_rock (3)
	add_rock (2)
	end
if (level == 3) then 
	add_rock (3)
	add_rock (2)
	add_rock (1) 
	end	
if (level > 3) then
	for blabla = 0, level*2, 1 do
		add_rock (math.random(1,3))
		end
	end
end
shield_power = shield_max_power
if IS_NETPLAY then
	if SERVER then
if (game_mode=="A" or game_mode=="C") then add_ingame_message ("Level " .. level .. " Get Ready!") end
level = level + 1
play_sound(sound_newlevel)
	end
else
	if (game_mode=="A" or game_mode=="C") then add_ingame_message ("Level " .. level .. " Get Ready!") end
	level = level + 1
	play_sound(sound_newlevel)
end
end


function draw_rocks ()
love.graphics.setColor(0.5, 0.5,0.5)
for i,v in ipairs(rocks) do
	if not v.b:isDestroyed() then
	love.graphics.circle ("line", v.b:getX(), v.b:getY(), v.s:getRadius(), 32)
	love.graphics.line (v.b:getX(), v.b:getY(),  v.b:getX()+math.sin(v.b:getAngle())*v.s:getRadius() , v.b:getY()+math.cos(v.b:getAngle())*v.s:getRadius())
	if (show_debug==true) then
		font:setLineHeight (1.0)
		--love.graphics.print(math.floor(v.b:getX())..":".. math.floor(v.b:getY()) , v.b:getX(), v.b:getY()) 		
		if (v.status ~= nil) then love.graphics.print(v.status, v.b:getX(), v.b:getY()) else love.graphics.print("nil", v.b:getX(), v.b:getY()) end
	end
	end
end
 end
 
function draw_walls ()
love.graphics.setColor(255, 255, 255, 255)
for i,v in ipairs(walls) do
	love.graphics.polygon("line", v.s:getPoints())
	end
 end
 
--local buttons = {}
function add_player ()
if (#players > max_players) then return end
local new_player = {}
new_player.playstatus = "RESPAWN" --INGAME, RESPAWN, DEAD
new_player.is_ai = true
new_player.is_active = false
new_player.net_up = false
new_player.net_down = false
new_player.net_left = false
new_player.net_right = false
new_player.name = "Player " .. tostring(#players+1)
new_player.id = #players + 1
if (#players == 0) then
	new_player.key_shot ="down"
	new_player.key_left ="left"
	new_player.key_right ="right"
	new_player.key_up ="up"
	if not DEDICATED then
	new_player.jstick = love.joystick.getJoysticks()[2]
	end
	new_player.playstatus = "INGAME"
	new_player.is_active = true
	new_player.is_ai = false
	end
if (#players == 1) then
	new_player.key_shot ="s"
	new_player.key_left ="a"
	new_player.key_right ="d"
	new_player.key_up ="w"
	end
if (#players == 2) then
	new_player.key_shot ="kp5"
	new_player.key_left ="kp4"
	new_player.key_right ="kp6"
	new_player.key_up ="kp8"
	end
if (#players == 3) then
	new_player.key_shot ="j"
	new_player.key_left ="h"
	new_player.key_right ="k"
	new_player.key_up ="u"
	end	
if (#players >= 4) then
	new_player.is_ai = true
	new_player.key_shot =""
	new_player.key_left =""
	new_player.key_right =""
	new_player.key_up =""
end
new_player.joystick_nr = nil
new_player.gun_blocktime = 0
new_player.shield_power = shield_max_power
new_player.ship_energy = ship_max_energy
new_player.lives = 3
new_player.points = 0
new_player.netindex = 0
new_player.is_ready = false
new_player.is_client = false
new_player.status = "SHIP"
new_player.b = love.physics.newBody(world, math.random(100,200), math.random(100,200), "dynamic")--100, 5)
--new_player.b:setBullet (true) --I MUST BECOME THE BULLET
new_player.s = love.physics.newCircleShape(ship_radius)
--new_player.b:setRestitution (0.2)

new_player.f = love.physics.newFixture(new_player.b, new_player.s)
new_player.f:setUserData (new_player)
new_player.want_left = false
new_player.want_right = false
new_player.want_shot = false
new_player.want_up = false
new_player.b:setAngle(0)
table.insert(players, new_player)
 new_player.n = nil
 --local newplayers = {} --key_shot key_left key_right key_up body shape player_a shield_power ship_energy lives
 end
 
function play_sound (sfx)
 if (play_sounds == true) then
	love.audio.stop(sfx)
	love.audio.play(sfx)
	end
	if SERVER then
		if sfx == sound_laser then
			ServerSend({
				type = "sound",
				sound = "LASER",
			})
		end
		if sfx == sound_rockexplode then
			ServerSend({
				type = "sound",
				sound = "ROCKEXPLODE",
			})
		end
		if sfx == sound_shipexplode then
			ServerSend({
				type = "sound",
				sound = "SHIPEXPLODE",
			})
		end
		if sfx == sound_newlevel then
			ServerSend({
				type = "sound",
				sound = "NEWLEVEL",
			})
		end
	end
 end
 
 --love.graphics.printf( text, x, y, limit, align )
function draw_menu ()
	if game_status == "MENU" or game_status == "GAMEOVER" or game_status == "LOBBY" then
draw_buttons (buttons)
--LOGO with ship circling around it
love.graphics.setColor(0, 255, 0, 255)
love.graphics.setFont( large_font )
--Old Title: Astropatrolonium!
love.graphics.print(game_name, res_w/2-100, res_h/5+(math.cos(menu_ship_a)*10))
local msx = res_w/2+math.sin(menu_ship_a/2)*160 	local msy = res_h/5+math.cos(menu_ship_a/2)*50
ps_ship_exhaust:setPosition (msx+ (sin(menu_ship_a/2)*ship_radius/2), msy+(cos(menu_ship_a/2)*ship_radius/2))
ps_ship_exhaust:setDirection((menu_ship_a/2))
ps_ship_exhaust:start()
love.graphics.setFont( small_font )
draw_ship (msx,msy, menu_ship_a/2-math.pi/2)
--love.graphics.print("press + to add player. press - to remove a player", res_w/2-300, res_h/4+70)
local sound_s = "off"
if (play_sounds==true) then sound_s = "on" end
--love.graphics.print("sound is " .. sound_s .. " (press F1 to change)", res_w/2-300, res_h-20)

local xs = 340
local ys = 190
for i,v in ipairs(players) do
	set_player_color (i)
	draw_ship ((res_w/2-xs)+20,(res_h/4+ys)+10,menu_ship_a+0.2*i)
	local player_s ="->"
	--Stoned Autopilot
	if CLIENT then
		if (players[i].is_ai) then player_s = "AI" else player_s = players[i].name end
	else
		if (players[i].is_ai) then player_s = "AI" else player_s = "turn: " .. players[i].key_left.." & "..players[i].key_right .. "  thrust:" .. players[i].key_up .. "  shot:" ..players[i].key_shot end
	end
	if (not players[i].is_active) then player_s = "not active" end
	if (game_status == "GAMEOVER") then player_s = player_s .. " Score:" .. players[i].points end
	--if (players[i] ~= nil) then button_s = love.joystick.getName(2) end
	if (show_debug) then player_s = player_s .. "( " .. i .. " )" end
	love.graphics.print(player_s, small_font, (res_w/2-xs)+40,(res_h/4+ys))
	ys = ys + 50
if ys > 340 then
	ys = 190
	xs = xs - 280
end
	end
--show_status_of_all_joystick ()
elseif game_status == "SETTINGS" then
	draw_buttons(setbuttons)

elseif game_status == "NETPLAY" then
	draw_buttons(netbuttons)
end
end
--local colorCache = {}
function set_player_color (playernumber)
if (playernumber==1) then love.graphics.setColor(0, 1, 1) end
if (playernumber==2) then love.graphics.setColor(0, 1, 0) end
if (playernumber==3) then love.graphics.setColor(1, 0, 0) end
if (playernumber==4) then love.graphics.setColor(1,1,1) end
if (playernumber==5) then love.graphics.setColor(0.1,0.5,1) end
if (playernumber==6) then love.graphics.setColor(0,0.5,0.1) end
if (playernumber==7) then love.graphics.setColor(1,1,0) end
if (playernumber==8) then love.graphics.setColor(0.8,0.8,0.8) end
if (playernumber==9) then love.graphics.setColor(0.3,1,1) end
if (playernumber==10) then love.graphics.setColor(1,0.5,1) end
if (playernumber==11) then love.graphics.setColor(0.2,0.8,0.9) end
if (playernumber==12) then love.graphics.setColor(1,1,0.4) end
end

function show_status_of_all_joystick ()
love.graphics.setFont( small_font )
love.graphics.setColor(255, 0, 0, 255)
local dx=100
local dy = res_h/2
local buttons_down_s = "LOL"
local button_n = 666
love.graphics.print(love.joystick.getJoystickCount(), dx-30, dy)
for j = 0, love.joystick.getJoystickCount(), 1 do
	--love.joystick.open( j )
	local joystick = love.joystick.getJoysticks()[j]
	if (joystick) then
		button_n = joystick.getButtonCount(j)
		buttons_down_s = "pressed buttons:"
			for b = 0, button_n, 1 do
			if (joystick.isDown(b)) then buttons_down_s = buttons_down_s .. tostring (b) .. "," end			
			end
		love.graphics.print("->" ..  joystick.getName(j), dx, dy)
		love.graphics.print("=> buttons:" .. button_n .. " " .. buttons_down_s, dx, dy+20)
		dy=dy+45
		end
		end
end




function distance (x1,y1 ,x2,y2)
local xdiff = x1 - x2
local ydiff = y1 - y2
local summer = xdiff * xdiff + ydiff * ydiff
return math.sqrt(summer)
end

------------------------------------------------------------------------------------------\
----------------------------------------------- ship AI ----------------------------------/
AIrange.engage = 300 AIrange.moveaway = 120 AIrange.runaway=75
function shipAI_getdecision (player)
--AIrange.engage = 300 AIrange.moveaway = 175 AIrange.runaway=140
--AIrange.engage = 300 AIrange.moveaway = 120 AIrange.runaway=75
local ai_msg = "xxx"
local want_left, want_right, want_up, want_shot = false, false, false, false
local shipx, shipy = player.b:getPosition( )
local xs, ys = player.b:getLinearVelocity ()
local current_a = real_a ((player.b:getAngle()))
local shipspeed = distance (xs,ys, 0,0)
local rocks = {}
local a_go_error = 1	--how excactly the ship does to be lined up with the a_want course to give thrust
local throttle = 20			--0 to 100
local want_a = current_a
local target_a
local lineup_error
rocks = shipAI_getrocks (player)

local nearest_rock_distance = -1
local nearest_rock_target_a = 100
local best_linedup_rock_target_a = 100
local nearest_rock_pos = {} nearest_rock_pos.x=0 nearest_rock_pos.y=0
console = ""
 for i,v in ipairs(rocks) do
	d = distance (shipx, shipy,  v.b:getX(), v.b:getY())
	target_a = real_a (angle_between_2_spots (shipx,shipy, v.b:getX(),v.b:getY()) + math.pi)
	lineup_error = math.abs (target_a - current_a)
	if (lineup_error < math.pi/4) then want_a = target_a want_shot = true end
	if (lineup_error < math.abs (current_a - best_linedup_rock_target_a) or best_linedup_rock_target_a == 100) then best_linedup_rock_target_a = target_a end
	if (d < nearest_rock_distance or nearest_rock_distance==-1) then nearest_rock_distance = d nearest_rock_pos.x =v.b:getX()  nearest_rock_pos.y =v.b:getY() nearest_rock_target_a = target_a end		
	end
console = math.floor(nearest_rock_pos.x) .. "  " .. math.floor (nearest_rock_pos.y) .. "d=" .. nearest_rock_distance
local drift_a = math.atan2(xs, ys)
--local want_a = current_a--real_a(drift_a+math.pi) --nearest_rock_target_a--drift_a --angle_between_2_spots (shipx,shipy, res_w/2, res_h/2) - math.pi --drift_a--current_a  --math.atan2(xs, ys) --math.atan2(1,0)  --math.atan2(a.y, a.x)-math.atan2(b.y,b.x)

if (nearest_rock_distance < AIrange.engage) then want_a = nearest_rock_target_a  ai_msg=" engaging slowly" throttle = 10 end
if (nearest_rock_distance > AIrange.engage) then want_a = nearest_rock_target_a  ai_msg=" engaging fast" throttle = 50 end
if (shipspeed > 150 and nearest_rock_distance > AIrange.runaway) then want_a = drift_a a_go_error = 0.2  throttle= 70 ai_msg=" slowing down " end --fliegt zu schnell? dann gegen flugrichtung drehen und bremsen
if (is_almost_offscreen (shipx,shipy)) then want_a = angle_between_2_spots (shipx,shipy, res_w/2, res_h/2) - math.pi throttle = 65 ai_msg=" to center "end
if (nearest_rock_distance < AIrange.moveaway) then want_a = real_a (nearest_rock_target_a+math.pi) throttle = 80 a_go_error=1 ai_msg=" moving way "end				--rocks sehr nah? wegdrehen --angle_between_2_spots (shipx,shipy, nearest_rock_pos.x, nearest_rock_pos.y)
if (nearest_rock_distance < AIrange.runaway) then want_a = angle_between_2_spots (shipx,shipy, nearest_rock_pos.x, nearest_rock_pos.y) throttle = 100 a_go_error=0.5 ai_msg=" running! "end				--rocks sehr nah? wegdrehen
if (shipspeed > 350) then want_a = drift_a a_go_error = 0.2 ai_msg=" hard brake " throttle = 100 end --fliegt richtig schnell, dann auf jeden fall bremsen

local diff_a =  want_a - current_a 	--console = current_a .. " " .. real_a (current_a)
if (diff_a >  0.05) then want_left = true end
if (diff_a < -0.05) then want_right = true end
if (math.abs (want_a - current_a) < a_go_error and math.random(0,100) < throttle) then want_up = true else want_up = false end



console = ai_msg
return want_left, want_right, want_up, want_shot
end

function shipAI_getrocks (player)
local r = rocks
return r
end


function real_a (a)
local n =  a / (2*math.pi)
if (math.abs (n) > 1) then a = a - (math.floor(n)*math.pi*2) end
return a
end

function angle_between_2_spots (ax, ay, bx, by)
return math.atan2(1, 0)-math.atan2(by-ay,bx-ax)
--return math.atan2(ay, ax)-math.atan2(by,bx)
end

function add_ingame_message (text)
local new_msg = {}
new_msg.text = text
new_msg.lifetime = 3
table.insert (ingame_messages, new_msg)

if SERVER then
	ServerSend({
		type = "ingamemsg",
		text = text,
	})
end
end

function show_ingame_messages ()
for i,m in ipairs(ingame_messages) do
		if (m.lifetime > 0) then
			love.graphics.setColor(1, 1, 1, 1)
			font:setLineHeight (1.0)
			love.graphics.setFont(large_font)
			love.graphics.print(m.text, 250, 400-m.lifetime*100)
			end
	end
end

function timeout_ingame_messages (dt)
for i,m in ipairs(ingame_messages) do
	m.lifetime=m.lifetime-dt
	end
end


----------------------------------------------------------  BUTTONS ----------------------------------------------

function point_in_rect (x1, y1, x2, y2, px, py)
if (px > x1 and px < x2 and py > y1 and py < y2) then return true end
return false
end


function draw_buttons (b)
font:setLineHeight (1.0)
love.graphics.setFont(small_font)
love.graphics.setColor(0, 255, 0, 255)
local mousex, mousey = love.mouse.getPosition()
mousex, mousey = CScreen.project(mousex, mousey)
for i = 1, #b, 1 do		
	if (point_in_rect (b[i].x, b[i].y, b[i].x+b[i].w, b[i].y+b[i].h,  mousex, mousey)) then 
		love.graphics.rectangle ("line", b[i].x+2, b[i].y+2, b[i].w-2, b[i].h-2)
		love.graphics.rectangle ("fill", b[i].x, b[i].y, 10, b[i].h)
		end
	love.graphics.rectangle ("line", b[i].x, b[i].y, b[i].w, b[i].h)
	love.graphics.print(b[i].text, b[i].x+10, b[i].y+b[i].h-26) 
end
end

function add_button (buttonlist, x,y, w, h, text, name)
if (h == nil) then h = 20 end
h = 25
local new_button = {}
new_button.x=x new_button.y=y new_button.w=w new_button.h=h new_button.text=text new_button.name=name
table.insert (buttonlist, new_button)
end

function clicked_button (b)
	if DEDICATED then return "NOBUTTONCLICKED" end
local mousex, mousey = love.mouse.getPosition()
mousex, mousey = CScreen.project(mousex, mousey)
local click = love.mouse.isDown(1)
--if (mouse_was_down==false and click == false) then return "NOBUTTONCLICKED" end
for i = 1, #b, 1 do	
	if (mouse_was_down and click == false and point_in_rect (b[i].x, b[i].y, b[i].x+b[i].w, b[i].y+b[i].h,  mousex, mousey)) then mouse_was_down=false return b[i].name, i end
	if (mouse_was_down == false and click == true and point_in_rect (b[i].x, b[i].y, b[i].x+b[i].w, b[i].y+b[i].h,  mousex, mousey)) then mouse_was_down = true end
	end
return "NOBUTTONCLICKED"
end


function add_wall(x, y)
    local t = {}
    t.b = love.physics.newBody(world, x, y, "dynamic")--5000,100)
    t.s = love.physics.newRectangleShape(0, 0, 50, 50)
    table.insert(walls, t)
end


-------------------------  background gfx -------------------------------
function backgroundgfx_setup (dt)
for i = 1, 20, 1 do
new_gfx = {}
new_gfx.x=math.random(0,res_w)
new_gfx.y=math.random(0,res_h)
new_gfx.size=math.random(51,200)
new_gfx.grow=math.random(10,50)
table.insert (backgroundgfx_obj, new_gfx)
end
end

function backgroundgfx_animate (dt)
for i = 1, #backgroundgfx_obj, 1 do
	backgroundgfx_obj[i].size = backgroundgfx_obj[i].size + backgroundgfx_obj[i].grow*dt
	if (backgroundgfx_obj[i].size > 255) then backgroundgfx_obj[i].grow =-backgroundgfx_obj[i].grow end
	if (backgroundgfx_obj[i].size < 50) then backgroundgfx_obj[i].grow =-backgroundgfx_obj[i].grow 
		backgroundgfx_obj[i].x=math.random(0,res_w)
		backgroundgfx_obj[i].y=math.random(0,res_h)
	end
	end
end

function backgroundgfx_draw ()
--love.graphics.setBlendMode("additive")
for i = 1, #backgroundgfx_obj-1, 1 do
	love.graphics.setColor(255-backgroundgfx_obj[i].size, 255-backgroundgfx_obj[i].size, 255-backgroundgfx_obj[i].size, 200)
	love.graphics.circle ("fill", backgroundgfx_obj[i].x+150-backgroundgfx_obj[i].size, backgroundgfx_obj[i].y+150-backgroundgfx_obj[i].size,   backgroundgfx_obj[i].size, 3)
	--love.graphics.circle ("line", backgroundgfx_obj[i].x, backgroundgfx_obj[i].y,   backgroundgfx_obj[i].size)
	--love.graphics.line (backgroundgfx_obj[i].x+150-backgroundgfx_obj[i].size, backgroundgfx_obj[i].y+150-backgroundgfx_obj[i].size,    backgroundgfx_obj[i+1].x+150-backgroundgfx_obj[i+1].size, backgroundgfx_obj[i+1].y+150-backgroundgfx_obj[i+1].size)
--	love.graphics.line (backgroundgfx_obj[i].x-backgroundgfx_obj[i].size, backgroundgfx_obj[i].y-backgroundgfx_obj[i].size  ,  backgroundgfx_obj[i].x+backgroundgfx_obj[i].size, backgroundgfx_obj[i].y+backgroundgfx_obj[i].size )
--	love.graphics.line (backgroundgfx_obj[i].x+backgroundgfx_obj[i].size, backgroundgfx_obj[i].y-backgroundgfx_obj[i].size  ,  backgroundgfx_obj[i].x+backgroundgfx_obj[i].size, backgroundgfx_obj[i].y+backgroundgfx_obj[i].size )
	end
end
	
	--[[  man das ist halt alt
--player controlls keyboard				
			if love.keyboard.isDown(p.key_left) then p.player_a=p.player_a+(ship_turnrate*dt) end
			if love.keyboard.isDown(p.key_right) then p.player_a=p.player_a-(ship_turnrate*dt) end
				if love.keyboard.isDown(p.key_up) then 
					local thrust_fx = -sin(p.player_a) *  ship_acc
					local thrust_fy = -cos(p.player_a) *  ship_acc
					p.b:applyForce (thrust_fx, thrust_fy)
					ps_ship_exhaust:setPosition (p.b:getX()+ sin(p.player_a)*ship_radius/2, p.b:getY()+cos(p.player_a)*ship_radius/2)
					ps_ship_exhaust:setDirection(-p.player_a+(3.14/2))
					ps_ship_exhaust:start()					
					end			
]]

function love.quit()
	if DEDICATED then
		print("Shutting down the server...")
	end

	if CLIENT then
		StopClient()
	end

	if SERVER then
		StopServer()
	end

	if not DEDICATED then
		save_data()
	end
end
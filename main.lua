local TILE = 48
local GRAVITY = 1650
local MOVE_SPEED = 285
local JUMP_SPEED = -710
local MAX_FALL = 900
local COYOTE_TIME = 0.12
local JUMP_BUFFER_TIME = 0.14

local assets = {}
local music
local levels = {}
local levelIndex = 1
local level
local player
local camera = {x = 0, y = 0}
local state = "title"
local messageTimer = 0
local floatTimer = 0
local fonts = {}

local function rectsOverlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function makeRect(x, y, w, h)
  return {x = x, y = y, w = w, h = h}
end

local function loadImage(path)
  local image = love.graphics.newImage(path)
  image:setFilter("nearest", "nearest")
  return image
end

local function drawImage(name, x, y, w, h, flip)
  local img = assets[name]
  if not img then return end
  local sx = w / img:getWidth()
  local sy = h / img:getHeight()
  if flip then
    love.graphics.draw(img, x + w, y, 0, -sx, sy)
  else
    love.graphics.draw(img, x, y, 0, sx, sy)
  end
end

local function makeRelaxingMusic()
  if not love.sound or not love.audio then return nil end

  local rate = 22050
  local seconds = 24
  local samples = rate * seconds
  local data = love.sound.newSoundData(samples, rate, 16, 1)
  local chords = {
    {261.63, 329.63, 392.00},
    {196.00, 293.66, 392.00},
    {220.00, 261.63, 329.63},
    {174.61, 261.63, 349.23},
  }

  for i = 0, samples - 1 do
    local t = i / rate
    local beat = math.floor(t / 0.5)
    local chord = chords[(math.floor(beat / 4) % #chords) + 1]
    local arp = chord[(beat % #chord) + 1]
    local bass = chord[1] * 0.5
    local shimmer = chord[((beat + 1) % #chord) + 1] * 2
    local pulse = 0.65 + 0.35 * math.sin(t * math.pi * 2)
    local fade = math.min(1, t / 1.2, (seconds - t) / 1.2)
    local sample =
      math.sin(t * bass * math.pi * 2) * 0.07 +
      math.sin(t * arp * math.pi * 2) * 0.10 * pulse +
      math.sin(t * shimmer * math.pi * 2) * 0.025
    data:setSample(i, sample * fade)
  end

  local source = love.audio.newSource(data, "static")
  source:setLooping(true)
  source:setVolume(0.32)
  return source
end

local function startMusic()
  if not music then return end
  if not music:isPlaying() then
    music:play()
  end
end

local function defineLevels()
  levels = {
    {
      name = "1-1: Potato Meadow",
      goal = "Grab the key and reach the door.",
      map = {
        "................................................................................",
        "................................................................................",
        "..............................................................C.................",
        ".....................C......................###..............###...............D",
        "....................###.......................................................##",
        "..........C..........................C..................E......................#",
        ".........###............E...........###...........####..###..............K.....#",
        ".........................................................#..............###....#",
        "....S.......................####.........................##....................#",
        "###########....#####.....................####...........###....#####....########",
        "###########....#####......^^^^.....###...####.....^^....###....#####....########",
      }
    },
    {
      name = "1-2: Peeler Bridge",
      goal = "Dodge the spikes and stomp the peelers.",
      map = {
        "........................................................................................",
        "........................................................................................",
        ".................C.....................................................C................",
        "...............#####...................C.........................############...........D",
        ".....................................#####............................................##",
        ".....S..........................E....................E................K.................#",
        "########......######..........#####.................#####............#####..............#",
        "########................^^.................C..................^^.......................#",
        "########...............####..............#####...............####.............E.........#",
        "########....C.........................................................###########....####",
        "########...#####......^^^^^^.....#####......^^^^^^.....#####.....^^...###########....####",
      }
    },
    {
      name = "1-3: Golden Castle",
      goal = "Enter the castle and follow the princess trail.",
      map = {
        "............................................................................................",
        "............................................................................................",
        ".................................C......................C...................................",
        "...............................#####..................#####.........................D.......",
        ".........C..............E........................................................####......",
        ".......#####..........#####.................E.....................K.........................#",
        "...............................C..........#####.................#####..............E........#",
        "....S...........^^............#####........................^^....................#####......#",
        "########......######..................###########.........######............................#",
        "########..............................###########..................#####....................#",
        "########....H........^^^^^^.....C.....###########.....^^^^^^...............^^^^^^.....#######",
      }
    },
    {
      name = "1-4: Princess Spudella",
      goal = "Find the key and rescue the princess.",
      map = {
        "................................................................................................",
        "................................................................................................",
        "..................................C............................C...............................",
        "...............................########.....................########.....................P......",
        ".............C.........E..............................................................#####....",
        "...........#####.....#####.....................E....................K..........................#",
        "....S.............................C..........#####................#####........E................#",
        "########.................^^......#####.................................^^....#####..............#",
        "########.....#####......#####......................#########............#####...................#",
        "########...............................H............#########............................D......#",
        "########....^^^^^^....########....^^^^^^^^....C.....#########....^^^^^^^^....########....########",
      }
    },
  }
end

local function newPlayer(x, y)
  return {
    x = x, y = y, w = 34, h = 48,
    vx = 0, vy = 0,
    facing = 1,
    onGround = false,
    coyote = 0,
    jumpBuffer = 0,
    jumps = 0,
    maxJumps = 2,
    chips = 0,
    hasKey = false,
    health = 3,
    invincible = 0,
    spawnX = x,
    spawnY = y,
  }
end

local function tileAt(tx, ty)
  if not level or ty < 1 or ty > #level.tiles or tx < 1 or tx > level.width then
    return "."
  end
  return level.tiles[ty]:sub(tx, tx)
end

local function isSolid(ch)
  return ch == "#" or ch == "="
end

local function setTile(tx, ty, ch)
  local row = level.tiles[ty]
  level.tiles[ty] = row:sub(1, tx - 1) .. ch .. row:sub(tx + 1)
end

local function nearbySolidRects(body)
  local rects = {}
  local left = math.floor((body.x - TILE) / TILE) + 1
  local right = math.floor((body.x + body.w + TILE) / TILE) + 1
  local top = math.floor((body.y - TILE) / TILE) + 1
  local bottom = math.floor((body.y + body.h + TILE) / TILE) + 1
  for ty = top, bottom do
    for tx = left, right do
      if isSolid(tileAt(tx, ty)) then
        rects[#rects + 1] = makeRect((tx - 1) * TILE, (ty - 1) * TILE, TILE, TILE)
      end
    end
  end
  return rects
end

local function moveAndCollide(body, dt)
  body.x = body.x + body.vx * dt
  for _, r in ipairs(nearbySolidRects(body)) do
    if rectsOverlap(body, r) then
      if body.vx > 0 then
        body.x = r.x - body.w
      elseif body.vx < 0 then
        body.x = r.x + r.w
      end
      body.vx = 0
    end
  end

  body.y = body.y + body.vy * dt
  body.onGround = false
  for _, r in ipairs(nearbySolidRects(body)) do
    if rectsOverlap(body, r) then
      if body.vy > 0 then
        body.y = r.y - body.h
        body.onGround = true
        body.jumps = 0
      elseif body.vy < 0 then
        body.y = r.y + r.h
      end
      body.vy = 0
    end
  end
end

local function parseLevel(index)
  local source = levels[index]
  local width = 0
  for _, row in ipairs(source.map) do
    width = math.max(width, #row)
  end

  level = {
    name = source.name,
    goal = source.goal,
    tiles = {},
    width = width,
    height = #source.map,
    chipsTotal = 0,
    enemies = {},
    doors = {},
    princess = nil,
  }

  local spawnX, spawnY = TILE, TILE
  for y, row in ipairs(source.map) do
    local padded = row .. string.rep(".", width - #row)
    for x = 1, width do
      local ch = padded:sub(x, x)
      local wx = (x - 1) * TILE
      local wy = (y - 1) * TILE
      if ch == "S" then
        spawnX, spawnY = wx + 5, wy - 6
        padded = padded:sub(1, x - 1) .. "." .. padded:sub(x + 1)
      elseif ch == "C" then
        level.chipsTotal = level.chipsTotal + 1
      elseif ch == "E" then
        level.enemies[#level.enemies + 1] = {x = wx + 5, y = wy + 4, w = 38, h = 42, vx = 95, startX = wx + 5, range = 150, alive = true}
        padded = padded:sub(1, x - 1) .. "." .. padded:sub(x + 1)
      elseif ch == "D" then
        level.doors[#level.doors + 1] = makeRect(wx + 6, wy + 2, TILE - 12, TILE - 4)
      elseif ch == "P" then
        level.princess = makeRect(wx + 7, wy + 1, TILE - 14, TILE - 2)
      end
    end
    level.tiles[y] = padded
  end

  player = newPlayer(spawnX, spawnY)
  camera.x, camera.y = 0, 0
  messageTimer = 2.5
  state = "playing"
end

local function resetLevel()
  parseLevel(levelIndex)
end

local function damagePlayer()
  if player.invincible > 0 then return end
  player.health = player.health - 1
  player.invincible = 1.2
  player.vy = JUMP_SPEED * 0.6
  player.vx = -player.facing * 180
  if player.health <= 0 then
    player.health = 3
    parseLevel(levelIndex)
  end
end

local function collectAt(tx, ty, ch)
  if ch == "C" then
    player.chips = player.chips + 1
    setTile(tx, ty, ".")
  elseif ch == "K" then
    player.hasKey = true
    setTile(tx, ty, ".")
    messageTimer = 2
  elseif ch == "H" then
    player.health = math.min(3, player.health + 1)
    setTile(tx, ty, ".")
  elseif ch == "^" then
    damagePlayer()
  end
end

local function collectTiles()
  local left = math.floor(player.x / TILE) + 1
  local right = math.floor((player.x + player.w) / TILE) + 1
  local top = math.floor(player.y / TILE) + 1
  local bottom = math.floor((player.y + player.h) / TILE) + 1
  for ty = top, bottom do
    for tx = left, right do
      collectAt(tx, ty, tileAt(tx, ty))
    end
  end
end

local function advanceLevel()
  if levelIndex == #levels then
    state = "rescued"
  else
    levelIndex = levelIndex + 1
    parseLevel(levelIndex)
  end
end

local function checkGoal()
  for _, door in ipairs(level.doors) do
    if rectsOverlap(player, door) then
      if player.hasKey then
        state = "levelComplete"
        messageTimer = 1.2
      else
        messageTimer = 1.5
      end
    end
  end

  if level.princess and rectsOverlap(player, level.princess) and player.hasKey then
    state = "rescued"
  end
end

local function updateEnemies(dt)
  for _, enemy in ipairs(level.enemies) do
    if enemy.alive then
      enemy.x = enemy.x + enemy.vx * dt
      if math.abs(enemy.x - enemy.startX) > enemy.range then
        enemy.vx = -enemy.vx
      end
      for _, r in ipairs(nearbySolidRects(enemy)) do
        if rectsOverlap(enemy, r) then
          if enemy.vx > 0 then
            enemy.x = r.x - enemy.w
          else
            enemy.x = r.x + r.w
          end
          enemy.vx = -enemy.vx
        end
      end

      if rectsOverlap(player, enemy) and player.invincible <= 0 then
        local fallingOntoEnemy = player.vy > 80 and player.y + player.h - enemy.y < 22
        if fallingOntoEnemy then
          enemy.alive = false
          player.vy = JUMP_SPEED * 0.55
          player.chips = player.chips + 1
        else
          damagePlayer()
        end
      end
    end
  end
end

local function tryBufferedJump()
  if player.jumpBuffer <= 0 then return end

  local canUseGroundJump = player.onGround or player.coyote > 0
  if canUseGroundJump or player.jumps < player.maxJumps then
    player.vy = JUMP_SPEED
    player.onGround = false
    player.coyote = 0
    player.jumpBuffer = 0
    if canUseGroundJump then
      player.jumps = 1
    else
      player.jumps = player.jumps + 1
    end
  end
end

local function updatePlayer(dt)
  local left = love.keyboard.isDown("left", "a")
  local right = love.keyboard.isDown("right", "d")
  if left == right then
    player.vx = player.vx * math.pow(0.001, dt)
  elseif left then
    player.vx = -MOVE_SPEED
    player.facing = -1
  elseif right then
    player.vx = MOVE_SPEED
    player.facing = 1
  end

  tryBufferedJump()
  player.vy = math.min(MAX_FALL, player.vy + GRAVITY * dt)
  moveAndCollide(player, dt)
  if player.onGround then
    player.coyote = COYOTE_TIME
  else
    player.coyote = math.max(0, player.coyote - dt)
  end
  tryBufferedJump()
  collectTiles()
  checkGoal()

  if player.y > level.height * TILE + 240 then
    damagePlayer()
    player.x, player.y = player.spawnX, player.spawnY
    player.vx, player.vy = 0, 0
  end

  player.invincible = math.max(0, player.invincible - dt)
  player.jumpBuffer = math.max(0, player.jumpBuffer - dt)
end

local function updateCamera(dt)
  local screenW = love.graphics.getWidth()
  local screenH = love.graphics.getHeight()
  local targetX = player.x + player.w / 2 - screenW / 2
  local maxX = math.max(0, level.width * TILE - screenW)
  camera.x = camera.x + (math.max(0, math.min(maxX, targetX)) - camera.x) * math.min(1, dt * 8)
  camera.y = math.max(0, math.min(level.height * TILE - screenH, 0))
end

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  fonts.hud = love.graphics.newFont(18)
  fonts.title = love.graphics.newFont(36)
  assets.potato = loadImage("Retina/character_roundYellow.png")
  assets.princess = loadImage("Retina/character_squarePurple.png")
  assets.grass = loadImage("Retina/tile_grass.png")
  assets.stone = loadImage("Retina/tile_stone.png")
  assets.chip = loadImage("Retina/tile_coin.png")
  assets.key = loadImage("Retina/tile_key.png")
  assets.door = loadImage("Retina/tile_door.png")
  assets.heart = loadImage("Retina/tile_heart.png")
  assets.spikes = loadImage("Retina/tile_spikes.png")
  assets.cloud = loadImage("Retina/background_cloudA.png")
  assets.tree = loadImage("Retina/background_tree.png")
  music = makeRelaxingMusic()
  startMusic()
  defineLevels()
  parseLevel(1)
  state = "title"
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
  elseif state == "title" and (key == "return" or key == "space") then
    parseLevel(levelIndex)
  elseif state == "levelComplete" and (key == "return" or key == "space") then
    advanceLevel()
  elseif state == "rescued" and key == "r" then
    levelIndex = 1
    parseLevel(levelIndex)
  elseif state == "playing" then
    if key == "space" or key == "up" or key == "w" then
      player.jumpBuffer = JUMP_BUFFER_TIME
    elseif key == "r" then
      resetLevel()
    end
  end
end

function love.update(dt)
  dt = math.min(dt, 1 / 30)
  floatTimer = floatTimer + dt
  messageTimer = math.max(0, messageTimer - dt)
  if state == "playing" then
    updatePlayer(dt)
    updateEnemies(dt)
    updateCamera(dt)
  end
end

local function drawBackground()
  local w = love.graphics.getWidth()
  local h = love.graphics.getHeight()
  love.graphics.clear(0.53, 0.78, 0.94)
  love.graphics.setColor(0.9, 0.97, 1, 0.75)
  love.graphics.rectangle("fill", 0, h * 0.63, w, h * 0.37)
  love.graphics.setColor(1, 1, 1)
  for i = 0, 8 do
    local x = (i * 290 - camera.x * 0.25) % (w + 280) - 160
    local y = 55 + (i % 3) * 54
    drawImage("cloud", x, y, 128, 64)
  end
end

local function drawPeeler(enemy)
  local dir = enemy.vx < 0 and -1 or 1
  love.graphics.push()
  love.graphics.translate(enemy.x + enemy.w / 2, enemy.y + enemy.h / 2)
  love.graphics.scale(dir, 1)

  love.graphics.setColor(0.76, 0.87, 0.92)
  love.graphics.polygon("fill", -20, -21, 22, -14, 17, -2, -17, -7)
  love.graphics.setColor(0.93, 0.98, 1)
  love.graphics.polygon("fill", -16, -18, 18, -12, 14, -7, -14, -10)
  love.graphics.setColor(0.45, 0.56, 0.60)
  love.graphics.setLineWidth(3)
  love.graphics.line(-20, -21, 22, -14, 17, -2, -17, -7, -20, -21)

  love.graphics.setColor(0.56, 0.78, 0.46)
  love.graphics.rectangle("fill", -8, -5, 16, 41, 6, 6)
  love.graphics.setColor(0.28, 0.46, 0.25)
  love.graphics.rectangle("line", -8, -5, 16, 41, 6, 6)
  love.graphics.setColor(0.96, 0.26, 0.23)
  love.graphics.circle("fill", 5, -9, 4)
  love.graphics.setColor(0.12, 0.13, 0.14)
  love.graphics.circle("fill", 6, -9, 1.5)

  love.graphics.setColor(0.45, 0.56, 0.60)
  love.graphics.line(-11, 25, -20, 34)
  love.graphics.line(11, 25, 20, 34)
  love.graphics.pop()
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

local function drawWorld()
  love.graphics.push()
  love.graphics.translate(-math.floor(camera.x), -math.floor(camera.y))

  for x = 0, level.width * TILE, 360 do
    drawImage("tree", x - 60, level.height * TILE - 220, 64, 128)
  end

  for ty, row in ipairs(level.tiles) do
    for tx = 1, level.width do
      local ch = row:sub(tx, tx)
      local x = (tx - 1) * TILE
      local y = (ty - 1) * TILE
      if ch == "#" then
        drawImage("grass", x, y, TILE, TILE)
      elseif ch == "=" then
        drawImage("stone", x, y, TILE, TILE)
      elseif ch == "C" then
        drawImage("chip", x + 8, y + 8 + math.sin(floatTimer * 5 + tx) * 3, 32, 32)
      elseif ch == "K" then
        drawImage("key", x + 7, y + 4 + math.sin(floatTimer * 4) * 4, 34, 34)
      elseif ch == "H" then
        drawImage("heart", x + 8, y + 7, 32, 32)
      elseif ch == "^" then
        drawImage("spikes", x, y + 10, TILE, TILE)
      elseif ch == "D" then
        drawImage("door", x, y, TILE, TILE)
      elseif ch == "P" then
        drawImage("princess", x + 4, y - 2 + math.sin(floatTimer * 3) * 2, 42, 42)
      end
    end
  end

  for _, enemy in ipairs(level.enemies) do
    if enemy.alive then
      drawPeeler(enemy)
    end
  end

  if player.invincible <= 0 or math.floor(floatTimer * 16) % 2 == 0 then
    drawImage("potato", player.x - 12, player.y - 20, 64, 64, player.facing < 0)
  end

  love.graphics.pop()
end

local function drawHud()
  love.graphics.setColor(0.07, 0.08, 0.1, 0.8)
  love.graphics.rectangle("fill", 20, 18, 430, 72, 8, 8)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(fonts.hud)
  love.graphics.print(level.name, 36, 28)
  love.graphics.print("Chips: " .. player.chips .. "/" .. level.chipsTotal .. "   Key: " .. (player.hasKey and "yes" or "no"), 36, 56)
  for i = 1, 3 do
    love.graphics.setColor(1, 1, 1, i <= player.health and 1 or 0.25)
    drawImage("heart", love.graphics.getWidth() - 42 * i - 18, 25, 32, 32)
  end
  love.graphics.setColor(1, 1, 1)
  if messageTimer > 0 then
    local text = player.hasKey and "You have the key. Run to the door!" or level.goal
    love.graphics.setColor(0.07, 0.08, 0.1, 0.78)
    love.graphics.rectangle("fill", 20, love.graphics.getHeight() - 58, 520, 38, 8, 8)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(text, 34, love.graphics.getHeight() - 48)
  end
end

local function drawPanel(title, body, action)
  drawBackground()
  love.graphics.setColor(0.07, 0.08, 0.1, 0.84)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  love.graphics.rectangle("fill", w / 2 - 290, h / 2 - 135, 580, 270, 8, 8)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(fonts.title)
  love.graphics.printf(title, w / 2 - 250, h / 2 - 95, 500, "center")
  love.graphics.setFont(fonts.hud)
  love.graphics.printf(body, w / 2 - 240, h / 2 - 32, 480, "center")
  love.graphics.setColor(0.98, 0.82, 0.22)
  love.graphics.printf(action, w / 2 - 240, h / 2 + 72, 480, "center")
end

function love.draw()
  if state == "title" then
    drawPanel(
      "Potato Rescue",
      "Poti the potato hero is rolling out to rescue Princess Spudella from the peeler patrol.\n\nRun with A/D or arrow keys, double jump with Space, and stomp peelers from above.",
      "Press Space or Enter to start"
    )
    return
  end

  drawBackground()
  drawWorld()
  drawHud()

  if state == "levelComplete" then
    drawPanel("Level Clear", "Poti is one step closer. Chips are bonus points, but the key opens the way forward.", "Press Space or Enter for the next level")
  elseif state == "rescued" then
    drawPanel("Princess Rescued", "Spudella is safe, the peelers have scattered, and the field smells like crispy victory.", "Press R to play again")
  end
end

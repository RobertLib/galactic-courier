local WINDOW_WIDTH = 800
local WINDOW_HEIGHT = 600
local LEVEL_WIDTH = 1600
local LEVEL_HEIGHT = 1200
local GRID_SIZE = 20

local font = love.graphics.newFont(20)
local world

local lives
local level

local pause = false

local camera = { x = 0, y = 0 }

local checkCollisionCircles = function(x1, y1, r1, x2, y2, r2)
  return (x1 - x2) ^ 2 + (y1 - y2) ^ 2 <= (r1 + r2) ^ 2
end

local timeouts = {}

local function setTimeout(callback, delay)
  for _, timeout in ipairs(timeouts) do
    if timeout.callback == callback then
      return
    end
  end

  table.insert(timeouts, {
    callback = callback,
    time = love.timer.getTime() + delay
  })
end

function timeouts:clear()
  for k in pairs(self) do
    if type(k) == 'number' then
      self[k] = nil
    end
  end
end

function timeouts:update()
  for i, timeout in ipairs(self) do
    if love.timer.getTime() >= timeout.time then
      timeout.callback()
      table.remove(self, i)
    end
  end
end

local particles = {}

function particles:clear()
  for k in pairs(self) do
    if type(k) == 'number' then
      self[k] = nil
    end
  end
end

function particles:create(x, y, num, speed, radius, life, color)
  for i = 1, num do
    local angle = 2 * math.pi * love.math.random()
    local randomSpeed = speed * love.math.random()
    local xVel = math.cos(angle) * randomSpeed
    local yVel = math.sin(angle) * randomSpeed

    local particle = {
      x = x,
      y = y,
      xVel = xVel,
      yVel = yVel,
      radius = radius,
      life = life
    }

    function particle:update(dt)
      self.x = self.x + self.xVel * dt
      self.y = self.y + self.yVel * dt
      self.life = self.life - dt
    end

    function particle:draw()
      love.graphics.setColor(color[1], color[2], color[3], self.life)
      love.graphics.circle('fill', self.x, self.y, self.radius)
    end

    table.insert(self, particle)
  end
end

function particles:update(dt)
  for i, particle in ipairs(self) do
    particle:update(dt)

    if particle.life <= 0 then
      table.remove(self, i)
    end
  end
end

function particles:draw()
  for _, particle in ipairs(self) do
    particle:draw()
  end
end

local gameState

local stateLoaders = {}

local function changeState(state)
  gameState = state

  if stateLoaders[state] then
    stateLoaders[state]()
  end

  timeouts:clear()
  particles:clear()
end

local function generateShootSound()
  local rate = 44100
  local length = 0.17
  local baseFrequency = 760
  local samples = rate * length
  local soundData = love.sound.newSoundData(samples, rate, 16, 1)

  for i = 0, samples - 1 do
    local time = i / rate
    local frequency = baseFrequency * (1 - time)
    local amplitude = (1 - time) * 0.5 * math.sin(2 * math.pi * frequency * time)
    amplitude = amplitude + 0.3 * (1 - time) * math.sin(2 * math.pi * (frequency * 1.5) * time)
    amplitude = amplitude + 0.2 * (1 - time) * math.sin(2 * math.pi * (frequency * 2) * time)
    amplitude = amplitude + 0.1 * (math.random() * 2 - 1) * (1 - time)
    soundData:setSample(i, amplitude)
  end

  local source = love.audio.newSource(soundData)
  source:setVolume(0.4)

  return source
end

local shootSound = generateShootSound()

local function generateExplosionSound()
  local rate = 44100
  local length = 0.5
  local baseFrequency = 760
  local samples = rate * length
  local soundData = love.sound.newSoundData(samples, rate, 16, 1)

  for i = 0, samples - 1 do
    local time = i / rate
    local frequency = baseFrequency * (1 - time)
    local amplitude = (1 - time) * 0.5 * math.sin(2 * math.pi * frequency * time)
    amplitude = amplitude + 0.3 * (1 - time) * math.sin(2 * math.pi * (frequency * 1.5) * time)
    amplitude = amplitude + 0.2 * (1 - time) * math.sin(2 * math.pi * (frequency * 2) * time)
    amplitude = amplitude + 0.1 * (math.random() * 2 - 1) * (1 - time)
    soundData:setSample(i, amplitude)
  end

  local source = love.audio.newSource(soundData)
  source:setVolume(0.4)

  return source
end

local explosionSound = generateExplosionSound()

local stars = {
  starsList = {},
  numStars = 200
}

function stars:load()
  self.starsList = {}

  for i = 1, self.numStars do
    table.insert(self.starsList, {
      x = love.math.random(0, love.graphics.getWidth()),
      y = love.math.random(0, love.graphics.getHeight()),
      intensity = love.math.random(),
      speed = love.math.random() * 0.5 + 0.5
    })
  end
end

function stars:update(dt)
  for _, star in ipairs(self.starsList) do
    star.intensity = star.intensity + star.speed * dt

    if star.intensity > 1 then
      star.intensity = 1
      star.speed = -star.speed
    elseif star.intensity < 0 then
      star.intensity = 0
      star.speed = -star.speed
    end
  end
end

function stars:draw()
  for _, star in ipairs(self.starsList) do
    love.graphics.setColor(1, 1, 1, star.intensity)
    love.graphics.points(star.x, star.y)
  end
end

local function drawGrid(objects)
  love.graphics.setColor(1, 1, 1, 0.7)

  local points = {}

  local windowWidth = love.graphics.getWidth()
  local windowHeight = love.graphics.getHeight()

  local minX = math.max(0, camera.x - windowWidth / 2)
  local maxX = math.min(LEVEL_WIDTH, camera.x + windowWidth / 2)
  local minY = math.max(0, camera.y - windowHeight / 2)
  local maxY = math.min(LEVEL_HEIGHT, camera.y + windowHeight / 2)

  minX = math.floor(minX / GRID_SIZE) * GRID_SIZE
  maxX = math.ceil(maxX / GRID_SIZE) * GRID_SIZE
  minY = math.floor(minY / GRID_SIZE) * GRID_SIZE
  maxY = math.ceil(maxY / GRID_SIZE) * GRID_SIZE

  for x = minX, maxX, GRID_SIZE do
    for y = minY, maxY, GRID_SIZE do
      local offsetX, offsetY = 0, 0

      for _, obj in ipairs(objects) do
        local dx = x - obj.x
        local dy = y - obj.y
        local distance = math.sqrt(dx * dx + dy * dy)
        local influence = math.exp(-distance / 100)

        offsetX = offsetX + influence * (obj.x - x) * 0.5
        offsetY = offsetY + influence * (obj.y - y) * 0.5
      end

      table.insert(points, x + offsetX)
      table.insert(points, y + offsetY)
    end
  end

  love.graphics.points(points)
end

local INIT_ENEMIES = 10

local enemies = {}

local INIT_COLLECTABLES = 10

local collectables = {}

local unloading = {
  x = LEVEL_WIDTH / 4,
  y = LEVEL_HEIGHT / 4,
  radius = 50,
  angle = 0,
}

function unloading:load()
  self.attachedCollectables = {}
end

function unloading:update(dt)
  self.angle = self.angle + math.pi * dt

  local angleStep = (2 * math.pi) / #self.attachedCollectables
  local radius = self.radius / 2

  for i, collectable in ipairs(self.attachedCollectables) do
    local angle = i * angleStep + self.angle
    local targetX = self.x + radius * math.cos(angle)
    local targetY = self.y + radius * math.sin(angle)
    local dx = targetX - collectable.x
    local dy = targetY - collectable.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local speed = 150

    if distance > collectable.radius then
      collectable.x = collectable.x + (dx / distance) * speed * dt
      collectable.y = collectable.y + (dy / distance) * speed * dt
    else
      collectable.x = targetX
      collectable.y = targetY
    end
  end
end

function unloading:draw()
  love.graphics.setColor(0.8, 0.8, 1)
  love.graphics.circle('line', self.x, self.y, self.radius)

  for _, collectable in ipairs(self.attachedCollectables) do
    collectable:draw()
  end
end

local spaceship = {
  x = LEVEL_WIDTH / 2,
  y = LEVEL_HEIGHT / 2,
  xVel = 0,
  yVel = 0,
  angle = -math.pi / 2,
  radius = 10,
  speed = 100,
  dead = false,
  opacity = 1,
  vertices = { 20, 0, -10, -10, -10, 10 },
  bullets = {},
  lastShotTime = 0,
  chain = {
    x = LEVEL_WIDTH / 2,
    y = LEVEL_HEIGHT / 2,
    length = 10,
    segmentLength = 20,
    chainList = {},
    joints = {}
  }
}

function spaceship:handleCollision()
  if self.dead then
    return
  end

  lives = lives - 1

  if lives <= 0 then
    changeState('gameOver')
  end

  self.dead = true
  self:explode()

  setTimeout(function()
    self:load()
  end, 1)
end

function spaceship:explode()
  particles:create(self.x, self.y, 50, 100, 5, 1, { 1, 1, 1 })
  explosionSound:play()

  for _, joint in ipairs(self.chain.joints) do
    joint:destroy()
  end

  self.chain.topJoint:destroy()
end

function spaceship.bullets:load(parent)
  self.parent = parent

  for k in pairs(self) do
    if type(k) == 'number' then
      self[k] = nil
    end
  end
end

function spaceship.bullets:createBullet()
  local SPEED = 300

  local bullet = {
    x = self.parent.x + 15 * math.cos(self.parent.angle),
    y = self.parent.y + 15 * math.sin(self.parent.angle),
    xVel = self.parent.xVel + math.cos(self.parent.angle) * SPEED,
    yVel = self.parent.yVel + math.sin(self.parent.angle) * SPEED,
    angle = self.parent.angle,
    radius = 2.5,
    vertices = { 0, 0, 5, 0 }
  }

  -- Normalize the velocity vector
  local length = math.sqrt(bullet.xVel ^ 2 + bullet.yVel ^ 2)
  bullet.xVel = bullet.xVel / length * SPEED
  bullet.yVel = bullet.yVel / length * SPEED

  function bullet:update(dt)
    self.x = self.x + self.xVel * dt
    self.y = self.y + self.yVel * dt

    for i, enemy in ipairs(enemies) do
      if checkCollisionCircles(
            self.x, self.y, self.radius, enemy.x, enemy.y, enemy.radius) then
        enemy:explode()
        table.remove(enemies, i)
        break
      end
    end
  end

  function bullet:draw()
    love.graphics.setColor(1, 1, 1)
    love.graphics.push()
    love.graphics.translate(self.x, self.y)
    love.graphics.rotate(self.angle)
    love.graphics.line(self.vertices)
    love.graphics.pop()
  end

  table.insert(self, bullet)
end

function spaceship.bullets:update(dt)
  for i, bullet in ipairs(self) do
    bullet:update(dt)

    if bullet.x < 0 or bullet.x > LEVEL_WIDTH or
        bullet.y < 0 or bullet.y > LEVEL_HEIGHT or
        bullet.x < camera.x - love.graphics.getWidth() / 2 or
        bullet.x > camera.x + love.graphics.getWidth() / 2 or
        bullet.y < camera.y - love.graphics.getHeight() / 2 or
        bullet.y > camera.y + love.graphics.getHeight() / 2 then
      table.remove(self, i)
    end
  end
end

function spaceship.bullets:draw()
  for _, bullet in ipairs(self) do
    bullet:draw()
  end
end

function spaceship.chain:load(parent, init)
  self.parent = parent

  local lastLink = self.chainList[#self.chainList]

  if not init and lastLink and lastLink.attachedCollectables then
    for _, collectable in ipairs(lastLink.attachedCollectables) do
      table.insert(collectables, collectable)
    end
  end

  self.x = self.parent.x
  self.y = self.parent.y

  for _, segment in ipairs(self.chainList) do
    if not segment.body:isDestroyed() then
      segment.body:destroy()
    end
  end

  for _, joint in ipairs(self.joints) do
    if not joint:isDestroyed() then
      joint:destroy()
    end
  end

  self.chainList = {}
  self.joints = {}

  for i = 1, self.length do
    local body = love.physics.newBody(
      world,
      self.x,
      self.y + (i - 1) * self.segmentLength,
      'dynamic')
    local shape = love.physics.newCircleShape(5)
    local fixture = love.physics.newFixture(body, shape, 1)

    table.insert(self.chainList, { body = body, shape = shape, fixture = fixture })
  end

  for i = 1, self.length - 1 do
    local joint = love.physics.newRopeJoint(
      self.chainList[i].body,
      self.chainList[i + 1].body,
      self.x,
      self.y + (i - 1) * self.segmentLength,
      self.x,
      self.y + i * self.segmentLength,
      self.segmentLength,
      false)

    table.insert(self.joints, joint)
  end

  self.topJoint = love.physics.newMouseJoint(self.chainList[1].body, self.x, self.y)
end

function spaceship.chain:update(dt)
  if not self.topJoint:isDestroyed() then
    self.topJoint:setTarget(self.parent.x, self.parent.y)
  end

  for _, segment in ipairs(self.chainList) do
    for i, enemy in ipairs(enemies) do
      if checkCollisionCircles(
            segment.body:getX(),
            segment.body:getY(),
            segment.shape:getRadius(),
            enemy.x,
            enemy.y,
            enemy.radius) then
        table.remove(enemies, i)
        self.parent:handleCollision()
        break
      end
    end
  end

  local lastLink = self.chainList[#self.chainList]
  lastLink.attachedCollectables = lastLink.attachedCollectables or {}

  for i, collectable in ipairs(collectables) do
    if checkCollisionCircles(
          lastLink.body:getX(),
          lastLink.body:getY(),
          lastLink.shape:getRadius() * 10,
          collectable.x,
          collectable.y,
          collectable.radius * 10) then
      table.insert(lastLink.attachedCollectables, collectable)
      table.remove(collectables, i)
      break
    end
  end

  local angleStep = (2 * math.pi) / #lastLink.attachedCollectables
  local radius = lastLink.shape:getRadius() + 10

  for i, collectable in ipairs(lastLink.attachedCollectables) do
    local angle = i * angleStep
    local targetX = lastLink.body:getX() + radius * math.cos(angle)
    local targetY = lastLink.body:getY() + radius * math.sin(angle)
    local dx = targetX - collectable.x
    local dy = targetY - collectable.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local speed = 150

    if distance > lastLink.shape:getRadius() + collectable.radius then
      collectable.x = collectable.x + (dx / distance) * speed * dt
      collectable.y = collectable.y + (dy / distance) * speed * dt
    else
      collectable.x = targetX
      collectable.y = targetY
    end
  end

  if checkCollisionCircles(
        lastLink.body:getX(),
        lastLink.body:getY(),
        lastLink.shape:getRadius() * 2,
        unloading.x,
        unloading.y,
        unloading.radius * 2) then
    for _, collectable in ipairs(lastLink.attachedCollectables) do
      table.insert(unloading.attachedCollectables, collectable)
    end

    lastLink.attachedCollectables = {}
  end
end

function spaceship.chain:draw()
  love.graphics.setColor(1, 1, 1, self.parent.opacity)

  for i, segment in ipairs(self.chainList) do
    love.graphics.circle(
      'line',
      segment.body:getX(),
      segment.body:getY(),
      segment.shape:getRadius())
  end

  local lastLink = self.chainList[#self.chainList]

  if lastLink.attachedCollectables then
    for _, collectable in ipairs(lastLink.attachedCollectables) do
      collectable:draw()
    end
  end
end

function spaceship:load(init)
  self.x = LEVEL_WIDTH / 2
  self.y = LEVEL_HEIGHT / 2
  self.xVel = 0
  self.yVel = 0
  self.angle = -math.pi / 2
  self.dead = false
  self.opacity = 1

  camera.x = self.x
  camera.y = self.y

  self.bullets:load(self)
  self.chain:load(self, init)
end

function spaceship:rotate(angle)
  self.angle = self.angle + angle
end

function spaceship:accelerate(dt)
  self.xVel = self.xVel + math.cos(self.angle) * self.speed * dt
  self.yVel = self.yVel + math.sin(self.angle) * self.speed * dt

  local speed = math.sqrt(self.xVel ^ 2 + self.yVel ^ 2)

  if speed > self.speed then
    self.xVel = self.xVel / speed * self.speed
    self.yVel = self.yVel / speed * self.speed
  end
end

function spaceship:move(dt)
  self.x = self.x + self.xVel * dt
  self.y = self.y + self.yVel * dt
end

function spaceship:shoot()
  if love.timer.getTime() - self.lastShotTime < 0.2 then
    return
  end

  self.bullets:createBullet()

  shootSound:play()

  self.lastShotTime = love.timer.getTime()
end

function spaceship:update(dt)
  if not self.dead then
    if love.keyboard.isDown('right') then
      self:rotate(2 * math.pi * dt)
    end
    if love.keyboard.isDown('left') then
      self:rotate(-2 * math.pi * dt)
    end
    if love.keyboard.isDown('up') then
      self:accelerate(dt)
    end
    if love.keyboard.isDown('space') then
      self:shoot()
    end
  end

  self:move(dt)

  if self.x < 0 or self.x > LEVEL_WIDTH or
      self.y < 0 or self.y > LEVEL_HEIGHT then
    self:handleCollision()
  end

  camera.x = self.x
  camera.y = self.y

  self.bullets:update(dt)
  self.chain:update(dt)

  for i, enemy in ipairs(enemies) do
    if checkCollisionCircles(
          self.x, self.y, self.radius, enemy.x, enemy.y, enemy.radius) then
      enemy:explode()
      table.remove(enemies, i)
      self:handleCollision()
      break
    end
  end

  if self.dead and self.opacity > 0 then
    self.opacity = self.opacity - dt
  end
end

function spaceship:drawThruster()
  love.graphics.setColor(0.8, 0.8, 1, self.opacity)
  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  love.graphics.rotate(self.angle)
  love.graphics.polygon('line', -30 * love.math.random() - 5, 0, -10, -5, -10, 5)
  love.graphics.pop()
end

function spaceship:draw()
  love.graphics.setColor(1, 1, 1, self.opacity)
  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  love.graphics.rotate(self.angle)
  love.graphics.polygon('line', self.vertices)
  love.graphics.pop()

  if love.keyboard.isDown('up') and not pause then
    self:drawThruster()
  end

  self.bullets:draw()
  self.chain:draw()
end

local function isEnemyPositionOccupied(x, y, radius)
  for _, enemy in ipairs(enemies) do
    if checkCollisionCircles(x, y, radius, enemy.x, enemy.y, enemy.radius) then
      return true
    end
  end

  if checkCollisionCircles(x, y, radius, spaceship.x, spaceship.y, spaceship.radius) or
      checkCollisionCircles(x, y, radius, unloading.x, unloading.y, unloading.radius) then
    return true
  end

  return false
end

local function spawnEnemy()
  local enemy

  repeat
    enemy = {
      x = 20 + love.math.random(LEVEL_WIDTH - 40),
      y = 20 + love.math.random(LEVEL_HEIGHT - 40),
      xVel = 0,
      yVel = 0,
      angle = 0,
      radius = 10,
      speed = 50,
      vertices = { 0, 10, 10, 0, 0, -10, -10, 0 }
    }
  until not isEnemyPositionOccupied(enemy.x, enemy.y, enemy.radius)

  function enemy:explode()
    particles:create(self.x, self.y, 10, 100, 2.5, 1, { 1, 0.8, 0.8 })
    explosionSound:play()
  end

  function enemy:update(dt)

  end

  function enemy:draw()
    love.graphics.setColor(1, 0.8, 0.8)
    love.graphics.push()
    love.graphics.translate(self.x, self.y)
    love.graphics.rotate(self.angle)
    love.graphics.polygon('line', self.vertices)
    love.graphics.pop()
  end

  table.insert(enemies, enemy)
end

function enemies:load()
  for k in pairs(self) do
    if type(k) == 'number' then
      self[k] = nil
    end
  end

  for i = 1, INIT_ENEMIES do
    spawnEnemy()
  end
end

function enemies:update(dt)
  for _, enemy in ipairs(self) do
    enemy:update(dt)
  end
end

function enemies:draw()
  for _, enemy in ipairs(self) do
    enemy:draw()
  end
end

local function isCollectablePositionOccupied(x, y, radius)
  for _, collectable in ipairs(collectables) do
    if checkCollisionCircles(
          x, y, radius, collectable.x, collectable.y, collectable.radius) then
      return true
    end
  end

  if checkCollisionCircles(x, y, radius, spaceship.x, spaceship.y, spaceship.radius) or
      checkCollisionCircles(x, y, radius, unloading.x, unloading.y, unloading.radius) then
    return true
  end

  for _, enemy in ipairs(enemies) do
    if checkCollisionCircles(x, y, radius, enemy.x, enemy.y, enemy.radius) then
      return true
    end
  end

  return false
end

local function spawnCollectable()
  local collectable

  repeat
    collectable = {
      x = 10 + love.math.random(LEVEL_WIDTH - 20),
      y = 10 + love.math.random(LEVEL_HEIGHT - 20),
      radius = 5
    }
  until not isCollectablePositionOccupied(
      collectable.x,
      collectable.y,
      collectable.radius)

  function collectable:update(dt)
    self.x = self.x % LEVEL_WIDTH
    self.y = self.y % LEVEL_HEIGHT
  end

  function collectable:draw()
    love.graphics.setColor(0.8, 1, 0.8)
    love.graphics.circle('line', self.x, self.y, self.radius)
  end

  table.insert(collectables, collectable)
end

function collectables:load()
  for k in pairs(self) do
    if type(k) == 'number' then
      self[k] = nil
    end
  end

  for i = 1, INIT_COLLECTABLES do
    spawnCollectable()
  end
end

function collectables:update(dt)
  for _, collectable in ipairs(self) do
    collectable:update(dt)
  end
end

function collectables:draw()
  for _, collectable in ipairs(self) do
    collectable:draw()
  end
end

local function loadLevel(init)
  stars:load()
  spaceship:load(init)
  unloading:load()
  enemies:load()
  collectables:load()
end

local function nextLevel()
  level = level + 1

  if level > 3 then
    changeState('win')
  end

  loadLevel()
end

local playing = {}

function playing:load()
  lives = 3
  level = 1

  loadLevel(true)
end

function playing:update(dt)
  if love.keyboard.isDown('escape') then
    changeState('mainMenu')
  end

  if pause then
    return
  end

  world:update(dt)

  timeouts:update()
  stars:update(dt)
  particles:update(dt)
  enemies:update(dt)
  collectables:update(dt)
  unloading:update(dt)
  spaceship:update(dt)

  if #unloading.attachedCollectables >= INIT_COLLECTABLES then
    setTimeout(nextLevel, 2)
  end
end

function playing:draw()
  stars:draw()

  love.graphics.push()

  love.graphics.translate(
    love.graphics.getWidth() / 2 - camera.x,
    love.graphics.getHeight() / 2 - camera.y)

  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle('line', 0, 0, LEVEL_WIDTH, LEVEL_HEIGHT)

  local objects = { spaceship }

  drawGrid(objects)

  particles:draw()
  enemies:draw()
  collectables:draw()
  unloading:draw()
  spaceship:draw()

  love.graphics.pop()

  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print('Collected: ' .. #unloading.attachedCollectables .. ' / ' .. INIT_COLLECTABLES, 10, 10)
  love.graphics.print('Lives: ' .. lives, 10, 40)
  love.graphics.print('Level: ' .. level, 10, 70)
end

stateLoaders.playing = playing.load

local mainMenu = {}

function mainMenu:load()

end

function mainMenu:update(dt)
  if love.keyboard.isDown('return') then
    changeState('playing')
  end
end

function mainMenu:draw()
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(
    'Galactic Courier',
    0,
    love.graphics.getHeight() / 2 - font:getHeight() / 1.25,
    love.graphics.getWidth(),
    'center')
  love.graphics.printf(
    'Press Enter to start',
    0,
    love.graphics.getHeight() / 2 + font:getHeight() / 1.25,
    love.graphics.getWidth(),
    'center')
end

stateLoaders.mainMenu = mainMenu.load

local gameOver = {}

function gameOver:load()

end

function gameOver:update(dt)
  if love.keyboard.isDown('return') then
    changeState('playing')
  end
end

function gameOver:draw()
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(
    'Game Over',
    0,
    love.graphics.getHeight() / 2 - font:getHeight() / 1.25,
    love.graphics.getWidth(),
    'center')
  love.graphics.printf(
    'Press Enter to restart',
    0,
    love.graphics.getHeight() / 2 + font:getHeight() / 1.25,
    love.graphics.getWidth(),
    'center')
end

stateLoaders.gameOver = gameOver.load

local win = {}

function win:load()

end

function win:update(dt)
  if love.keyboard.isDown('return') then
    changeState('playing')
  end
end

function win:draw()
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(
    'You win!',
    0,
    love.graphics.getHeight() / 2 - font:getHeight() / 1.25,
    love.graphics.getWidth(),
    'center')
  love.graphics.printf(
    'Press Enter to restart',
    0,
    love.graphics.getHeight() / 2 + font:getHeight() / 1.25,
    love.graphics.getWidth(),
    'center')
end

stateLoaders.win = win.load

function love.load()
  love.window.setMode(WINDOW_WIDTH, WINDOW_HEIGHT)
  love.window.setTitle('Galactic Courier')

  love.physics.setMeter(1)

  world = love.physics.newWorld(0, 0, true)

  changeState('mainMenu')
end

function love.update(dt)
  if gameState == 'playing' then
    playing:update(dt)
  elseif gameState == 'mainMenu' then
    mainMenu:update(dt)
  elseif gameState == 'gameOver' then
    gameOver:update(dt)
  elseif gameState == 'win' then
    win:update(dt)
  end
end

function love.draw()
  if gameState == 'playing' then
    playing:draw()
  elseif gameState == 'mainMenu' then
    mainMenu:draw()
  elseif gameState == 'gameOver' then
    gameOver:draw()
  elseif gameState == 'win' then
    win:draw()
  end
end

function love.keypressed(key)
  if key == 'f' then
    love.window.setFullscreen(not love.window.getFullscreen())
    stars:load()
  end

  if key == 'p' and gameState == 'playing' then
    pause = not pause
  end
end

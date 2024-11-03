local LEVEL_WIDTH = 1600
local LEVEL_HEIGHT = 1200
local GRID_SIZE = 20

local world

local checkCollisionCircleCircle = function(x1, y1, r1, x2, y2, r2)
  return (x1 - x2) ^ 2 + (y1 - y2) ^ 2 <= (r1 + r2) ^ 2
end

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
  love.graphics.setColor(1, 1, 1, 0.5)

  local points = {}

  for x = 0, LEVEL_WIDTH, GRID_SIZE do
    for y = 0, LEVEL_HEIGHT, GRID_SIZE do
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

local enemies = {}

local spaceship = {
  x = love.graphics.getWidth() / 2,
  y = love.graphics.getHeight() / 2,
  xVel = 0,
  yVel = 0,
  angle = -math.pi / 2,
  radius = 10,
  speed = 100,
  vertices = { 20, 0, -10, -10, -10, 10 },
  bullets = {},
  lastShotTime = 0,
  chain = {
    x = love.graphics.getWidth() / 2,
    y = love.graphics.getHeight() / 2,
    length = 10,
    segmentLength = 20,
  }
}

function spaceship.bullets:load(parent)
  self.parent = parent
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
      if checkCollisionCircleCircle(
            self.x, self.y, self.radius, enemy.x, enemy.y, enemy.radius) then
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
        bullet.y < 0 or bullet.y > LEVEL_HEIGHT then
      table.remove(self, i)
    end
  end
end

function spaceship.bullets:draw()
  for _, bullet in ipairs(self) do
    bullet:draw()
  end
end

function spaceship.chain:load(parent)
  self.parent = parent

  for i = 1, self.length do
    local body = love.physics.newBody(
      world,
      self.x,
      self.y + (i - 1) * self.segmentLength,
      "dynamic")
    local shape = love.physics.newCircleShape(5)
    local fixture = love.physics.newFixture(body, shape, 1)

    table.insert(self, { body = body, shape = shape, fixture = fixture })
  end

  for i = 1, self.length - 1 do
    local joint = love.physics.newDistanceJoint(
      self[i].body,
      self[i + 1].body,
      self.x,
      self.y + (i - 1) * self.segmentLength,
      self.x,
      self.y + i * self.segmentLength,
      false)

    joint:setDampingRatio(0.01)
  end

  self.topJoint = love.physics.newMouseJoint(self[1].body, self.x, self.y)
end

function spaceship.chain:update()
  self.topJoint:setTarget(self.parent.x, self.parent.y)

  for _, segment in ipairs(self) do
    segment.body:setPosition(
      segment.body:getX() % LEVEL_WIDTH,
      segment.body:getY() % LEVEL_HEIGHT)
  end
end

function spaceship.chain:draw()
  love.graphics.setColor(1, 1, 1)

  for i, segment in ipairs(self) do
    love.graphics.circle(
      "line",
      segment.body:getX(),
      segment.body:getY(),
      segment.shape:getRadius())
  end
end

function spaceship:load()
  self.bullets:load(self)
  self.chain:load(self)
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

  self.lastShotTime = love.timer.getTime()
end

function spaceship:update(dt)
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

  self:move(dt)

  self.x = self.x % LEVEL_WIDTH
  self.y = self.y % LEVEL_HEIGHT

  self.bullets:update(dt)
  self.chain:update()
end

function spaceship:drawThruster()
  love.graphics.setColor(0.8, 0.8, 1)
  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  love.graphics.rotate(self.angle)
  love.graphics.polygon('line', -30 * love.math.random() - 5, 0, -10, -5, -10, 5)
  love.graphics.pop()
end

function spaceship:draw()
  love.graphics.setColor(1, 1, 1)
  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  love.graphics.rotate(self.angle)
  love.graphics.polygon('line', self.vertices)
  love.graphics.pop()

  if love.keyboard.isDown('up') then
    self:drawThruster()
  end

  self.bullets:draw()
  self.chain:draw()
end

local function spawnEnemy()
  local enemy = {
    x = love.math.random(LEVEL_WIDTH),
    y = love.math.random(LEVEL_HEIGHT),
    xVel = 0,
    yVel = 0,
    angle = 0,
    radius = 10,
    speed = 50,
    vertices = { 0, 10, 10, 0, 0, -10, -10, 0 }
  }

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

function enemies:update(dt)
  for _, enemy in ipairs(enemies) do
    enemy:update(dt)
  end
end

function enemies:draw()
  for _, enemy in ipairs(enemies) do
    enemy:draw()
  end
end

function love.load()
  love.window.setTitle('Galactic Courier')

  love.physics.setMeter(1)

  world = love.physics.newWorld(0, 0, true)

  stars:load()
  spaceship:load()

  for i = 1, 10 do
    spawnEnemy()
  end
end

function love.update(dt)
  world:update(dt)

  stars:update(dt)
  spaceship:update(dt)
  enemies:update(dt)
end

function love.draw()
  stars:draw()

  love.graphics.push()

  love.graphics.translate(
    love.graphics.getWidth() / 2 - spaceship.x,
    love.graphics.getHeight() / 2 - spaceship.y)

  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle('line', 0, 0, LEVEL_WIDTH, LEVEL_HEIGHT)

  local objects = { spaceship }

  drawGrid(objects)

  spaceship:draw()
  enemies:draw()

  love.graphics.pop()
end

function love.keypressed(key)
  if key == 'f' then
    love.window.setFullscreen(not love.window.getFullscreen())
    stars:load()
  end

  if key == 'r' then
    love.event.quit('restart')
  end
end

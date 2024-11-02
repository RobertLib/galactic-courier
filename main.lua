local LEVEL_WIDTH = 1600
local LEVEL_HEIGHT = 1200

local checkCollisionCircleCircle = function(x1, y1, r1, x2, y2, r2)
  return (x1 - x2) ^ 2 + (y1 - y2) ^ 2 <= (r1 + r2) ^ 2
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
  lastShotTime = 0
}

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

  local SPEED = 300

  local bullet = {
    x = self.x + 15 * math.cos(self.angle),
    y = self.y + 15 * math.sin(self.angle),
    xVel = self.xVel + math.cos(self.angle) * SPEED,
    yVel = self.yVel + math.sin(self.angle) * SPEED,
    angle = self.angle,
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
            self.x, self.y, self.radius,
            enemy.x, enemy.y, enemy.radius) then
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

  table.insert(self.bullets, bullet)

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

  for i, bullet in ipairs(self.bullets) do
    bullet:update(dt)

    if bullet.x < 0 or bullet.x > LEVEL_WIDTH or
        bullet.y < 0 or bullet.y > LEVEL_HEIGHT then
      table.remove(self.bullets, i)
    end
  end
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

  for _, bullet in ipairs(self.bullets) do
    bullet:draw()
  end
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

  for i = 1, 10 do
    spawnEnemy()
  end
end

function love.update(dt)
  spaceship:update(dt)
  enemies:update(dt)
end

function love.draw()
  love.graphics.translate(
    love.graphics.getWidth() / 2 - spaceship.x,
    love.graphics.getHeight() / 2 - spaceship.y
  )

  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle('line', 0, 0, LEVEL_WIDTH, LEVEL_HEIGHT)

  spaceship:draw()
  enemies:draw()
end

function love.keypressed(key)
  if key == 'f' then
    love.window.setFullscreen(not love.window.getFullscreen())
  end
end

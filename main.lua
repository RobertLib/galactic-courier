local spaceship = {
  x = love.graphics.getWidth() / 2,
  y = love.graphics.getHeight() / 2,
  xVel = 0,
  yVel = 0,
  angle = -math.pi / 2,
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
    vertices = { 0, 0, 5, 0 }
  }

  -- Normalize the velocity vector
  local length = math.sqrt(bullet.xVel ^ 2 + bullet.yVel ^ 2)
  bullet.xVel = bullet.xVel / length * SPEED
  bullet.yVel = bullet.yVel / length * SPEED

  function bullet:update(dt)
    self.x = self.x + self.xVel * dt
    self.y = self.y + self.yVel * dt
  end

  function bullet:draw()
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

  for i, bullet in ipairs(self.bullets) do
    bullet:update(dt)

    if bullet.x < 0 or bullet.x > love.graphics.getWidth() or
        bullet.y < 0 or bullet.y > love.graphics.getHeight() then
      table.remove(self.bullets, i)
    end
  end
end

function spaceship:drawThruster()
  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  love.graphics.rotate(self.angle)
  love.graphics.polygon('line', -30 * math.random() - 5, 0, -10, -5, -10, 5)
  love.graphics.pop()
end

function spaceship:draw()
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

function love.load()

end

function love.update(dt)
  spaceship:update(dt)
end

function love.draw()
  spaceship:draw()
end

function love.keypressed(key)
  if key == 'f' then
    love.window.setFullscreen(not love.window.getFullscreen())
  end
end

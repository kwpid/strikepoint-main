local BallPhysics = {}
local Config = require(script.Parent.BallConfig)

function BallPhysics.new(initialPosition)
        local self = {
                position = initialPosition or Vector3.new(0, 10, 0),
                velocity = Vector3.new(0, 0, 0),
                isMoving = false,
                hitCount = 0,
                lastHitter = "None",
                bounceCount = 0,
                color = Color3.new(1, 1, 1),
                transparency = 0,
        }

        setmetatable(self, { __index = BallPhysics })
        return self
end

function BallPhysics:applyHit(direction, customSpeed, hitterName)
        self.hitCount = self.hitCount + 1
        if hitterName then
                self.lastHitter = hitterName
        end

        self.bounceCount = 0

        local speed
        if customSpeed then
                speed = customSpeed
        else
                if self.hitCount == 1 then
                        speed = Config.Physics.START_SPEED
                else
                        speed = Config.Physics.START_SPEED + (self.hitCount - 1) * Config.Physics.SPEED_INCREMENT
                end
        end

        speed = math.min(speed, Config.Physics.MAX_SPEED)

        self.velocity = direction.Unit * speed
        self.isMoving = true

        return speed
end

function BallPhysics:update(dt, raycastFunc, groundHeight, radius, onCollision)
        radius = radius or 2
        if not self.isMoving then
                return false
        end

        self.velocity = self.velocity * (Config.Physics.DECELERATION ^ (dt * 60))

        local currentSpeed = self.velocity.Magnitude
        if currentSpeed < Config.Physics.GRAVITY_THRESHOLD then
                local gravityForce = Config.Physics.GRAVITY * dt * 60
                self.velocity = Vector3.new(self.velocity.X, self.velocity.Y - gravityForce, self.velocity.Z)
        end

        local postGravitySpeed = self.velocity.Magnitude

        if postGravitySpeed < Config.Physics.MIN_SPEED then
                local horizontalSpeed = Vector3.new(self.velocity.X, 0, self.velocity.Z).Magnitude
                local verticalSpeed = math.abs(self.velocity.Y)

                if horizontalSpeed < 0.5 and verticalSpeed < 0.1 then
                        self.velocity = Vector3.new(0, 0, 0)
                        self.isMoving = false
                        return false
                end
        end

        local moveDistance = self.velocity * dt
        local distanceMagnitude = moveDistance.Magnitude
        local stepSize = math.max(2, math.min(distanceMagnitude * 0.1, 5))
        local steps = math.max(1, math.ceil(distanceMagnitude / stepSize))
        local stepVector = moveDistance / steps

        for i = 1, steps do
                local nextPosition = self.position + stepVector
                local bounceHeight = groundHeight + Config.Physics.FLOAT_HEIGHT
                local crossedFloorPlane = nextPosition.Y <= bounceHeight and self.velocity.Y < -1

                if crossedFloorPlane then
                        local currentSpeed = self.velocity.Magnitude
                        local velocityDirection = self.velocity.Unit
                        local impactAngle = math.deg(math.asin(math.abs(velocityDirection.Y)))

                        local shouldBounce = false

                        if impactAngle >= Config.Physics.MIN_BOUNCE_ANGLE and currentSpeed >= Config.Physics.MIN_BOUNCE_SPEED and self.bounceCount < Config.Physics.MAX_BOUNCES then
                                shouldBounce = true
                        end

                        if shouldBounce then
                                local normal = Vector3.new(0, 1, 0)
                                local reflectedVelocity = self.velocity - 2 * self.velocity:Dot(normal) * normal
                                self.velocity = reflectedVelocity * Config.Physics.GROUND_BOUNCE_ENERGY_LOSS
                                self.position = Vector3.new(nextPosition.X, bounceHeight, nextPosition.Z)
                                self.bounceCount = self.bounceCount + 1
                        else
                                self.velocity = Vector3.new(self.velocity.X, 0, self.velocity.Z) * 0.95
                                self.position = Vector3.new(nextPosition.X, bounceHeight, nextPosition.Z)
                                self.bounceCount = 0
                        end

                        if onCollision then
                                local impactSpeed = math.abs(self.velocity.Y)
                                onCollision(nil, impactSpeed)
                        end
                        break
                end

                if raycastFunc then
                        local collision = raycastFunc(self.position, nextPosition)

                        if collision then
                                local normal = collision.Normal
                                local reflectedVelocity = (self.velocity - 2 * self.velocity:Dot(normal) * normal) * Config.Physics.BOUNCE_ENERGY_LOSS
                                self.velocity = reflectedVelocity
                                local distanceTraveled = (collision.Position - self.position).Magnitude
                                local remainingDistance = math.max(0, stepVector.Magnitude - distanceTraveled)
                                remainingDistance = math.min(remainingDistance, radius * 2)
                                self.position = collision.Position
                                        + (normal * radius)
                                        + (reflectedVelocity.Unit * remainingDistance)
                                        + (normal * 0.01)

                                if self.position.Y < bounceHeight then
                                        self.position = Vector3.new(self.position.X, bounceHeight, self.position.Z)
                                end

                                if self.velocity.Magnitude < 2 then
                                        self.velocity = Vector3.new(0, 0, 0)
                                        self.isMoving = false
                                end

                                if onCollision then
                                        local impactSpeed = math.abs(self.velocity:Dot(normal))
                                        onCollision(collision, impactSpeed)
                                end
                                break
                        else
                                self.position = nextPosition
                        end
                else
                        self.position = nextPosition
                end
        end

        return true
end

function BallPhysics:enforceFloatHeight(groundHeight)
        local targetHeight = groundHeight + Config.Physics.FLOAT_HEIGHT

        if self.position.Y < targetHeight then
                self.position = Vector3.new(self.position.X, targetHeight, self.position.Z)

                if self.velocity.Y < 0 then
                        self.velocity = Vector3.new(self.velocity.X, 0, self.velocity.Z)
                end
        end
end

function BallPhysics:getSpeed()
        return self.velocity.Magnitude
end

function BallPhysics:getSpeedPercent()
        return math.clamp(self:getSpeed() / Config.Physics.MAX_SPEED, 0, 1)
end

function BallPhysics:serialize()
        return {
                position = self.position,
                velocity = self.velocity,
                isMoving = self.isMoving,
                hitCount = self.hitCount,
                color = self.color,
                transparency = self.transparency or 0,
                lastHitter = self.lastHitter or "None",
        }
end

function BallPhysics:deserialize(data)
        self.position = data.position
        self.velocity = data.velocity
        self.isMoving = data.isMoving
        self.hitCount = data.hitCount
        self.lastHitter = data.lastHitter or "None"
        self.transparency = data.transparency or 0
        if data.color then
                self.color = data.color
        end
end

return BallPhysics

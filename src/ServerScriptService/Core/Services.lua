--!strict
-- Services: a tiny service registry. Bootstrap populates this with every service
-- singleton after requiring it. Services reference each other through this table
-- *at call time* (never at require time), which keeps module dependencies acyclic
-- and makes wiring explicit -- see each service's Init(services) method.
local Services = {} :: { [string]: any }

return Services

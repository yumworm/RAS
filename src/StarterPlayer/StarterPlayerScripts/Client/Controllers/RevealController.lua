--!strict
-- RevealController: the single entry point for turning a server spin result into
-- visuals. It does one thing: branch on the server-provided PresentationType and
-- hand off to the matching handler. It never invents a tier, and Standard results
-- can never reach the Flagship handler.
--
-- The client trusts the server's PresentationType and asset refs as display-only
-- instructions; inventory/income truth still comes from the state sync, not here.
local StandardRevealHandler = require(script.Parent.StandardRevealHandler)
local FlagshipRevealHandler = require(script.Parent.FlagshipRevealHandler)

local RevealController = {}
local view: any

-- view is the shared reveal surface (card, labels, glow, input lock + helpers)
-- built and owned by SpinController.
function RevealController.Init(revealView)
	view = revealView
end

function RevealController.Reveal(result)
	if type(result) ~= "table" or not view then
		return
	end
	if result.presentationType == "Flagship" then
		FlagshipRevealHandler.Reveal(view, result)
	else
		StandardRevealHandler.Reveal(view, result)
	end
end

return RevealController

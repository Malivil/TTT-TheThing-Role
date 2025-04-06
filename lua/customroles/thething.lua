local hook = hook
local IsValid = IsValid
local net = net
local player = player
local table = table
local timer = timer
local util = util

local PlayerIterator = player.Iterator

local ROLE = {}

ROLE.nameraw = "thething"
ROLE.name = "The Thing"
ROLE.nameplural = "The Things"
ROLE.nameext = "a Thing"
ROLE.nameshort = "thi"

ROLE.desc = [[You are {role}!

Sacrifice yourself while killing your enemies
to convert them and win through attrition.]]
ROLE.shortdesc = "Spreads their contamination when they kill, sacrificing themselves to convert their victim. Wins by being the last killable role left."

ROLE.team = ROLE_TEAM_INDEPENDENT

ROLE.translations = {
    ["english"] = {
        ["ev_thingcontam"] = "{victim} has been contaminated and turned into {thething}!",
        ["ev_win_thething"] = "{role} has assimilated the living and taken over",
        ["win_thething"] = "{role}'s contamination has wiped out all enemies",
        ["hilite_win_thething"] = "{role} WINS"
    }
}

ROLE.victimchangingrole = function(ply, victim)
    return victim:GetNWBool("IsContaminating", false)
end

ROLE.convars = {}
table.insert(ROLE.convars, {
    cvar = "ttt_thething_is_monster",
    type = ROLE_CONVAR_TYPE_BOOL
})
table.insert(ROLE.convars, {
    cvar = "ttt_thething_swap_lovers",
    type = ROLE_CONVAR_TYPE_BOOL
})

RegisterRole(ROLE)

local thething_is_monster = CreateConVar("ttt_thething_is_monster", "0", FCVAR_REPLICATED, "Whether the thing is on the monster team", 0, 1)

if SERVER then
    AddCSLuaFile()

    util.AddNetworkString("TTT_ThingContaminated")

    local thething_swap_lovers = CreateConVar("ttt_thething_swap_lovers", "1", FCVAR_NONE, "Whether the thing should swap lovers with their victim or not", 0, 1)

    hook.Add("Initialize", "TheThing_Initialize", function()
        WIN_THETHING = GenerateNewWinID(ROLE_THETHING)
        EVENT_THINGCONTAMINATED = GenerateNewEventID(ROLE_THETHING)
    end)

    local function SwapCupidLovers(attacker, victim)
        local attCupidSID = attacker:GetNWString("TTTCupidShooter", "")
        local attCupid = player.GetBySteamID64(attCupidSID)
        local attLoverSID = attacker:GetNWString("TTTCupidLover", "")
        local attLover = player.GetBySteamID64(attLoverSID)
        local vicSID = victim:SteamID64()

        -- Copy attacker values to victim
        victim:SetNWString("TTTCupidShooter", attCupidSID)
        victim:SetNWString("TTTCupidLover", attLoverSID)
        -- And victim values to their new lover
        if attLover and IsPlayer(attLover) then
            attLover:SetNWString("TTTCupidLover", vicSID)
            attLover:QueueMessage(MSG_PRINTBOTH, victim:Nick() .. " has been contaminated by " .. attacker:Nick() .. " and is now your lover.")
        end

        if attCupid then
            if attCupid:GetNWString("TTTCupidTarget1", "") == attacker:SteamID64() then
                attCupid:SetNWString("TTTCupidTarget1", victim:SteamID64())
            else
                attCupid:SetNWString("TTTCupidTarget2", victim:SteamID64())
            end

            local attMessage = victim:Nick() .. " has been contaminated by " .. attacker:Nick() .. " and is now "
            if attLoverSID == "" then
                attMessage = attMessage .. "waiting to be paired with a lover."
            else
                attMessage = attMessage .. "in love with " .. attLover:Nick() .. "."
            end

            attCupid:QueueMessage(MSG_PRINTBOTH, attMessage)
        end

        local vicMessage = ""
        if attLoverSID == "" then
            vicMessage = attacker:Nick() .. " had been hit by cupid's arrow so you are now waiting to be paired with a lover."
        else
            vicMessage = attacker:Nick() .. " was in love so you are now in love with " .. attLover:Nick() .. "."
        end

        victim:QueueMessage(MSG_PRINTBOTH, vicMessage)
    end

    hook.Add("PlayerDeath", "TheThing_DoPlayerDeath", function(victim, infl, attacker)
        local valid_kill = IsPlayer(attacker) and attacker ~= victim and GetRoundState() == ROUND_ACTIVE
        if not valid_kill then return end
        if not attacker:IsActiveTheThing() then return end
        if attacker:IsRoleAbilityDisabled() then return end
        if victim:ShouldActLikeJester() then return end

        local respawning = victim:IsRespawning() and victim:StopRespawning()

        attacker:SetNWBool("IsContaminating", true)
        victim:SetNWBool("IsContaminating", true)
        timer.Create("TheThingRespawn_" .. victim:SteamID64(), 0.01, 1, function()
            local attCupidSID = attacker:GetNWString("TTTCupidLover", "")
            local vicCupidSID = victim:GetNWString("TTTCupidLover", "")
            -- Only swap lovers if the swap doesn't cause a lover to die elsewhere
            if thething_swap_lovers:GetBool() and attCupidSID ~= "" and vicCupidSID == "" then
                SwapCupidLovers(attacker, victim)
            end

            victim:QueueMessage(MSG_PRINTBOTH, "You have been contaminated by " .. ROLE_STRINGS[ROLE_THETHING] .. "!")
            if respawning then
                victim:QueueMessage(MSG_PRINTBOTH, ROLE_STRINGS[ROLE_THETHING] .. "'s contamination has prevented your previous fate!")
            end
            victim:PrintMessage(HUD_PRINTTALK, "Kill others to sacrifice yourself and consume the living.")

            local body = victim.server_ragdoll or victim:GetRagdollEntity()
            victim:SetRole(ROLE_THETHING)
            victim:SpawnForRound(true)
            SetRoleHealth(victim)
            if IsValid(body) then
                victim:SetPos(FindRespawnLocation(body:GetPos()) or body:GetPos())
                victim:SetEyeAngles(Angle(0, body:GetAngles().y, 0))
                body:Remove()
            end
            SendFullStateUpdate()

            net.Start("TTT_ThingContaminated")
            net.WriteString(victim:Nick())
            net.Broadcast()

            attacker:QueueMessage(MSG_PRINTBOTH, "You have successfully contaminated " .. victim:Nick() .. ", sacrificing yourself in the process")
            attacker:Kill()

            attacker:SetNWBool("IsContaminating", false)
            victim:SetNWBool("IsContaminating", false)
        end)
    end)

    hook.Add("TTTStopPlayerRespawning", "TheThing_TTTStopPlayerRespawning", function(ply)
        if not IsPlayer(ply) then return end
        if ply:Alive() then return end

        if ply:GetNWBool("IsContaminating", false) then
            timer.Remove("TheThingRespawn_" .. ply:SteamID64())
            ply:SetNWBool("IsContaminating", false)
        end
    end)

    hook.Add("ScalePlayerDamage", "TheThing_ScalePlayerDamage", function(ply, hitgroup, dmginfo)
        if not IsPlayer(ply) or not ply:IsTheThing() then return end

        local att = dmginfo:GetAttacker()
        if not IsPlayer(att) or not att:IsTheThing() then return end

        -- Don't let some delayed damage caused by the previous Thing damage the new thing
        dmginfo:ScaleDamage(0)
        dmginfo:SetDamage(0)
    end)

    hook.Add("TTTCupidShouldLoverSurvive", "TheThing_TTTCupidShouldLoverSurvive", function(ply, lover)
        if ply:GetNWBool("IsContaminating", false) or lover:GetNWBool("IsContaminating", false) then
            return true
        end
    end)

    hook.Add("TTTCheckForWin", "TheThing_CheckForWin", function()
        -- Only independent Things win on their own
        if thething_is_monster:GetBool() then return end

        local thething_alive = false
        local other_alive = false
        for _, v in PlayerIterator() do
            if v:Alive() and v:IsTerror() then
                if v:IsTheThing() then
                    thething_alive = true
                elseif not v:ShouldActLikeJester() and not ROLE_HAS_PASSIVE_WIN[v:GetRole()] then
                    other_alive = true
                end
            end
        end

        if thething_alive and not other_alive then
            return WIN_THETHING
        elseif thething_alive then
            return WIN_NONE
        end
    end)

    hook.Add("TTTPrintResultMessage", "TheThing_PrintResultMessage", function(type)
        if type == WIN_THETHING then
            LANG.Msg("win_thething", { role = ROLE_STRINGS[ROLE_THETHING] })
            ServerLog("Result: " .. ROLE_STRINGS[ROLE_THETHING] .. " wins.\n")
            return true
        end
    end)

    hook.Add("TTTPrepareRound", "TheThing_PrepareRound", function()
        for _, v in PlayerIterator() do
            v:SetNWBool("IsContaminating", false)
            timer.Remove("TheThingRespawn_" .. v:SteamID64())
        end
    end)
end

if CLIENT then
    hook.Add("TTTSyncWinIDs", "TheThing_TTTSyncWinIDs", function()
        WIN_THETHING = WINS_BY_ROLE[ROLE_THETHING]
    end)

    hook.Add("TTTSyncEventIDs", "TheThing_TTTSyncEventIDs", function()
        EVENT_THINGCONTAMINATED = EVENTS_BY_ROLE[ROLE_THETHING]
        local contam_icon = Material("icon16/user_go.png")
        local Event = CLSCORE.DeclareEventDisplay
        local PT = LANG.GetParamTranslation
        Event(EVENT_THINGCONTAMINATED, {
            text = function(e)
                return PT("ev_thingcontam", {victim = e.vic, thething = ROLE_STRINGS[ROLE_THETHING]})
            end,
            icon = function(e)
                return contam_icon, "Contaminated"
            end})
    end)

    net.Receive("TTT_ThingContaminated", function(len)
        local name = net.ReadString()
        CLSCORE:AddEvent({
            id = EVENT_THINGCONTAMINATED,
            vic = name
        })
    end)

    hook.Add("TTTEventFinishText", "TheThing_EventFinishText", function(e)
        if e.win == WIN_THETHING then
            return LANG.GetParamTranslation("ev_win_thething", { role = ROLE_STRINGS[ROLE_THETHING] })
        end
    end)

    hook.Add("TTTEventFinishIconText", "TheThing_EventFinishIconText", function(e, win_string, role_string)
        if e.win == WIN_THETHING then
            return win_string, ROLE_STRINGS[ROLE_THETHING]
        end
    end)

    hook.Add("TTTScoringWinTitle", "TheThing_ScoringWinTitle", function(wintype, wintitles, title, secondaryWinRole)
        if wintype == WIN_THETHING then
            return { txt = "hilite_win_thething", params = { role = ROLE_STRINGS[ROLE_THETHING]:upper() }, c = ROLE_COLORS[ROLE_THETHING] }
        end
    end)

    -- Show the player's starting role icon if they were converted to The Thing and group them with their original team
    hook.Add("TTTScoringSummaryRender", "TheThing_TTTScoringSummaryRender", function(ply, roleFileName, groupingRole, roleColor, name, startingRole, finalRole)
        if finalRole == ROLE_THETHING then
            return ROLE_STRINGS_SHORT[startingRole], startingRole
        end
    end)

    hook.Add("TTTTutorialRoleText", "TheThing_TTTTutorialRoleText", function(role, titleLabel)
        if role == ROLE_THETHING then
            -- Use this for highlighting things like "kill"
            local traitorColor = ROLE_COLORS[ROLE_TRAITOR]

            local roleTeam = player.GetRoleTeam(ROLE_THETHING, true)
            local roleTeamString, roleColor = GetRoleTeamInfo(roleTeam, true)
            local html = ROLE_STRINGS[ROLE_THETHING] .. " is a member of the <span style='color: rgb(" .. roleColor.r .. ", " .. roleColor.g .. ", " .. roleColor.b .. ")'>" .. string.lower(roleTeamString) .. " team</span> whose goal is to assimilate others by killing them."

            html = html .. "<span style='display: block; margin-top: 10px;'>If the killed target <span style='color: rgb(" .. traitorColor.r .. ", " .. traitorColor.g .. ", " .. traitorColor.b .. ")'>can be assimilated</span>, they will instantly respawn and take the role of " .. ROLE_STRINGS[ROLE_THETHING] .. ".</span>"

            html = html .. "<span style='display: block; margin-top: 10px;'>Assimilating another player <span style='color: rgb(" .. traitorColor.r .. ", " .. traitorColor.g .. ", " .. traitorColor.b .. ")'>will kill " .. ROLE_STRINGS[ROLE_THETHING] .. "</span>.</span>"

            return html
        end
    end)
end

hook.Add("TTTUpdateRoleState", "TheThing_Team_TTTUpdateRoleState", function()
    local is_monster = thething_is_monster:GetBool()
    MONSTER_ROLES[ROLE_THETHING] = is_monster
    INDEPENDENT_ROLES[ROLE_THETHING] = not is_monster
end)

hook.Add("TTTIsPlayerRespawning", "TheThing_TTTIsPlayerRespawning", function(ply)
    if not IsPlayer(ply) then return end
    if ply:Alive() then return end

    if ply:GetNWBool("IsContaminating", false) then
        return true
    end
end)
local ROLE = {}

ROLE.nameraw = "thething"
ROLE.name = "The Thing"
ROLE.nameplural = "The Things"
ROLE.nameext = "a Thing"
ROLE.nameshort = "thi"

ROLE.desc = [[You are {role}!

Sacrifice yourself while killing your enemies
to convert them and win through attrition.]]

ROLE.team = ROLE_TEAM_INDEPENDENT

ROLE.translations = {
    ["english"] = {
        ["ev_thingcontam"] = "{victim} has been contaminated and turned into {thething}!",
        ["ev_win_thething"] = "{role} has assimilated the living and taken over",
        ["win_thething"] = "{role}'s contamination has wiped out all enemies",
        ["hilite_win_thething"] = "{role} WINS"
    }
}

RegisterRole(ROLE)

if SERVER then
    AddCSLuaFile()

    util.AddNetworkString("TTT_ThingContaminated")

    hook.Add("Initialize", "TheThing_Initialize", function()
        WIN_THETHING = GenerateNewWinID(ROLE_THETHING)
        EVENT_THINGCONTAMINATED = GenerateNewEventID(ROLE_THETHING)
    end)

    hook.Add("PlayerDeath", "TheThing_DoPlayerDeath", function(victim, infl, attacker)
        local valid_kill = IsPlayer(attacker) and attacker ~= victim and GetRoundState() == ROUND_ACTIVE
        if not valid_kill then return end
        if not attacker:IsTheThing() then return end
        if victim:ShouldActLikeJester() then return end

        timer.Simple(0.01, function()
            local message = "You have been contaminated by " .. ROLE_STRINGS[ROLE_THETHING] .. "!"
            victim:PrintMessage(HUD_PRINTCENTER, message)
            victim:PrintMessage(HUD_PRINTTALK, message)
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

            message = "You have successfully contaminated " .. victim:Nick() .. ", sacrificing yourself in the process"
            attacker:PrintMessage(HUD_PRINTCENTER, message)
            attacker:PrintMessage(HUD_PRINTTALK, message)
            attacker:Kill()
        end)
    end)

    hook.Add("TTTCheckForWin", "TheThing_CheckForWin", function()
        local thething_alive = false
        local other_alive = false
        for _, v in ipairs(player.GetAll()) do
            if v:Alive() and v:IsTerror() then
                if v:IsTheThing() then
                    thething_alive = true
                elseif not v:ShouldActLikeJester() then
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
end

if CLIENT then
    local function RegisterEvent()
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
    end

    if not CRVersion("1.4.6") then
        hook.Add("Initialize", "TheThing_Initialize", function()
            WIN_THETHING = GenerateNewWinID(ROLE_THETHING)
            EVENT_THINGCONTAMINATED = GenerateNewEventID(ROLE_THETHING)
            RegisterEvent()
        end)
    else
        hook.Add("TTTSyncWinIDs", "TheThing_TTTSyncWinIDs", function()
            WIN_THETHING = WINS_BY_ROLE[ROLE_THETHING]
        end)

        hook.Add("TTTSyncEventIDs", "TheThing_TTTSyncEventIDs", function()
            EVENT_THINGCONTAMINATED = EVENTS_BY_ROLE[ROLE_THETHING]
            RegisterEvent()
        end)
    end

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
            local roleColor = GetRoleTeamColor(ROLE_TEAM_INDEPENDENT)
            local html = ROLE_STRINGS[ROLE_THETHING] .. " is an <span style='color: rgb(" .. roleColor.r .. ", " .. roleColor.g .. ", " .. roleColor.b .. ")'>independent</span> role whose goal is to assimilate others by killing them."

            -- Use this for highlighting things like "kill"
            roleColor = ROLE_COLORS[ROLE_TRAITOR]

            html = html .. "<span style='display: block; margin-top: 10px;'>If the killed target <span style='color: rgb(" .. roleColor.r .. ", " .. roleColor.g .. ", " .. roleColor.b .. ")'>can be assimilated</span>, they will instantly respawn and take the role of " .. ROLE_STRINGS[ROLE_THETHING] .. ".</span>"

            html = html .. "<span style='display: block; margin-top: 10px;'>Assimilating another player <span style='color: rgb(" .. roleColor.r .. ", " .. roleColor.g .. ", " .. roleColor.b .. ")'>will kill " .. ROLE_STRINGS[ROLE_THETHING] .. "</span>.</span>"

            return html
        end
    end)
end
-- Storage.lua
-- Manages all SavedVariables for PugRaidAssignments2.
--
-- Schema (PugRaidAssignmentsDB):
--   raids = {
--     [id] = {
--       id, name, raidType,
--       documents = { [id] = { id, name, order, versions = { [id] = { id, timestamp, text } }, lastValues = { [var] = val } } },
--       sessions  = { [id] = { id, raidId, startedAt, endedAt, lastSeenAt, currentDocIndex,
--                               targetProgress = { [docId] = { assignedIcons = { [icon] = true/false } } } } },
--     }
--   }
--   activeSessionId = id | nil   -- globally unique active session

PugRaidAssignmentsStorage = {}
local S = PugRaidAssignmentsStorage

local function NewId()
    return tostring(time()) .. "_" .. tostring(math.random(100000, 999999))
end

function S.Init()
    if not PugRaidAssignmentsDB then
        PugRaidAssignmentsDB = { raids = {}, activeSessionId = nil }
    end
    if not PugRaidAssignmentsDB.raids then PugRaidAssignmentsDB.raids = {} end
end

-- ── Raids ────────────────────────────────────────────────────────────────────

function S.GetAllRaids()
    return PugRaidAssignmentsDB.raids
end

function S.GetRaid(raidId)
    return PugRaidAssignmentsDB.raids[raidId]
end

function S.CreateRaid(name, raidType)
    local id = NewId()
    PugRaidAssignmentsDB.raids[id] = {
        id        = id,
        name      = name,
        raidType  = raidType,
        documents = {},
        sessions  = {},
    }
    return PugRaidAssignmentsDB.raids[id]
end

function S.DeleteRaid(raidId)
    local db = PugRaidAssignmentsDB
    -- If active session belongs to this raid, clear it
    if db.activeSessionId then
        local raid = db.raids[raidId]
        if raid and raid.sessions[db.activeSessionId] then
            db.activeSessionId = nil
        end
    end
    db.raids[raidId] = nil
end

-- ── Documents ────────────────────────────────────────────────────────────────

function S.GetDocumentsSorted(raidId)
    local raid = S.GetRaid(raidId)
    if not raid then return {} end
    local list = {}
    for _, doc in pairs(raid.documents) do
        list[#list + 1] = doc
    end
    table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return list
end

function S.GetDocument(raidId, docId)
    local raid = S.GetRaid(raidId)
    return raid and raid.documents[docId]
end

local function NextDocOrder(raid)
    local max = 0
    for _, doc in pairs(raid.documents) do
        if (doc.order or 0) > max then max = doc.order end
    end
    return max + 1
end

function S.CreateDocument(raidId, name, initialText)
    local raid = S.GetRaid(raidId)
    if not raid then return nil end
    local docId = NewId()
    local verId = NewId()
    raid.documents[docId] = {
        id         = docId,
        name       = name,
        order      = NextDocOrder(raid),
        versions   = {
            [verId] = { id = verId, timestamp = time(), text = initialText or "" }
        },
        lastValues = {},
    }
    return raid.documents[docId]
end

function S.DeleteDocument(raidId, docId)
    local raid = S.GetRaid(raidId)
    if raid then raid.documents[docId] = nil end
end

function S.SwapDocumentOrder(raidId, docIdA, docIdB)
    local raid = S.GetRaid(raidId)
    if not raid then return end
    local a = raid.documents[docIdA]
    local b = raid.documents[docIdB]
    if a and b then
        a.order, b.order = b.order, a.order
    end
end

-- ── Versions ─────────────────────────────────────────────────────────────────

function S.GetVersionsSorted(raidId, docId)
    local doc = S.GetDocument(raidId, docId)
    if not doc then return {} end
    local list = {}
    for _, v in pairs(doc.versions) do list[#list + 1] = v end
    table.sort(list, function(a, b) return a.timestamp < b.timestamp end)
    return list
end

function S.GetLatestVersion(raidId, docId)
    local versions = S.GetVersionsSorted(raidId, docId)
    return versions[#versions]
end

function S.AddVersion(raidId, docId, text)
    local doc = S.GetDocument(raidId, docId)
    if not doc then return nil end
    local verId = NewId()
    doc.versions[verId] = { id = verId, timestamp = time(), text = text }
    return doc.versions[verId]
end

-- ── Last Values ───────────────────────────────────────────────────────────────

function S.GetLastValue(raidId, docId, varName)
    local doc = S.GetDocument(raidId, docId)
    return doc and doc.lastValues[varName]
end

function S.SetLastValue(raidId, docId, varName, value)
    local doc = S.GetDocument(raidId, docId)
    if doc then doc.lastValues[varName] = value end
end

-- ── Sessions ─────────────────────────────────────────────────────────────────

function S.GetActiveSession()
    local db = PugRaidAssignmentsDB
    if not db.activeSessionId then return nil end
    for _, raid in pairs(db.raids) do
        if raid.sessions[db.activeSessionId] then
            return raid.sessions[db.activeSessionId]
        end
    end
    return nil
end

function S.GetLastSession(raidId)
    local raid = S.GetRaid(raidId)
    if not raid then return nil end
    local last = nil
    for _, sess in pairs(raid.sessions) do
        if not last or sess.startedAt > last.startedAt then
            last = sess
        end
    end
    return last
end

function S.CreateSession(raidId)
    local raid = S.GetRaid(raidId)
    if not raid then return nil end
    local id = NewId()
    raid.sessions[id] = {
        id              = id,
        raidId          = raidId,
        startedAt       = time(),
        endedAt         = nil,
        lastSeenAt      = nil,
        currentDocIndex = 1,
        targetProgress  = {},
    }
    PugRaidAssignmentsDB.activeSessionId = id
    return raid.sessions[id]
end

function S.EndSession(session)
    if session then
        session.endedAt = time()
        if PugRaidAssignmentsDB.activeSessionId == session.id then
            PugRaidAssignmentsDB.activeSessionId = nil
        end
    end
end

function S.TouchSession(session)
    if session then session.lastSeenAt = time() end
end

-- ── Target Progress ───────────────────────────────────────────────────────────

function S.GetTargetProgress(session, docId)
    if not session.targetProgress[docId] then
        session.targetProgress[docId] = { assignedIcons = {} }
    end
    return session.targetProgress[docId]
end

function S.MarkIconAssigned(session, docId, icon)
    local tp = S.GetTargetProgress(session, docId)
    tp.assignedIcons[icon] = true
end

function S.ResetTargetProgress(session, docId)
    session.targetProgress[docId] = { assignedIcons = {} }
end

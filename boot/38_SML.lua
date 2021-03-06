-- StattenOS Markup Language Parser --
sml = {
	globalEntities = {
		quot = "\"",
		apos = "'",
		amp = "&",
		gt = ">",
		lt = "<",
	}
}

do
	local tagTypeOpen = 0
	local tagTypeSelfTerminate = 1
	local tagTypeClose = 2
	
	local nodemethods = {
		setParent = function(this, newParent) -- Set the node's parent
			if (this.parent == newParent or this == newParent or newParent.parent == this) then return false end
			if (this.parent ~= nil) then
				for i,p in pairs(this.parent.children) do if (p == this) then this.parent.children[i] = nil end end
			end
			if (newParent ~= nil) then
				table.insert(newParent.children, this)
			end
			this.parent = newParent
			return true
		end;
		
		remove = function(this) -- Remove the node from it's parent
			return this:setParent(nil)
		end;
		
		addChild = function(this, newChild)
			return newChild:setParent(this)
		end;
		
		getChildren = function(this, filter)
			if (filter) then
				local filtered = {}
				for i=1,#this.children do
					local child = this.children[i]
					if (child.name:find(filter)) then table.insert(filtered, child) end
				end
				return filtered
			else
				return this.children
			end
		end;
		
		getFirstChild = function(this, filter)
			if (filter) then
				for i=1,#this.children do
					local child = this.children[i]
					if (child.name:find(filter)) then return child end
				end
			else
				return this.children[1]
			end
		end;
		
		get = function(this, k) return this.attribs[k] end;
		gett = function(this, k, tk) if (type(this.attribs[k] == "table")) then return this.attribs[k][tk] end end;
		set = function(this, k, v) this.attribs[k] = v end;
		sett = function(this, k, tk, v) this.attribs[k] = this.attribs[k] or {} if (type(this.attribs[k] == "table")) then this.attribs[k][tk] = v end end;
		
	}
	local nodemeta = {__index = nodemethods}
	
	sml.nodemeta = nodemeta -- Some modules require this in order to extend node functionality
	
	local function getCurrentLine(s, ptr)
		local i = 1
		for _ in s:sub(1,ptr):gmatch("\n") do i = i + 1 end
		return i
	end
	
	local function firstChar(s) -- Find the first non-whitespace character
		local i,j,m = s:find("([^%s])")
		return m,j
	end
	
	local function removeComments(s)
		return s:gsub("<!%-%-.->", "")
	end
	
	local function replaceEntities(s, entities)
		return s:gsub("&([%w%d%p]+);", function(k)
			local p1, p2 = k:match("(%w+):(.+)")
			if (p1 and p2) then
				local f = entities[p1]
				if (f and type(f) == "function") then
					return f(p2)
				else
					return "&"..k..";"
				end
			else
				local v = entities[k]
				if (v) then return v else return "&"..k..";" end
			end
		end)
	end
	
	local function parseAttribs(s, doc)
		local tbl = {}
		for k,v in s:gmatch("%s-(%w+)%s-=%s-[\"']([^<>\"']+)[\"']") do
			tbl[k] = replaceEntities(v, doc.entities)
		end
		return tbl
	end
	
	local function parseTag(s, doc)
		local nc = firstChar(s)
		if (not nc) then return nil, nil, nil end
		if (nc ~= "<") then return nil, nil, "Unexpected token '"..nc.."'" end
		local i, j, name, attribs, terminate = s:find("%s-<([%w%.]+)%s-(.-)(/?)>") -- Try to match open or self-terminating tag
		if (not i) then
			i, j, name = s:find("%s-</%s-([%w%.]+)%s->") -- Try to match close tag
			if (not i) then return nil, nil, "malformed tag" end
			return {name = name}, tagTypeClose, nil
		end
		local attribTbl = parseAttribs(attribs, doc)
		if (not attribTbl) then return nil, nil, "malformed tag attributes" end
		local tagType
		if (terminate:len() > 0 and terminate ~= " ") then tagType = tagTypeSelfTerminate else tagType = tagTypeOpen end
		local newTag = {
			name = name,
			attribs = attribTbl,
			children = {}
		}
		setmetatable(newTag, nodemeta)
		return newTag, tagType, nil
	end
	
	local function tryGetInnerText(s, tagname)
		local i, j, t = s:find("([^<>\"']+)</"..tagname..">")
		if (t and (t:gsub("%s", ""):len() > 0)) then return t else return nil end
	end
	
	local function parse(s)
		local starttime = os.clock()
		local doc = {name = "documentroot", ln = 0, children = {}, attribs = {}, entities = {}}
		setmetatable(doc, nodemeta)
		setmetatable(doc.entities, {__index = sml.globalEntities})
		doc.parent = doc
		local currentTag = doc
		local ptr = 1
		local lastPtr = 1
		local tag, tagType, reason
		s = removeComments(s)
		while (true) do
			if (os.clock() - starttime > 4.5) then event.sleep(0) starttime = os.clock() end -- This prevents the computer from crashing if loading the document takes a long time
			local i,j = s:find(">", ptr)
			local segment
			lastPtr = ptr
			if (i) then segment = s:sub(ptr, i+1); ptr = j + 1; else segment = s:sub(ptr, s:len()); ptr = s:len(); end
			tag, tagType, reason = parseTag(segment, doc)
			if (not tag and reason) then
				return nil, reason.." (Line "..getCurrentLine(s,ptr)..")" -- Failed to parse next tag
			elseif (not tag and currentTag ~= doc) then -- Tag was not closed
				return nil, "Missing </"..currentTag.name.."> (Line "..getCurrentLine(s,ptr)..")"
			elseif (not tag and currentTag == doc) then -- End of document
				break
			elseif (tag and tagType == tagTypeOpen) then -- New open tag
				local i,j = s:find(">", ptr)
				local segment, nptr
				if (i) then segment = s:sub(ptr, i+1); nptr = j + 1; else segment = s:sub(ptr, s:len()); nptr = s:len(); end
				local innertxt = tryGetInnerText(segment, tag.name)
				tag.parent = currentTag
				table.insert(currentTag.children, tag)
				if (innertxt) then
					tag.innerText = replaceEntities(innertxt, doc.entities)
					ptr = nptr
				else
					currentTag = tag
				end
				tag.ln = getCurrentLine(s,ptr)
			elseif (tag and tagType == tagTypeSelfTerminate) then -- New self-terminating tag
				tag.parent = currentTag
				table.insert(currentTag.children, tag)
				tag.ln = getCurrentLine(s,ptr)
			elseif (tag and tagType == tagTypeClose) then -- Close parent tag
				if (currentTag == doc) then
					return nil, "Floating closing tag (Line "..getCurrentLine(s,ptr)..")"
				elseif (tag.name ~= currentTag.name) then
					return nil, "Expected </"..currentTag.name.."> got </"..tag.name.."> (Line "..getCurrentLine(s,ptr)..")"
				else
					currentTag = currentTag.parent
				end
			else
				return nil, "Unknown error (Line "..getCurrentLine(s,ptr)..")"
			end
		end
		return doc, "Document loaded"
	end
	sml.parse = parse
	
	local newNode = function(name)
		checkArg(1, name, "string", "nil")
		name = name or "node"
		local newNode = {
			name = name,
			children = {},
			attribs = {}
		}
		setmetatable(newNode, nodemeta)
		return newNode
	end
	sml.newNode = newNode
	
	local isNode = function(o)
		if (type(o) ~= "table" or getmetatable(o) ~= nodemeta) then return false end
		return true
	end
	sml.isNode = isNode
	
	
	
	
end


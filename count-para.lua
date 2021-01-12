--[[

Make all 'regular' paragraphs into a div and assign a numeric ID
Format this number in the margin

Copyright © 2021 Michael Cysouw <cysouw@mac.com>

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
]]

local count = 0
local chapter = 0
local indexUserID = {}

------------------------------
-- Options with default values
------------------------------

local resetAtChapter = false
local enclosing = "[]"
local refName = "paragraph "
local addPageNr = true

function getUserSettings (meta)

  if meta.resetAtChapter ~= nil then
    resetAtChapter = meta.resetAtChapter
  end

  if meta.enclosing ~= nil then
    enclosing = pandoc.utils.stringify(meta.enclosing)
  end

  if meta.refName ~= nil then
    refName = pandoc.utils.stringify(meta.refName)
    if FORMAT:match "latex" then
      if refName == "#" then refName = "\\#" end
    end
  end

  if meta.addPageNr ~= nil then
    addPageNr = meta.addPageNr
  end

end

------------------------
-- Add global formatting
------------------------

function addFormatting (meta)

  local tmp = meta['header-includes']
              or pandoc.MetaList{meta['header-includes']}
  
  if FORMAT:match "html" then
    local css = [[ 
    <style>
    .paragraph-number sup { 
      color: grey;
      font-size: x-small;
    }
    </style>
    ]]
    tmp[#tmp+1] = pandoc.MetaBlocks(pandoc.RawBlock("html", css))
  end
  
  function addTexPreamble (tex)
    tmp[#tmp+1] = pandoc.MetaBlocks(pandoc.RawBlock("tex", tex))
  end

  if FORMAT:match "latex" then
    addTexPreamble("\\usepackage{geometry}")
    addTexPreamble("\\usepackage{marginnote}")
    addTexPreamble("\\reversemarginpar")
  end
  
  meta['header-includes'] = tmp
  return(meta)
end

-------------------------
-- count Para and add Div
-------------------------

function countPara (doc)

  for i=1,#doc.blocks do

    -- optionally reset counter
    if  doc.blocks[i].tag == "Header"
        and doc.blocks[i].level == 1
        and doc.blocks[i].classes[1] ~= "unnumbered" 
        and resetAtChapter
    then
        chapter = chapter + 1
        count = 0
    end

    -- count Para, but not if there is an Image inside
    if  doc.blocks[i].tag == "Para"
        and doc.blocks[i].content[1].tag ~= "Image"
    then
      count = count + 1	

      local ID = count
      if resetAtChapter then 
        ID = chapter.."."..count 
      end

      -- check for user-inserted IDs at the start of the paragraph
      local firstElem = pandoc.utils.stringify(doc.blocks[i].content[1])
      local userID = firstElem:match("{#(.*)}")

      if userID ~= nil then
        -- add to index
        indexUserID[userID] = ID
        -- remove reference from text
        table.remove(doc.blocks[i].content, 1)
        -- remove possible space
        if doc.blocks[i].content[1].tag == "Space" then
          table.remove(doc.blocks[i].content, 1)
        end
        -- add label for Latex
        if FORMAT:match "latex" then
          table.insert(doc.blocks[i].content, 1,
            pandoc.RawInline("tex", "\\hypertarget{"..userID.."}{")
          )
          table.insert(doc.blocks[i].content, 3, 
            pandoc.RawInline("tex", "}\\label{"..userID.."}")
          )
        end
      end

      -- add Div with class to Para	
      doc.blocks[i] = pandoc.Div( doc.blocks[i], pandoc.Attr(ID, {"paragraph-number"}))
    end

  end
  return doc
end

------------------------------
-- set in-text cross-references
------------------------------

function setCrossRefs (cite)

  local userID = cite.citations[1].id

  -- ignore other "cite" elements
  if indexUserID[userID] ~= nil then
  
    -- make in-document cross-references
    local paraID = indexUserID[userID] 
    if FORMAT:match "latex" then
      if addPageNr then
        return pandoc.RawInline("tex", 
          refName.."\\hyperlink{"..userID.."}{"..paraID.."} \
            on page~\\pageref{"..userID.."}"
          )
      else
        return pandoc.RawInline("tex", 
          refName.."\\hyperlink{"..userID.."}{"..paraID.."}"
          )
      end
    else
      return pandoc.Link(refName..paraID, "#"..paraID)
    end

  end
end


------------------------------
-- format for Latex and HTML using attributes
-- for other formats, use HTML
------------------------------

function formatNumber (div)
  
  -- only do this for Divs of the right class
  if div.classes[1] == "paragraph-number" then

    -- format number
    local string = div.identifier

    if enclosing:len() == 1 then
      string = enclosing..div.identifier..enclosing
    else
      string = enclosing:sub(1,1)..div.identifier..enclosing:sub(2,2)
    end

    if FORMAT:match "latex" then
      -- use marginnote for formatting number in margin
      local texInsert = pandoc.RawInline("tex", 
                          "\\marginnote{ \
                              \\color{lightgray} \
                              \\tiny \
                              \\textsuperscript{"..string.."} \
                          }" )
      table.insert(div.content[1].content, 1, texInsert)

    else
      
      -- insert number at start of Para
      local number = pandoc.Superscript(string)
      table.insert(div.content[1].content, 1, pandoc.Space())
      table.insert(div.content[1].content, 1, number)
      
      -- approximate negative text indent depends on size of number
      -- should be fine-tuned by whatever CSS is used
      local small = 0 
      local n = tostring(string)
      for i=1,#n do 
        if n:sub(i,i):find("[1|]") ~= nil  then small=small+1 end 
      end
      -- space + nchars - n_small_chars
      local points = 5 + string.len(string)*5 - small*1
      div.attributes = {style = "text-indent: -"..points.."px;"}
      end
    
  end

  return(div)
end

--------------------
-- basic Pandoc loop
--------------------

return {
  { Meta = addFormatting },
  { Meta = getUserSettings },
  { Pandoc = countPara },
  { Cite = setCrossRefs },
  { Div = formatNumber }
}

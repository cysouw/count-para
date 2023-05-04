--[[

Make all 'regular' paragraphs into a div and assign a numeric ID
Format this number in the margin

Copyright © 2021, 2023 Michael Cysouw <cysouw@mac.com>

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
local chapterSep = "."
local refName = "paragraph "
local addPageNr = true

function getUserSettings (meta)

  if meta.resetAtChapter ~= nil then
    resetAtChapter = meta.resetAtChapter
  end

  if meta.enclosing ~= nil then
    enclosing = pandoc.utils.stringify(meta.enclosing)
  end

  if meta.chapterSep ~= nil then
    chapterSep = pandoc.utils.stringify(meta.chapterSep)
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

  local tmp = pandoc.MetaList{meta['header-includes']}
  if meta['header-includes'] ~= nil then
    tmp = meta['header-includes']
  end
  
  if FORMAT:match "html" then
    local css = [[ 
<!-- CSS added by lua-filter 'count-para' -->
<style>
.paragraph-number { 
  float: left;
  margin-left: -5em;
  width: 4.5em;
  text-align: right;
  color: grey;
  font-size: x-small;
  padding-top: 5px;
}
</style>
    ]]
    tmp[#tmp+1] = pandoc.MetaBlocks(pandoc.RawBlock("html", css))
  end
  
  function addTexPreamble (tex)
    tmp[#tmp+1] = pandoc.MetaBlocks(pandoc.RawBlock("tex", tex))
  end

  if FORMAT:match "latex" then
    addTexPreamble("\\usepackage{xcolor}")
    addTexPreamble("\\usepackage{marginnote}")
    addTexPreamble("\\reversemarginpar")
    addTexPreamble("\\newcommand{\\paragraphnumber}[1]{\\marginnote{\\color{lightgray}\\tiny{#1}}[0pt]}")
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

    -- get Para, but not if there is an Image inside
    if  doc.blocks[i].tag == "Para"
        and doc.blocks[i].content[1].tag ~= "Image"
    then

      -- count paragraphs
      count = count + 1	
      local ID = count
      if resetAtChapter then 
        ID = chapter..chapterSep..count 
      end

      -- format number to insert
      local number = ID
      if pandoc.text.len(enclosing) == 1 then
        number = enclosing..ID..enclosing
      else
        number = pandoc.text.sub(enclosing, 1, 1)..ID..pandoc.text.sub(enclosing, 2, 2)
      end

      -- check for user-inserted ids at the start of the paragraph
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
      end

      -- insert number
      if FORMAT:match "latex" then
        -- use marginnote for formatting number in margin
        local texCount = "\\paragraphnumber{"..number.."}"
        if userID ~= nil then
          -- add target for link to the number
          texCount = "\\hypertarget{"..userID.."}{\n"..texCount.."\\label{"..userID.."}}"
        end
        -- insert after first word in Latex to keep number on same page
        table.insert(doc.blocks[i].content, 2, pandoc.RawInline("tex", texCount))
      else
        table.insert(doc.blocks[i].content, 1, pandoc.Space())
        table.insert(doc.blocks[i].content, 1, pandoc.Span(number, pandoc.Attr(tostring(ID), {"paragraph-number"})))
      end

    end
  end
  return doc
end

------------------------------
-- set in-text cross-references
------------------------------

function setCrossRefs (cite)

  local userID = cite.citations[1].id
  local paraID = indexUserID[userID] 

  -- ignore other "cite" elements
  if paraID ~= nil then
  
    -- make in-document cross-references
    if FORMAT:match "latex" then

      local texInsert = refName.."\\hyperlink{"..userID.."}{"..paraID.."}"
      if addPageNr then
        texInsert = texInsert.." on page~\\pageref{"..userID.."}"
      end
      return pandoc.RawInline("tex", texInsert)

    else
      return pandoc.Link(refName..paraID, "#"..paraID)
    end

  end
end

--------------------
-- basic Pandoc loop
--------------------

return {
  { Meta = addFormatting },
  { Meta = getUserSettings },
  { Pandoc = countPara },
  { Cite = setCrossRefs }
}

require("/scripts/util.lua")
require("/scripts/rect.lua")
require("/scripts/quest/paramtext.lua")
require("/scripts/quest/directions.lua")

function sb_replaceTags(text, selftags)
    local temptext=text
    repeat
        local lasttemptext = temptext
        if type(temptext)=="string" then
            local replacetext=""
            local replacetext_tablename=""
            local pos1=0
            local pos2=0
            local rawText = string.gsub(temptext,"-","_")
            rawText = string.gsub(rawText,"^","_")
            rawText = string.gsub(rawText,"\\<","__")
            rawText = string.gsub(rawText,"\\>","__")
            pos1=string.find(rawText,"<")
            if pos1 then
                pos1=pos1-1
                pos2=string.find(rawText,">",pos1)
                if pos2 then
                    pos2=pos2-1
                    replacetext=string.sub(temptext,pos1,pos2)
                    if pos1+1<pos2 then
                        replacetext_tablename=string.sub(temptext,pos1+1,pos2-1)
                    end
                end
            end
            if replacetext_tablename~="" then
                for name,tag in pairs(selftags) do
                    if name==replacetext_tablename then
                        temptext=string.gsub(temptext,replacetext,tag)
                    end
                end
            end
        end
    until lasttemptext == temptext
    return temptext
end
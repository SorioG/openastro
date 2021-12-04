function string:split(sep)
    sep=sep or '%s'
    local t={}
    for str in self:gmatch("([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end
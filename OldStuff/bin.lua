--[[TODO
	+Add symbols
	+Better compatiblity with streamables
	+Add Hash
	+Add Data Compression
	+Add Encryption(better)
	+Create full documentation
]]
if not os.getSystemBit then error("The bin library needs the utils library!") end
bin={}
bin.Version={3,1,0}
bin.stage="stable"
bin.help=[[
For a list of features do print(bin.Features)
For a list of changes do print(bin.changelog)
For current version do print(bin.Version)
For current stage do print(bin.stage)
For help do print(bin.help) :D
]]
bin.credits=[[
Credits:
	Everything by me Ryan Ward
]]
bin.Features=bin.Version[1].."."..bin.Version[2].."."..bin.Version[3].." "..bin.stage..[[

print(bin.Features) And you get this thing
print(bin.Version) ]]..bin.Version[1].."."..bin.Version[2].."."..bin.Version[3]..[[ <-- your version
print(bin.Changlog) -- gives you a list of changes
print(bin.stage) ]]..bin.stage..[[ <-- your stage

Purpose
-------
Made to assist with the manipulation of binary data and efficent data management
Created by: Ryan Ward

Full documentation with examples of every function soon to come!!!
This is a brief doc for reference
Misc
----
nil		=	log(data,name,fmt)	-- data is the text that you want to log to a file, the name argument only needs to be called with the first log. It tells where to log to. If name is used again it will change the location of the log file.

Constructors
------------
binobj	=	bin.load(filename,s,r)	-- creates binobj from file in s and r nil then reads entire file but if not s is the start point of reading and r is either the #to read after s or from s to "#" (like string.sub())
binobj	=	bin.new(string data)	-- creates binobj from a string
binobj	=	bin.stream(file,lock)	-- creates a streamable binobj lock is defult to true if locked file is read only
binobj	=	bin.newTempFile(data)	-- creates a tempfile in stream mode
bitobj	=	bits.new(n)				-- creates bitobj from a number
vfs		=	bin.newVFS()			-- creates a new virtual file system 	--WIP
vfs		=	bin.loadVFS(path)		-- loads a saved .lvfs file				--WIP

Helpers
-------
string	=	bin.randomName(n,ext)					-- creates a random file name if n and ext is nil then a random length is used, and ".tmp" extension is added
string	=	bin.NumtoHEX(n)							-- turns number into hex
binobj	=	bin.HEXtoBin(s)							-- turns hex data into binobj
string	=	bin.HEXtoStr(s)							-- turns hex data into string/text
string	=	bin.tohex(s)							-- turns string to hex
string	=	bin.fromhex(s)							-- turns hex to string
string	=	bin.endianflop(data)					-- flips the high order bits to the low order bits and viseversa
string	=	bin.getVersion()						-- returns the version as a string
string	=	bin.escapeStr(str)						-- system function that turns functions into easy light
string	=	bin.ToStr(tab)							-- turns a table into a string (even functions are dumped; used to create compact data files)
nil		=	bin.packLLIB(name,tab,ext)				-- turns a bunch of "files" into 1 file tab is a table of file names, ext is extension if nil .llib is used Note: Currently does not support directories within .llib
nil		=	bin.unpackLLIB(name,exe,todir,over,ext)	-- takes that file and makes the files Note: if exe is true and a .lua file is in the .llib archive than it is ran after extraction ext is extension if nil .llib is used
boolean	=	bin.fileExist(path)						-- returns true if the file exist false otherwise
boolean*=	bin.closeto(a,b,v)						-- test data to see how close it is (a,b=tested data v=#difference (v must be <=255))
String	=	bin.textToBinary(txt)					-- turns text into binary data 10101010's
binobj	=	bin.decodeBits(bindata)					-- turns binary data into text
string	=	bin.trimNul(s)							-- terminates string at the nul char

Assessors
---------
nil***	=	binobj:tofile(filename)					-- writes binobj data as a file
binobj*	=	binobj:clone()							-- clones and returns a binobj
number*	=	binobj:compare(other binobj,diff)		-- returns 0-100 % of simularity based on diff factor (diff must be <=255)
string	=	binobj:sub(a,b)							-- returns string data like segment but dosen't alter the binobject
num,num	=	binobj:tonumber(a,b)					-- converts from a-b into a base 10 number so "AXG" in data becomes 4675649 returns left,right parse of data
number	=	binobj:getbyte(n)						-- gets byte at location and converts to base 10 number
bitobj	=	binobj:tobits(i)						-- returns the 8bits of data as a bitobj Ex: if value of byte was a 5 it returns a bitobj with a value of: "00000101"
string	=	binobj:getHEX(a,b)						-- gets the HEX data from 'a' to 'b' if both a,b are nil returns entire file as hex
a,b		=	binobj:scan(s,n,f)						-- searches a binobj for "s"; n is where to start looking, 'f' is weather or not to flip the string data entered 's'
string	=	binobj:streamData(a,b)					-- reads data from a to b or a can be a data handle... I will explain this and more in offical documentation
string#	=	binobj:streamread(a,b)					-- reads data from a stream object between a and b (note: while other functions start at 1 for both stream and non stream 0 is the starting point for this one)
boolean	=	binobj:canStreamWrite()					-- returns true if the binobj is streamable and isn't locked
string	=	bitobj:conv(n)							-- converts number to binary bits (system used)
binobj	=	bitobj:tobytes()						-- converts bit obj into a string byte (0-255)
number	=	bitobj:tonumber()						-- converts "10101010" to a number
boolean	=	bitobj:isover()							-- returns true if the bits exceed 8 bits false if 8 or less
string	=	bitobj:getBin()							-- returns the binary 10100100's of the data as a string

Mutators (Changes affect the actual object or if streaming the actual file) bin:remove()
--------
nil#	=	binobj:setEndOfFile(n)	-- sets the end of a file
nil		=	binobj:reverse() 		-- reverses binobj data ex: hello --> olleh
nil		=	binobj:flipbits() 		-- flips the binary bits
nil** 	=	binobj:segment(a,b)		-- gets a segment of the binobj data works just like string.sub(a,b) without str
nil*	=	binobj:insert(a,i)		-- inserts i (string or number(converts into string)) in position a
nil*	=	binobj:parseN(n)		-- removes ever (nth) byte of data
nil 	=	binobj:getlength()		-- gets length or size of binary data
nil*	=	binobj:shift(n)			-- shift the binary data by n positive --> negitive <--
nil*	=	binobj:delete(a,b)		-- deletes part of a binobj data Usage: binobj:delete(#) deletes at pos # binobj:delete(#1,#2) deletes from #1 to #2 binobj:delete("string") deletes all instances of "byte" as a string Use string.char(#) or "\#" to get byte as a string
nil*	=	binobj:encrypt(seed)	-- encrypts data using a seed, seed may be left blank
nil*	=	binobj:decrypt(seed)	-- decrypts data encrypted with encrypt(seed)
nil*	=	binobj:shuffle()		-- Shuffles the data randomly Note: there is no way to get it back!!! If original is needed clone beforehand
nil**	=	binobj:mutate(a,i)		-- changes position a's value to i
nil		=	binobj:merge(o,t)		-- o is the binobj you are merging if t is true it merges the new data to the left of the binobj EX: b:merge(o,true) b="yo" o="data" output: b="datayo" b:merge(o) b="yo" o="data" output: b="yodata"
nil*	=	binobj:parseA(n,a,t)	-- n is every byte where you add, a is the data you are adding, t is true or false true before false after
nil		=	binobj:getHEX(a,b)		-- returns the HEX of the bytes between a,b inclusive
nil		=	binobj:cryptM()			-- a mirrorable encryptor/decryptor
nil		=	binobj:addBlock(d,n)	-- adds a block of data to a binobj s is size d is data e is a bool if true then encrypts string values. if data is larger than 'n' then data is lost. n is the size of bytes the data is Note: n is no longer needed but you must use getBlock(type) to get it back
nil		=	binobj:getBlock(t,n)	-- gets block of code by type
nil		=	binobj:seek(n)			-- used with getBlock EX below with all 3
nil*	=	binobj:morph(a,b,d)		-- changes data between point a and b inclusive to d
nil		=	binobj:fill(n,d)		-- fills binobj with data "d" for n
nil		=	binobj:fillrandom(n)	-- fills binobj with random data for n
nil		=	binobj:shiftbits(n)		-- shifts all bits by n amount
nil		=	binobj:shiftbit(n,i)	-- shifts a bit ai index i by n
nil#	=	binobj:streamwrite(d,n)	-- writes to the streamable binobj d data n position
nil#	=	binobj:open()			-- opens the streamable binobj
nil#	=	binobj:close()			-- closes the streamable binobj
nil#	=	binobj:wipe()			-- erases all data in the file
nil*	=	binobj:tackB(d)			-- adds data to the beginning of a file
nil		=	binobj:tackE(d)			-- adds data to the end of a file
nil		=	binobj:parse(n,f)		-- loops through each byte calling function 'f' with the args(i,binobj,data at i)
nil		=	binobj:flipbit(i)		-- flips the binary bit at position i
nil*	=	binobj:gsub()			-- just like string:gsub(), but mutates self

numbers are written in Little-endian use bin.endianflop(d) to filp to Big-endian

Note: binobj:tonumber() returns little,big so if printing do: l,b=binobj:tonumber() print(l) print(b)

nil		=	bitobj:add(i)		-- adds i to the bitobj i can be a number (base 10) or a bitobj
nil		=	bitobj:sub(i)		-- subs i to the bitobj i can be a number (base 10) or a bitobj
nil		=	bitobj:multi(i)		-- multiplys i to the bitobj i can be a number (base 10) or a bitobj
nil		=	bitobj:div(i)		-- divides i to the bitobj i can be a number (base 10) or a bitobj
nil		=	bitobj:flipbits()	-- filps the bits 1 --> 0, 0 --> 1
string	=	bitobj:getBin()		-- returns 1's & 0's of the bitobj

# stream objects only
* not compatible with stream files
** works but do not use with large files or it works to some degree
*** all changes are made directly to the file no need to do tofile()
]]
bin.Changelog=[[
Version.Major.Minor
-------------------------
1.0.0	: initial release 	load/new/tofile/clone/closeto/compare/sub/reverse/flip/segment/insert/insert/parseN/getlength/shift
1.0.1	: update			Delete/tonumber/getbyte/
1.0.2	: update			Changed how delete works. Added encrypt/decrypt/shuffle
1.0.3	: update			Added bits class, Added in bin: tobit/mutate/parseA Added in bits: add/sub/multi/div/isover/tobyte/tonumber/flip
1.0.4	: update			Changed tobyte() to tobytes()/flipbit() to flipbits() and it now returns a binobj not str Added bin:merge
1.0.5	: update			Changed bin.new() now hex data can be inserted EX: bin.new("0xFFC353D") Added in bin: getHEX/cryptM/addBlock/getBlock/seek
1.0.6	: update			Added bin.NumtoHEX/bin:getHEX/bin.HEXtoBin/bin.HEXtoStr/bin.tohex/bin.fromhex
1.0.7	: update			Added bin:morph/bin.endianflop/bin:scan/bin.ToStr
1.0.8	: update			Added bin:fill/bin:fillrandom
1.1.0	: update			Added bin.packLLIB/bin.unpackLLIB
1.2.0	: update			Updated llib files
1.3.0	: Update			Changed bin.unpackLLIB and bin.load() Added: bin.fileExist
1.4.0	: Update			Changed bin.unpackLLIB bin.packLLIB Added: bin:shiftbits(n) bin:shiftbit(n,i)

Woot!!! Version 2
2.0.0 HUGE UPDATE			Added Streamable files!!! lua 5.1, 5.2 and 5.3 compatable!!!
#binobj is the same as binobj:getlength() but only works in 5.2 in 5.1 just use getlength() for compatibility
Now you can work with gigabyte sized data without memory crashes(streamable files[WIP]).

Stream Compatible methods:
	sub(a,b)
	getlength()
	tofile(filename)
	flipbits()
	tonumber(a,b)
	getbyte(n)
	segment(a,b)
	parse(n,f)
	tobits(i)
	reverse()
	flipbit(i)
	cryptM()
	getBlock(t,n)
	addBlock(d,n)
	shiftbits(n)
	shiftbit(n,i)
	getHEX(a,b)

Added functions in this version:
	binobj:streamwrite(d,n)
	binobj:open()
	binobj:close()
	binobj:tackB(d)
	binobj:tackE(d)
	binobj:parse(n,f)
	binobj:flipbit(i)
	bin.stream(file)
	binobj:streamData(a,b)
	bin.getVersion()
	bin.escapeStr(str)
	binobj:streamread(a,b)
	binobj:canStreamWrite()
	binobj:wipe()

Woot!!! Version 3
3.0.0 HUGE UPDATE!!!
							Added:		bin.newVFS() bin.loadVFS() bin.textToBinary(txt) bin.decodeBits(bindata) bitobj:getBin()
							Updated:	bin.addBlock() <-- Fixed error with added features to the bits.new() function that allow for new functions to work
							Notice:		The bin library now requires the utils library!!! Put utils.lua in the lua/ directory

3.1.0
							Added: bin.newTempFile(data) binobj:setEndOfFile(n) bin.randomName(n,ext)
							Updated: bin:tackE() bin:fill() bin:fillrandom() are now stream compatible!
							Notic: bin:setEndOfFile() only works on streamable files!
3.1.1
							Added: bin.trimNul(s) bin:gsub()
3.1.2
							Added: log(data,name,fmt)

							In secret something is brewing...
]]
bin.data=""
bin.t="bin"
bin.__index = bin
bin.__tostring=function(self) return self.data end
bin.__len=function(self) return self:getlength() end
bits={}
bits.data=""
bits.t="bits"
bits.__index = bits
bits.__tostring=function(self) return self.data end
bits.__len=function(self) return (#self.data)/8 end
--[[----------------------------------------
MISC
------------------------------------------]]
function log(data,name,fmt)
	if not bin.logger then
		bin.logger = bin.stream(name or "lua.log",false)
	elseif bin.logger and name then
		bin.logger:close()
		bin.logger = bin.stream(name or "lua.log",false)
	end
	local d=os.date("*t",os.time())
	bin.logger:tackE((fmt or "["..math.numfix(d.month,2).."-"..math.numfix(d.day,2).."-"..d.year.."|"..math.numfix(d.hour,2)..":"..math.numfix(d.min,2)..":"..math.numfix(d.sec,2).."]\t")..data.."\n")
end
--[[----------------------------------------
BIN
------------------------------------------]]
function bin.getVersion()
	return bin.Version[1].."."..bin.Version[2].."."..bin.Version[3]
end
--[[function bin:gsub(...)
	return self.data:gsub(...)
end
function bin:find(...)
	return self.data:find(...)
end]]
function bin:gsub(...)
	self.data=self.data:gsub(...)
end
function bin:find(...)
	self.data=self.data:find(...)
end
function bin.fromhex(str)
    return (str:gsub('..', function (cc)
        return string.char(tonumber(cc, 16))
    end))
end
if table.unpack==nil then
	table.unpack=unpack
end
function bin.tohex(str)
    return (str:gsub('.', function (c)
        return string.format('%02X', string.byte(c))
    end))
end
function bin:streamData(a,b)
	if type(a)=="table" then
		a,b,t=table.unpack(a)
	end
	if type(a)=="number" and type(b)=="string" then
		return bin.load(self.file,a,b),bin.load(self.file,a,b).data
	else
		error("Invalid args!!! Is do you have a valid stream handle or is this a streamable object?")
	end
end
function bin.new(data)
	data=tostring(data)
	local c = {}
    setmetatable(c, bin)
	data=data or ""
	if string.sub(data,1,2)=="0x" then
		data=string.sub(data,3)
		data=bin.fromhex(data)
	end
	c.data=data
	c.t="bin"
	c.Stream=false
    return c
end
function bin.stream(file,l)
	local c=bin.new()
	if bin.fileExist(file) then
		c.file=file
		c.lock = l
		c.workingfile=io.open(file,"r+")
	else
		c.file=file
		c.lock = l
		c.workingfile=io.open(file,"w")
		io.close(c.workingfile)
		c.workingfile=io.open(file,"r+")
	end
	c.Stream=true
	return c
end
function bin:streamwrite(d,n)
	if self:canStreamWrite() then
		if n then
			self.workingfile:seek("set",n)
		else
			self.workingfile:seek("set",self.workingfile:seek("end"))
		end
		self.workingfile:write(d)
	end
end
function bin:streamread(a,b)
	a=tonumber(a)
	b=tostring(b)
	return bin.load(self.file,a,b).data
end
function bin:close()
	if self:canStreamWrite() then
		self.workingfile:close()
	end
end
function bin:open()
	if self:canStreamWrite() then
		self.workingfile=io.open(self.file,"r+")
	end
end
function bin:canStreamWrite()
	return (self.Stream==true and self.lock==false)
end
function bin.load(file,s,r)
	if not(s) or not(r) then
		local f = io.open(file, "rb")
		local content = f:read("*a")
		f:close()
		return bin.new(content)
	end
	s=s or 0
	r=r or -1
	if type(r)=="number" then
		r=r+s-1
	elseif type(r)=="string" then
		r=tonumber(r) or -1
	end
    local f = io.open(file, "rb")
	f:seek("set",s)
    local content = f:read((r+1)-s)
    f:close()
    return bin.new(content)
end
function bin:tofile(filename)
	if not(filename) or self.Stream then return nil end
	io.mkFile(filename,self.data)
end
function bin.trimNul(s)
	for i=1,#s do
		if s:sub(i,i)=="\0" then
			return s:sub(1,i-1)
		end
	end
	return s
end
function bin:match(pat)
	return self.data:match(pat)
end
function bin:gmatch(pat)
	return self.data:gmatch(pat)
end
function bin.randomName(n,ext)
	n=n or math.random(7,15)
	if ext then
		a,b=ext:find(".",1,true)
		if a and b then
			ext=ext:sub(2)
		end
	end
	local str,h = "",0
	strings = {"a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z","1","2","3","4","5","6","7","8","9","0","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"}
	for i=1,n do
		h = math.random(1,#strings)
		str = str..""..strings[h]
	end
	return str.."."..(ext or "tmp")
end
function bin.newTempFile(data)
	data=data or ""
	local name=bin.randomName()
	bin.new():tofile(name)
	local tempfile=bin.stream(name,false)
	tempfile:streamwrite(data,0)
	tempfile:setEndOfFile(#data)
	return tempfile
end
function bin:wipe()
	if self:canStreamWrite() then
		os.remove(self.file)
	else
		self.data=""
	end
end
function bin:setEndOfFile(n)
	if self:canStreamWrite() then
		local name=bin.randomName()
		local tempfile=bin.stream(name,false)
		tempfile:streamwrite(self:sub(0,n-1))
		self:close()
		os.remove(self.file)
		tempfile:close()
		os.rename(name,self.file)
		self:open()
		tempfile=nil
	else
		self.data=self.data:sub(1,n)
	end
end
function bin:reverse()
	if self:canStreamWrite() then
		local x,f,b=self:getlength(),0,0
		for i=0,math.floor((x-1)/2) do
			self:streamwrite(self:sub(i+1,i+1),x-i-1)
			self:streamwrite(self:sub(x-i,x-i),i)
		end
	elseif self.Stream==false then
		self.data=string.reverse(self.data)
	end
end
function bin:flipbits()
	if self:canStreamWrite() then
		for i=0,self:getlength()-1 do
			self:streamwrite(string.char(255-string.byte(self:streamread(i,i))),i)
		end
	elseif self.Stream==false then
		local temp={}
		for i=1,#self.data do
			table.insert(temp,string.char(255-string.byte(string.sub(self.data,i,i))))
		end
		self.data=table.concat(temp,"")
	end
end
function bin:flipbit(i)
	if self:canStreamWrite() then
		self:streamwrite(string.char(255-string.byte(self:streamread(i-1,i-1))),i-1)
	elseif self.Stream==false then
		self:mutate(string.char(255-string.byte(string.sub(self.data,i,i))),i)
	end
end
function bin:segment(a,b) -- needs to be updated!!!
	if self:canStreamWrite() then
		--[[local pos=1
		for i=a,b do
			self:streamwrite(self:sub(i,i),b-a-i)
		end]]
		local temp=self:sub(a,b)
		self:close()
		local f=io.open(self.file,"w")
		f:write(temp)
		io.close(f)
		self:open()
	elseif self.Stream==false then
		self.data=string.sub(self.data,a,b)
	end
end
function bin:insert(i,a)
	if self:canStreamWrite() then
		-- do something
	elseif self.Stream==false then
		if type(i)=="number" then i=string.char(i) end
		self.data=string.sub(self.data,1,a)..i..string.sub(self.data,a+1)
	end
end
function bin:parseN(n)
	if self:canStreamWrite() then
		-- do something
	elseif self.Stream==false then
		local temp={}
		for i=1,#self.data do
			if i%n==0 then
				table.insert(temp,string.sub(self.data,i,i))
			end
		end
		self.data=table.concat(temp,"")
	end
end
function bin:parse(n,f)
	local f = f
	local n=n or 1
	if not(f) then return end
	for i=1,self:getlength() do
		if i%n==0 then
			f(i,self,self:sub(i,i))
		end
	end
end
function bin.copy(file,tofile,s)
	if not(s) then
		bin.load(file):tofile(tofile)
	else
		rf=bin.stream(file)
		wf=bin.stream(tofile,false)
		for i=1,rf:getlength(),s do
			wf:streamwrite(rf:sub(i,i-1+s))
		end
	end
end
function bin:getlength()
	if self.Stream then
		local current = self.workingfile:seek()      -- get current position
		local size = self.workingfile:seek("end")    -- get file size
		self.workingfile:seek("set", current)        -- restore position
		return size
	elseif self.Stream==false then
		return #self.data
	end
end
function bin:sub(a,b)
	if self.Stream then
		return bin.load(self.file,a-1,tostring(b-1)).data
	elseif self.Stream==false then
		return string.sub(self.data,a,b)
	end
end
function bin:tackB(d)
	if self:canStreamWrite() then
		-- do something don't know if possible
	elseif self.Stream==false then
		self.data=d..self.data
	end
end
function bin:tackE(d)
	if type(d)=="table" then
		if d:canStreamWrite() then
			d=d:sub(0,d:getlength())
		else
			d=d.data
		end
	end
	if self:canStreamWrite() then
		self:streamwrite(d)
	elseif self.Stream==false then
		self.data=self.data..d
	end
end
function bin:clone(filename)
	if self:canStreamWrite() then
		-- do something
	elseif self.Stream==false then
		return bin.new(self.data)
	end
end
function bin.closeto(a,b,v)
	if self:canStreamWrite() then
		-- do something
	elseif self.Stream==false then
		if type(a)~=type(b) then
			error("Attempt to compare unlike types")
		elseif type(a)=="number" and type(b)=="number" then
			return math.abs(a-b)<=v
		elseif type(a)=="table" and type(b)=="table" then
			if a.data and b.data then
				return (math.abs(string.byte(a.data)-string.byte(b.data)))<=v
			else
				error("Attempt to compare non-bin data")
			end
		elseif type(a)=="string" and type(b)=="string" then
			return math.abs(string.byte(a)-string.byte(b))<=v
		else
			error("Attempt to compare non-bin data")
		end
	end
end
function bin:compare(_bin,t)
	if self:canStreamWrite() then
		-- do something
	elseif self.Stream==false then
		t=t or 1
		local tab={}
		local a,b=self:getlength(),_bin:getlength()
		if not(a==b) then
			print("Unequal Lengths!!! Equalizing...")
			if a>b then
				_bin.data=_bin.data..string.rep(string.char(0),a-b)
			else
				self.data=self.data..string.rep(string.char(0),b-a)
			end
		end
		if t==1 then
			for i=1,self:getlength() do
				table.insert(tab,self:sub(i,i)==_bin:sub(i,i))
			end
		else
			for i=1,self:getlength() do
				table.insert(tab,bin.closeto(self:sub(i,i),_bin:sub(i,i),t))
			end
		end
		local temp=0
		for i=1,#tab do
			if tab[i]==true then
				temp=temp+1
			end
		end
		return (temp/#tab)*100
	end
end
function bin:shift(n)
	if self:canStreamWrite() then
		local a,b,x,p="","",self:getlength(),0
		for i=1,x do
			if i+n>x then
				p=(i+n)-(x)
			else
				p=i+n
			end
		end
	elseif self.Stream==false then
		n=n or 0
		local s=#self.data
		if n>0 then
			self.data = string.sub(self.data,s-n+1)..string.sub(self.data,1,s-n)
		elseif n<0 then
			n=math.abs(n)
			self.data = string.sub(self.data,n+1)..string.sub(self.data,1,n*1)
		end
	end
end
function bin:delete(a,b)
	if self:canStreamWrite() then
		-- do something
	elseif self.Stream==false then
		if type(a)=="string" then
			local tab={}
			for i=1,self:getlength() do
				if self:getbyte(i)~=string.byte(a) then
					table.insert(tab,self:sub(i,i))
				end
			end
			self.data=table.concat(tab)
		elseif a and not(b) then
			self.data=self:sub(1,a-1)..self:sub(a+1)
		elseif a and b then
			self.data=self:sub(1,a-1)..self:sub(b+1)
		else
			self.data=""
		end
	end
end
function bin:tonumber(a,b)
	local temp={}
	if a then
		temp.data=self:sub(a,b)
	else
		temp=self
		end
	local l,r=0,0
	local g=#temp.data
	for i=1,g do
		r=r+(256^(g)-i)*string.byte(string.sub(temp.data,i,i))
		l=l+(256^(i-1))*string.byte(string.sub(temp.data,i,i))
	end
	return l,r
end
function bin:getbyte(n)
	return string.byte(self:sub(n,n))
end
function bin:encrypt(s)
	if self:canStreamWrite() then
		s=tonumber(s) or 4546
		math.randomseed(s)
		self:shift(math.random(1,self:getlength()))
		self:flipbits()
	elseif self.Stream==false then
		s=tonumber(s) or 4546
		math.randomseed(s)
		self:shift(math.random(1,self:getlength()))
		self:flipbits()
	end
end
function bin:decrypt(s)
	if self:canStreamWrite() then
		s=tonumber(s) or 4546
		math.randomseed(s)
		self:flipbits()
		self:shift(-math.random(1,self:getlength()))
	elseif self.Stream==false then
		s=tonumber(s) or 4546
		math.randomseed(s)
		self:flipbits()
		self:shift(-math.random(1,self:getlength()))
	end
end
function bin:shuffle(s)
	if self:canStreamWrite() then
		-- do something
	elseif self.Stream==false then
		s=tonumber(s) or 4546
		math.randomseed(s)
		local t={}
			for i=1,self:getlength() do
				table.insert(t,self:sub(i,i))
			end
		local n = #t
		while n >= 2 do
			local k = math.random(n)
			t[n], t[k] = t[k], t[n]
			n = n - 1
		end
		self.data=table.concat(t)
	end
end
function bin:tobits(i)
	return bits.new(self:getbyte(i))
end
function bin:mutate(a,i)
	if self:canStreamWrite() then
		self:streamwrite(a,i-1)
	elseif self.Stream==false then
		self:delete(i)
		self:insert(a,i-1)
	end
end
function bin:parseA(n,a,t)
	if self:canStreamWrite() then
		-- do something
	elseif self.Stream==false then
		local temp={}
		for i=1,#self.data do
			if i%n==0 then
				if t then
					table.insert(temp,a)
					table.insert(temp,string.sub(self.data,i,i))
				else
					table.insert(temp,string.sub(self.data,i,i))
					table.insert(temp,a)
				end
			else
				table.insert(temp,string.sub(self.data,i,i))
			end
		end
		self.data=table.concat(temp,"")
	end
end
function bin:merge(o,t)
	if self:canStreamWrite() then
		self:close()
		self.workingfile=io.open(self.file,"a+")
		self.workingfile:write(o.data)
		self:close()
		self:open()
	elseif self.Stream==false then
		if not(t) then
			self.data=self.data..o.data
		else
			seld.data=o.data..self.data
		end
	end
end
function bin:cryptM()
	self:flipbits()
	self:reverse()
end
function bin.escapeStr(str)
	local temp=""
	for i=1,#str do
		temp=temp.."\\"..string.byte(string.sub(str,i,i))
	end
	return temp
end
function bin.ToStr(t)
	local dat="{"
	for i,v in pairs(t) do
		if type(i)=="number" then
			i="["..i.."]="
		else
			i="[\""..i.."\"]="
		end
		if type(v)=="string" then
			dat=dat..i.."[["..v.."]],"
		elseif type(v)=="number" then
			dat=dat..i..v..","
		elseif type(v)=="boolean" then
			dat=dat..i..tostring(v)..","
		elseif type(v)=="table" then
			dat=dat..i..bin.ToStr(v)..","
		elseif type(v)=="function" then
			dat=dat..i.."assert(loadstring(\""..bin.escapeStr(string.dump(v)).."\")),"
		end
	end
	return string.sub(dat,1,-2).."}"
end
function bin:addBlock(d,n,e)
	local temp={}
	if type(d)=="table" then
		if d.t=="bin" then
			temp=d
		elseif d.t=="bit" then
			temp=bin.new(d:tobytes())
		else
			self:addBlock("return "..bin.ToStr(d))
			return
		end
	elseif type(d)=="string" then
		temp=bin.new(d)
		if e or not(n) then
			temp.data=temp.data.."_EOF"
			temp:flipbits()
		end
	elseif type(d)=="function" then
		temp=bin.new(string.dump(d))
		if e or not(n) then
			temp.data=temp.data.."_EOF"
			temp:flipbits()
		end
	elseif type(d)=="number" then
		local nn=tostring(d)
		if nn:find(".",1,true) then
			temp=bin.new(nn)
			temp.data=temp.data.."_EOF"
			temp:flipbits()
		else
			temp=bits.new(d):tobytes()
			if not n then
				temp.data=temp.data.."_EOF"
				temp:flipbits()
			end
		end
	elseif type(d)=="boolean" then
		n=1
		if d then
			temp=bits.new(math.random(0,127)):tobytes()
		else
			temp=bits.new(math.random(128,255)):tobytes()
		end
	end
	if n then
		if temp:getlength()<n then
			temp:merge(bin.new(string.rep(string.char(0),n-temp:getlength())))
		elseif temp:getlength()>n then
			temp:segment(1,n)
		end
	end
	self:merge(temp)
end
function bin:getBlock(t,n)
	if not(self.Block) then
		self.Block=1
	end
	local x=self.Block
	local temp=bin.new()
	if n then
		temp=bin.new(self:sub(x,x+n-1))
		self.Block=self.Block+n
	end
	if t=="stringe" or t=="stre" or t=="se" and n then
		temp:flipbits()
		return temp.data
	elseif t=="string" or t=="str" or t=="s" and n then
		return temp.data
	elseif t=="number" or t=="num" or t=="n" and n then
		return self:tonumber(x,x+n-1)
	elseif t=="boolean" or t=="bool" or t=="b" then
		self.Block=self.Block+1
		return self:tonumber(x,x)<127
	elseif t=="stringe" or t=="stre" or t=="se" or t=="string" or t=="str" or t=="s" then
		local a,b=self:scan("_EOF",self.Block,true)
		if not(b) then return nil end
		local t=bin.new(self:sub(self.Block,b-4))
		t:flipbits()
		self.Block=self.Block+t:getlength()+4
		return tostring(t)
	elseif t=="table" or t=="tab" or t=="t" then
		temp=self:getBlock("s")
		if temp=="return }" then
			return {}
		end
		return assert(loadstring(temp))()
	elseif t=="function" or t=="func" or t=="f" then
		return assert(loadstring(self:getBlock("s")))
	elseif t=="number" or t=="num" or t=="n" then
		local num=bin.new(self:getBlock("s"))
		if tonumber(num.data) then
			return tonumber(num.data)
		end
		local a,b=num:tonumber()
		return a
	elseif n then
		-- C data
	else
		print("Invalid Args!!!")
	end
end
function bin:seek(n)
	self.Block=self.Block+n
end
function bin.NumtoHEX(num)
	local hexstr = '0123456789ABCDEF'
	local s = ''
	while num > 0 do
		local mod = math.fmod(num, 16)
		s = string.sub(hexstr, mod+1, mod+1) .. s
		num = math.floor(num / 16)
	end
	if s == '' then
		s = '0'
	end
	return s
end
function bin:getHEX(a,b,e)
	a=a or 1
	local temp = self:sub(a,b)
	if e then temp=string.reverse(temp) end
	return bin.tohex(temp)
end
function bin.HEXtoBin(hex,e)
	if e then
		return bin.new(string.reverse(bin.fromhex(hex)))
	else
		return bin.new(bin.fromhex(hex))
	end
end
function bin.HEXtoStr(hex,e)
	if e then
		return string.reverse(bin.fromhex(hex))
	else
		return bin.fromhex(hex)
	end
end
function bin:morph(a,b,d)
	if self:canStreamWrite() then
		local len=self:getlength()
		local temp=bin.newTempFile(self:sub(b+1,self:getlength()))
		self:streamwrite(d,a-1)
		print(temp:sub(1,temp:getlength()))
		self:setEndOfFile(len+(b-a)+#d)
		self:streamwrite(temp:sub(1,temp:getlength()),a-1)
		temp:remove()
	elseif self.Stream==false then
		if a and b then
			self.data=self:sub(1,a-1)..d..self:sub(b+1)
		else
			print("error both arguments must be numbers and the third a string")
		end
	end
end
function bin.endianflop(data,n)
	n=n or 1
	local tab={}
	for i=1,#data,n do
		table.insert(tab,1,string.sub(data,i,i+1))
	end
	return table.concat(tab)
end
function bin:scan(s,n,f)
	n=n or 1
	if self.Stream then
		for i=n,self:getlength() do
			if f then
				local temp=bin.new(self:sub(i,i+#s-1))
				temp:flipbits()
				if temp.data==s then
					return i,i+#s-1
				end
			else
				if self:sub(i,i+#s-1)==s then
					return i,i+#s-1
				end
			end
		end
	elseif self.Stream==false then
		if f then
			s=bin.new(s)
			s:flipbits()
			s=s.data
		end
		n=n or 1
		local a,b=string.find(self.data,s,n,true)
		return a,b
	end
end
function bin:fill(s,n)
	if self:canStreamWrite() then
		self:streamwrite(string.rep(s,n),0)
		self:setEndOfFile(n*#s)
	elseif self.Stream==false then
		self.data=string.rep(s,n)
	end
end
function bin:fillrandom(n)
	if self:canStreamWrite() then
		local t={}
		for i=1,n do
			table.insert(t,string.char(math.random(0,255)))
		end
		self:streamwrite(table.concat(t),0)
		self:setEndOfFile(n)
	elseif self.Stream==false then
		local t={}
		for i=1,n do
			table.insert(t,string.char(math.random(0,255)))
		end
		self.data=table.concat(t)
	end
end
function bin.packLLIB(name,tab,ext)
	local temp=bin.new()
	temp:addBlock("³Šž³–")
	temp:addBlock(bin.getVersion())
	temp:addBlock(tab)
	for i=1,#tab do
		temp:addBlock(tab[i])
		temp:addBlock(bin.load(tab[i]).data)
	end
	temp:addBlock("Done")
	temp:tofile(name.. ("."..ext or ".llib"))
end
function bin.unpackLLIB(name,exe,todir,over,ext)
	local temp=bin.load(name..("."..ext or ".llib"))
	local name=""
	Head=temp:getBlock("s")
	ver=temp:getBlock("s")
	infiles=temp:getBlock("t")
	if ver~=bin.getVersion() then
		print("Incompatable llib file")
		return nil
	end
	local tab={}
	while name~="Done" do
		name,data=temp:getBlock("s"),bin.new(temp:getBlock("s"))
		if string.find(name,".lua",1,true) then
			table.insert(tab,data.data)
		else
			if not(bin.fileExist((todir or "")..name) and not(over)) then
				data:tofile((todir or "")..name)
			end
		end
	end
	os.remove((todir or "").."Done")
	if exe then
		for i=1,#tab do
			assert(loadstring(tab[i]))()
		end
	end
	return infiles
end
function bin.fileExist(path)
	g=io.open(path or '','r')
	if path =="" then
		p="empty path"
		return nil
	end
	if g~=nil and true or false then
		p=(g~=nil and true or false)
	end
	if g~=nil then
		io.close(g)
	else
		return false
	end
	return p
end
function bin:shiftbits(n)
	if self:canStreamWrite() then
		n=n or 0
		if n>=0 then
			for i=0,self:getlength() do
				print(string.byte(self:sub(i,i))+n%256)
				self:streamwrite(string.char(string.byte(self:sub(i,i))+n%256),i-1)
			end
		else
			n=math.abs(n)
			for i=0,self:getlength() do
				self:streamwrite(string.char((string.byte(self:sub(i,i))+(256-n%256))%256),i-1)
			end
		end
	elseif self.Stream==false then
		n=n or 0
		if n>=0 then
			for i=1,self:getlength() do
				self:morph(i,i,string.char(string.byte(self:sub(i,i))+n%256))
			end
		else
			n=math.abs(n)
			for i=1,self:getlength() do
				self:morph(i,i,string.char((string.byte(self:sub(i,i))+(256-n%256))%256))
			end
		end
	end
end
function bin:shiftbit(n,i)
	if self:canStreamWrite() then
		i=i-1
		n=n or 0
		if n>=0 then
			self:streamwrite(string.char(string.byte(self:sub(i,i))+n%256),i)
		else
			n=math.abs(n)
			self:streamwrite(string.char((string.byte(self:sub(i,i))+(256-n%256))%256),i)
		end
	elseif self.Stream==false then
		n=n or 0
		if n>=0 then
			self:morph(i,i,string.char(string.byte(self:sub(i,i))+n%256))
		else
			n=math.abs(n)
			self:morph(i,i,string.char((string.byte(self:sub(i,i))+(256-n%256))%256))
		end
	end
end
function bin.decodeBits(par)
	if type(par)=="table" then
		if par.t=="bit" then
			return bin.new(par:toSbytes())
		end
	else
		if par:find(" ") then
			par=par:gsub(" ","")
		end
		local temp=bits.new()
		temp.data=par
		return bin.new((temp:toSbytes()):reverse())
	end
end
function bin.textToBinary(txt)
	return bin.new(bits.new(txt:reverse()):getBin())
end
--[[----------------------------------------
VFS
------------------------------------------]]
local _require = require
function require(path,vfs)
	if bin.fileExist(path..".lvfs") then
		local data = bin.loadVFS(path..".lvfs")
		if data:fileExist(vsf) then
			loadstring(data:readFile(vfs))()
		end
	else
		return _require(path)
	end
end
function bin.loadVFS(path)
	return bin.newVFS(bin.load(path):getBlock("t"))
end
function bin.copyDir(dir,todir)
	local vfs=bin.newVFS(dir,true)
	vfs:toFS(todir)
	vfs=nil
end
function bin.newVFS(t,l)
	if type(t)=="string" then
		t=io.parseDir(t,l)
	end
	local c={}
	c.FS= t or {}
	function c:merge(vfs)
		bin.newVFS(table.merge(self.FS,vfs.FS))
	end
	function c:mkdir(path)
		table.merge(self.FS,io.pathToTable(path))
	end
	function c:scanDir(path)
		path=path or ""
		local tab={}
		if path=="" then
			for i,v in pairs(self.FS) do
				tab[#tab+1]=i
			end
			return tab
		end
		spath=io.splitPath(path)
		local last=self.FS
		for i=1,#spath-1 do
			last=last[spath[i]]
		end
		return last[spath[#spath]]
	end
	function c:getFiles(path)
		if not self:dirExist(path) then return end
		path=path or ""
		local tab={}
		if path=="" then
			for i,v in pairs(self.FS) do
				if self:fileExist(i) then
					tab[#tab+1]=i
				end
			end
			return tab
		end
		spath=io.splitPath(path)
		local last=self.FS
		for i=1,#spath-1 do
			last=last[spath[i]]
		end
		local t=last[spath[#spath]]
		for i,v in pairs(t) do
			if self:fileExist(path.."/"..i) then
				tab[#tab+1]=path.."/"..i
			end
		end
		return tab
	end
	function c:getDirectories(path)
		if not self:dirExist(path) then return end
		path=path or ""
		local tab={}
		if path=="" then
			for i,v in pairs(self.FS) do
				if self:dirExist(i) then
					tab[#tab+1]=i
				end
			end
			return tab
		end
		spath=io.splitPath(path)
		local last=self.FS
		for i=1,#spath-1 do
			last=last[spath[i]]
		end
		local t=last[spath[#spath]]
		for i,v in pairs(t) do
			if self:dirExist(path.."/"..i) then
				tab[#tab+1]=path.."/"..i
			end
		end
		return tab
	end
	function c:mkfile(path,data)
		local name=io.getFullName(path)
		local temp=path:reverse()
		local a,b=temp:find("/")
		if not a then
			a,b=temp:find("\\")
		end
		if a then
			temp=temp:sub(a+1):reverse()
			path=temp
			local t,l=io.pathToTable(path)
			l[name]=data
			table.merge(self.FS,t)
		else
			self.FS[name]=data
		end
	end
	function c:remove(path)
		if path=="" or path==nil then return end
		spath=io.splitPath(path)
		local last=self.FS
		for i=1,#spath-1 do
			last=last[spath[i]]
		end
		last[spath[#spath]]=nil
	end
	function c:readFile(path)
		spath=io.splitPath(path)
		local last=self.FS
		for i=1,#spath do
			last=last[spath[i]]
		end
		if type(last)=="userdata" then
			last=last:read("*all")
		end
		return last
	end
	function c:copyFile(p1,p2)
		self:mkfile(p2,self:readFile(p1))
	end
	function c:moveFile(p1,p2)
		self:copyFile(p1,p2)
		self:remove(p1)
	end
	function c:fileExist(path)
		return type(self:readFile(path))=="string"
	end
	function c:dirExist(path)
		if path=="" or path==nil then return end
		spath=io.splitPath(path)
		local last=self.FS
		for i=1,#spath-1 do
			last=last[spath[i]]
		end
		if last[spath[#spath]]~=nil then
			if type(last[spath[#spath]])=="table" then
				return true
			end
		end
		return false
	end
	function c:tofile(path)
		local temp=bin.new()
		temp:addBlock(self.FS)
		temp:tofile(path)
	end
	function c:toFS(path)
		if path then
			if path:sub(-1,-1)~="\\" then
				path=path.."\\"
			elseif path:find("/") then
				path=path:gsub("/","\\")
			end
			io.mkDir(path)
		else
			path=""
		end
		function build(tbl, indent, folder)
			if not indent then indent = 0 end
			if not folder then folder = "" end
			for k, v in pairs(tbl) do
				formatting = string.rep(" ", indent) .. k .. ":"
				if type(v) == "table" then
					if v.t~=nil then
						io.mkFile(folder..k,v.data,"wb")
					else
						if not(io.dirExists(path..folder..string.sub(formatting,1,-2))) then
							io.mkDir(folder..string.sub(formatting,1,-2))
						end
						build(v,0,folder..string.sub(formatting,1,-2).."\\")
					end
				elseif type(v)=="string" then
					io.mkFile(folder..k,v,"wb")
				elseif type(v)=="userdata" then
					io.mkFile(folder..k,v:read("*all"),"wb")
				end
			end
		end
		build(self.FS,0,path)
	end
	function c:print()
		table.print(self.FS)
	end
	return c
end
--[[----------------------------------------
BITS
------------------------------------------]]
function bits.new(n)
	if type(n)=="string" then
		local t=tonumber(n,2)
		if not t then
			t={}
			for i=#n,1,-1 do
				table.insert(t,bits:conv(string.byte(n,i)))
			end
			n=table.concat(t)
		else
			n=t
		end
	end
	local temp={}
	temp.t="bit"
	setmetatable(temp, bits)
	if not type(n)=="string" then
		local tab={}
		while n>=1 do
			table.insert(tab,n%2)
			n=math.floor(n/2)
		end
		local str=string.reverse(table.concat(tab))
		if #str%8~=0 then
			str=string.rep("0",8-#str%8)..str
		end
		temp.data=str
	else
		temp.data=n
	end
	setmetatable({__tostring=function(self) return self.data end},temp)
	return temp
end
function bits:conv(n)
	local tab={}
	while n>=1 do
		table.insert(tab,n%2)
		n=math.floor(n/2)
	end
	local str=string.reverse(table.concat(tab))
	if #str%8~=0 then
		str=string.rep("0",8-#str%8)..str
	end
	return str
end
function bits:add(i)
	if type(i)=="number" then
		i=bits.new(i)
	end
	self.data=self:conv(tonumber(self.data,2)+tonumber(i.data,2))
end
function bits:sub(i)
	if type(i)=="number" then
		i=bits.new(i)
	end
	self.data=self:conv(tonumber(self.data,2)-tonumber(i.data,2))
end
function bits:multi(i)
	if type(i)=="number" then
		i=bits.new(i)
	end
	self.data=self:conv(tonumber(self.data,2)*tonumber(i.data,2))
end
function bits:div(i)
	if type(i)=="number" then
		i=bits.new(i)
	end
	self.data=self:conv(tonumber(self.data,2)/tonumber(i.data,2))
end
function bits:tonumber(s)
	if type(s)=="string" then
		return tonumber(self.data,2)
	end
	s=s or 1
	return tonumber(string.sub(self.data,(8*(s-1))+1,8*s),2) or error("Bounds!")
end
function bits:isover()
	return #self.data>8
end
function bits:flipbits()
	tab={}
	for i=1,#self.data do
		if string.sub(self.data,i,i)=="1" then
			table.insert(tab,"0")
		else
			table.insert(tab,"1")
		end
	end
	self.data=table.concat(tab)
end
function bits:tobytes()
	local tab={}
	for i=self:getbytes(),1,-1 do
		table.insert(tab,string.char(self:tonumber(i)))
	end
	return bin.new(table.concat(tab))
end
function bits:toSbytes()
	local tab={}
	for i=self:getbytes(),1,-1 do
		table.insert(tab,string.char(self:tonumber(i)))
	end
	return table.concat(tab)
end
function bits:getBin()
	return self.data
end
function bits:getbytes()
	print(self.data)
	return #self.data/8
end

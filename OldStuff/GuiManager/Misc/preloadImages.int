_GuiPro.jobqueue.OnJobCompleted(function(JOBID,n,i,t)
	if t~="PRE" then return end
	_GuiPro.imagecache[i]=n
end)
function gui:preloadImages(tab)
	local t
	if type(tab)=="string" then
		t = {tab}
	else
		t = tab
	end
	for i = 1,#t do
		_GuiPro.jobqueue:pushJob("LoadImage",t[i],"PRE")
	end
end